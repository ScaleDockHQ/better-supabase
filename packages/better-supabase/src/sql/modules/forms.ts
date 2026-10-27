import type { FormsEvents } from "../../blocks/forms/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockContributes } from "../contributions.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { isRecord } from "../../core/guards.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  addExtraColumns,
  extraFieldsJson,
  fail,
  lockTable,
  pageSize,
  schemaPreamble,
  SERVICE_CALLER,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import { subjectReadable, subjectsOption } from "../subjects.ts";
import { DURATION } from "./approvals-policies.ts";
import { formNpsFunction } from "./forms-nps.ts";
import { formSchemaFunctions, formScoringFunctions } from "./forms-schema.ts";
import { OPERATIONS } from "./permissions-model.ts";
import { liveShareLink, shareLinkRow } from "./share-links.ts";

/** The share-links subject type of a public form link. */
const FORM_SUBJECT = "form";

/** The share-links role a public form link carries. */
const FORM_LINK_ROLE = "respond";

const WHERE = "blocks.forms.options";
const SUBJECT_PAYLOAD = ["organizationId", "subjectType", "subjectId"] as const;

const EVENTS: BlockSqlEvents<FormsEvents> = {
  "form.created": {
    subject: "forms",
    payload: ["organizationId", "id", "key"],
  },
  "form_version.published": {
    subject: "forms",
    payload: ["organizationId", "id", "formId", "number"],
  },
  "form_submission.submitted": {
    subject: "form-submissions",
    payload: [
      ...SUBJECT_PAYLOAD,
      "id",
      "formId",
      "versionId",
      "source",
      "score",
      "maxScore",
      "passed",
    ],
  },
  "form_submission.reviewed": {
    subject: "form-submissions",
    payload: [...SUBJECT_PAYLOAD, "id", "formId", "status"],
  },
  "form_submission.deleted": {
    subject: "form-submissions",
    payload: [...SUBJECT_PAYLOAD, "id", "formId"],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    form: {
      table: "forms",
      singular: "form",
      primary: true,
      subject: {
        title: "title",
        permissions: { read: "read", write: "manage" },
      },
    },
  },
  events: EVENTS,
  hooks: [
    "before_form_publish",
    "after_form_publish",
    "before_form_submission",
    "after_form_submission",
    "before_public_form_submission",
  ],
  options: ["handlers", "publicLimit", "extraColumns"],
  tables: {
    forms: {
      name: "forms",
      app: {},
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        key: "key",
        title: "title",
        description: "description",
        status: "status",
        currentVersion: "current_version_id",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      typed: ["status"],
    },
    versions: {
      name: "form_versions",
      app: {},
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        form: "form_id",
        number: "number",
        definition: "definition",
        schema: "schema",
        createdBy: "created_by",
        createdAt: "created_at",
      },
    },
    submissions: {
      name: "form_submissions",
      app: {},
      lifecycle: { tenant: "tenant", user: "respondent", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        form: "form_id",
        version: "version_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        respondent: "respondent_id",
        answers: "answers",
        status: "status",
        source: "source",
        reviewedBy: "reviewed_by",
        reviewedAt: "reviewed_at",
        createdAt: "created_at",
        submittedAt: "submitted_at",
        updatedAt: "updated_at",
        score: "score",
        maxScore: "max_score",
        passed: "passed",
      },
      optional: ["score", "maxScore", "passed"],
      typed: ["status"],
    },
    answerKeys: {
      name: "form_answer_keys",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        version: "version_id",
        tenant: "tenant_id",
        answers: "answers",
        createdAt: "created_at",
      },
      optionalTable: true,
      app: { onlyWhenMapped: true },
    },
  },
};

/** The buckets `form_nps` groups periods by. */

const FORM_KEY = /^[a-z][a-z0-9_-]{0,62}$/;
const FUNCTION = /^[a-z_][a-z0-9_]*(\.[a-z_][a-z0-9_]*)?$/;

const functionName = (name: string): string =>
  name.includes(".")
    ? name
        .split(".")
        .map((part) => sqlIdent(part))
        .join(".")
    : `public.${sqlIdent(name)}`;

/**
 * `options.handlers`: form key to `schema.function(submission_id uuid) returns
 * jsonb`.
 */
function handlersOf(
  ctx: BlockSqlContext,
): readonly (readonly [string, string])[] {
  const raw = ctx.option("handlers");

  if (raw === undefined) {
    return [];
  }

  if (!isRecord(raw)) {
    throw new TypeError(
      `${WHERE}.handlers must map form keys to functions, such as { contact: "public.lead_from_submission" }`,
    );
  }

  return Object.entries(raw).map(([key, fn]) => {
    if (!FORM_KEY.test(key)) {
      throw new TypeError(`${WHERE}.handlers: "${key}" is not a form key`);
    }

    if (typeof fn !== "string" || !FUNCTION.test(fn)) {
      throw new TypeError(
        `${WHERE}.handlers.${key} must name a function, such as public.lead_from_submission`,
      );
    }

    return [key, fn] as const;
  });
}

interface PublicLimit {
  readonly max: number;
  readonly period: string;
}

/** `options.publicLimit`: public submissions per form and caller, or `false`. */
function publicLimitOf(ctx: BlockSqlContext): PublicLimit | undefined {
  const raw = ctx.option("publicLimit");

  if (raw === false) {
    return undefined;
  }

  if (raw === undefined) {
    return { max: 20, period: "PT1H" };
  }

  const max = isRecord(raw) ? raw["max"] : undefined;
  const period = isRecord(raw) ? raw["period"] : undefined;

  if (
    typeof max !== "number" ||
    !Number.isInteger(max) ||
    max < 1 ||
    typeof period !== "string" ||
    !DURATION.test(period)
  ) {
    throw new TypeError(
      `${WHERE}.publicLimit must be false or { max, period } with a whole max and an ISO 8601 period such as PT1H`,
    );
  }

  return { max, period };
}

/** Scoring needs the score columns, which `columns` can map to `null`. */
function scoringOn(ctx: BlockSqlContext): boolean {
  return ["score", "maxScore", "passed"].every((column) =>
    ctx.has("submissions", column),
  );
}

/**
 * PL/pgSQL that raises 23514 with the schema errors, as the jsonb-schemas
 * checks do.
 */
const answersInvalid = (table: string): string =>
  `raise exception '%.answers does not match its JSON Schema: %', ${sqlString(table)}, array_to_string(v_errors, '; ')
      using errcode = '23514', column = 'answers', detail = to_jsonb(v_errors)::text, hint = 'JSON_SCHEMA_INVALID';`;

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const forms = ctx.table("forms");
  const versions = ctx.table("versions");
  const submissions = ctx.table("submissions");
  const f = (column: string): string => ctx.col("forms", column);
  const v = (column: string): string => ctx.col("versions", column);
  const s = (column: string): string => ctx.col("submissions", column);
  const fn = (name: string): string => ctx.fn(name);
  const read = ctx.permission("read", OPERATIONS["forms.read"]);
  const manage = ctx.permission("manage", OPERATIONS["forms.manage"]);
  const submit = ctx.permission("submit", OPERATIONS["forms.submit"]);
  const review = ctx.permission("review", OPERATIONS["forms.review"]);
  const subjects = subjectsOption(ctx);
  const handlers = handlersOf(ctx);
  const limit = publicLimitOf(ctx);
  const shares = ctx.installed("share-links");
  const extras = ctx.extraColumns("forms", ["version"]);
  const scoring = scoringOn(ctx);
  const keys = scoring ? ctx.table("answerKeys") : "";
  const k = (column: string): string => ctx.col("answerKeys", column);
  const notFound = fail("FORM_NOT_FOUND", "form not found", "P0002");

  const submissionNotFound = fail(
    "FORM_SUBMISSION_NOT_FOUND",
    "submission not found",
    "P0002",
  );

  const formJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${f("id")}, 'organizationId', ${row}.${f("tenant")}, 'key', ${row}.${f("key")}, 'title', ${row}.${f("title")}, 'description', ${row}.${f("description")}, 'status', ${row}.${f("status")}, 'currentVersionId', ${row}.${f("currentVersion")}, 'createdBy', ${row}.${f("createdBy")}, 'createdAt', ${row}.${f("createdAt")}, 'updatedAt', ${row}.${f("updatedAt")}${extraFieldsJson(row, extras)})`;

  /**
   * The definition of version `row`: with its answer key put back when
   * `managers` and the caller manages forms, without it otherwise.
   */
  const definitionOf = (row: string, managers: boolean): string =>
    scoring && managers
      ? `case when ${SERVICE_CALLER} or ${ctx.can("tenant", `${row}.${v("tenant")}`, manage)}
        then ${fn("form_answer_merge")}(${row}.${v("definition")}, (select a.${k("answers")} from ${keys} a where a.${k("version")} = ${row}.${v("id")}))
        else ${row}.${v("definition")} end`
      : `${row}.${v("definition")}`;

  const versionJson = (row: string, managers = true): string =>
    `jsonb_build_object('id', ${row}.${v("id")}, 'formId', ${row}.${v("form")}, 'number', ${row}.${v("number")}, 'definition', ${definitionOf(row, managers)}, 'schema', ${row}.${v("schema")}, 'createdBy', ${row}.${v("createdBy")}, 'createdAt', ${row}.${v("createdAt")})`;

  const scoreJson = (row: string): string =>
    scoring
      ? `, 'score', ${row}.${s("score")}, 'maxScore', ${row}.${s("maxScore")}, 'passed', ${row}.${s("passed")}`
      : "";

  const submissionJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${s("id")}, 'organizationId', ${row}.${s("tenant")}, 'formId', ${row}.${s("form")}, 'versionId', ${row}.${s("version")}, 'subjectType', ${row}.${s("subjectType")}, 'subjectId', ${row}.${s("subjectId")}, 'respondentId', ${row}.${s("respondent")}, 'answers', ${row}.${s("answers")}, 'status', ${row}.${s("status")}, 'source', ${row}.${s("source")}, 'reviewedBy', ${row}.${s("reviewedBy")}, 'reviewedAt', ${row}.${s("reviewedAt")}, 'createdAt', ${row}.${s("createdAt")}, 'submittedAt', ${row}.${s("submittedAt")}, 'updatedAt', ${row}.${s("updatedAt")}${scoreJson(row)})`;

  const subjectOf = (row: string): string =>
    `'subjectType', coalesce(${row}.${s("subjectType")}, ${sqlString(FORM_SUBJECT)}), 'subjectId', coalesce(${row}.${s("subjectId")}, ${row}.${s("form")}::text)`;

  const submissionRecord = (
    type: string,
    row: string,
    extra: string,
    audit: boolean,
  ): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${s("tenant")}, ${subjectOf(row)}, 'id', ${row}.${s("id")}, 'formId', ${row}.${s("form")}${extra})`,
      subject: `'form-submissions/' || ${row}.${s("id")}::text`,
      tenant: `${row}.${s("tenant")}`,
      audit: audit
        ? {
            category: "data",
            targetType: "form_submission",
            recordId: `${row}.${s("id")}::text`,
          }
        : false,
    });

  const handlerCase =
    handlers.length === 0
      ? ""
      : `
    if v_row.${s("subjectType")} is null then
      case v_form.${f("key")}
${handlers.map(([key, name]) => `        when ${sqlString(key)} then v_link := ${functionName(name)}(v_row.${s("id")});`).join("\n")}
        else v_link := null;
      end case;
      if v_link ->> 'subjectType' is not null and v_link ->> 'subjectId' is not null then
        update ${submissions} x
          set ${s("subjectType")} = v_link ->> 'subjectType', ${s("subjectId")} = v_link ->> 'subjectId'
          where x.${s("id")} = v_row.${s("id")}
          returning * into v_row;
      end if;
    end if;`;

  const links = shares ? ctx.of("share-links") : undefined;

  const linkCheck = (token: string): string => {
    if (links === undefined) {
      return "";
    }

    const l = (column: string): string => links.col("links", column);

    return `select x.${f("id")} into v_form_id
  from ${links.table("links")} k
  join ${forms} x on x.${f("id")}::text = k.${l("subjectId")} and x.${f("tenant")} = k.${l("tenant")}
  where ${liveShareLink(links, "k", token, sqlString(FORM_SUBJECT))}
    and k.${l("role")} = ${sqlString(FORM_LINK_ROLE)};
  if v_form_id is null then
    ${fail("FORM_LINK_INVALID", "this form link isn't valid", "P0002")}
  end if;`;
  };

  const rateLimit =
    limit === undefined || !ctx.installed("rate-limit")
      ? ""
      : `
  v_headers := nullif(current_setting('request.headers', true), '')::jsonb;
  v_caller := coalesce(auth.uid()::text, 'ip:' || coalesce(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 'unknown'));
  select h.allowed, h.retry_after into v_allowed, v_retry
    from ${ctx.of("rate-limit").fn("hit_rate_limit")}('forms:' || v_form_id::text, v_caller, ${String(limit.max)}, ${sqlString(limit.period)}::interval) h;
  if not v_allowed then
    raise sqlstate 'PGRST' using
      message = json_build_object(
        'code', 'BS429',
        'message', ${sqlString(`Rate limit for this form exceeded: ${String(limit.max)} submissions per ${limit.period}`)},
        'details', format('Retry after %s seconds.', v_retry),
        'hint', null
      )::text,
      detail = json_build_object(
        'status', 429,
        'status_text', 'Too Many Requests',
        'headers', json_build_object('Retry-After', v_retry::text)
      )::text;
  end if;`;

  const tables = ctx.manages
    ? `create table if not exists ${forms} (
  ${f("id")} uuid primary key default gen_random_uuid(),
  ${f("tenant")} ${ctx.idType} not null,
  ${f("key")} text not null check (${f("key")} ~ '^[a-z][a-z0-9_-]{0,62}$'),
  ${f("title")} text not null check (length(${f("title")}) between 1 and 200),
  ${f("description")} text check (${f("description")} is null or length(${f("description")}) <= 2000),
  ${f("status")} text not null default 'draft' check (${f("status")} in ('draft', 'open', 'closed', 'archived')),
  ${f("currentVersion")} uuid,
  ${f("createdBy")} uuid,
  ${f("createdAt")} timestamptz not null default now(),
  ${f("updatedAt")} timestamptz not null default now(),
  unique (${f("tenant")}, ${f("key")})
);${addExtraColumns(forms, extras)}
${lockTable(forms, { read: true })}
${renderPolicy(makePolicy({ table: forms, name: ctx.naming.rename("forms_read"), command: "select", roles: ["authenticated"], using: ctx.scope.check(f("tenant"), read) }), { drop: true, target: forms })}

create table if not exists ${versions} (
  ${v("id")} uuid primary key default gen_random_uuid(),
  ${v("tenant")} ${ctx.idType} not null,
  ${v("form")} uuid not null references ${forms} (${f("id")}) on delete cascade,
  ${v("number")} integer not null check (${v("number")} > 0),
  ${v("definition")} jsonb not null,
  ${v("schema")} jsonb not null,
  ${v("createdBy")} uuid,
  ${v("createdAt")} timestamptz not null default now(),
  unique (${v("form")}, ${v("number")})
);
${lockTable(versions, { read: true })}
${renderPolicy(makePolicy({ table: versions, name: ctx.naming.rename("form_versions_read"), command: "select", roles: ["authenticated"], using: ctx.scope.check(v("tenant"), read) }), { drop: true, target: versions })}

create table if not exists ${submissions} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("tenant")} ${ctx.idType} not null,
  ${s("form")} uuid not null references ${forms} (${f("id")}) on delete cascade,
  ${s("version")} uuid not null references ${versions} (${v("id")}) on delete cascade,
  ${s("subjectType")} text,
  ${s("subjectId")} text,
  ${s("respondent")} uuid,
  ${s("answers")} jsonb not null default '{}'::jsonb check (jsonb_typeof(${s("answers")}) = 'object' and octet_length(${s("answers")}::text) <= 1048576),
  ${s("status")} text not null default 'submitted' check (${s("status")} in ('draft', 'submitted', 'accepted', 'rejected')),
  ${s("source")} text not null default 'member' check (${s("source")} in ('member', 'public', 'service')),
  ${s("reviewedBy")} uuid,
  ${s("reviewedAt")} timestamptz,
  ${s("createdAt")} timestamptz not null default now(),
  ${s("submittedAt")} timestamptz,
  ${s("updatedAt")} timestamptz not null default now(),
  check ((${s("subjectType")} is null) = (${s("subjectId")} is null))
);
create index if not exists ${sqlIdent(ctx.naming.rename(`${ctx.tableName("submissions").name}_form_idx`))} on ${submissions} (${s("form")}, ${s("createdAt")} desc);
create index if not exists ${sqlIdent(`${ctx.tableName("submissions").name}_version_idx`)} on ${submissions} (${s("version")});
create index if not exists ${sqlIdent(`${ctx.tableName("submissions").name}_respondent_idx`)} on ${submissions} (${s("respondent")}) where ${s("respondent")} is not null;
create index if not exists ${sqlIdent(`${ctx.tableName("submissions").name}_subject_idx`)} on ${submissions} (${s("subjectType")}, ${s("subjectId")}) where ${s("subjectType")} is not null;
${lockTable(submissions, { read: true })}
${renderPolicy(makePolicy({ table: submissions, name: ctx.naming.rename("form_submissions_read"), command: "select", roles: ["authenticated"], using: `${ctx.scope.check(s("tenant"), review)} or ${s("respondent")} = (select auth.uid())` }), { drop: true, target: submissions })}
alter table ${submissions} add column if not exists ${s("score")} numeric;
alter table ${submissions} add column if not exists ${s("maxScore")} numeric;
alter table ${submissions} add column if not exists ${s("passed")} boolean;

-- The correct answers of a scored version, which only definer functions read.
create table if not exists ${keys} (
  ${k("version")} uuid primary key references ${versions} (${v("id")}) on delete cascade,
  ${k("tenant")} ${ctx.idType} not null,
  ${k("answers")} jsonb not null check (jsonb_typeof(${k("answers")}) = 'object'),
  ${k("createdAt")} timestamptz not null default now()
);
${lockTable(keys)}
`
    : "";

  return `${schemaPreamble(ctx)}
${tables}
${formSchemaFunctions(ctx)}
${formScoringFunctions(ctx)}
-- Creates a draft form. fields sets the extra columns by name.
drop function if exists ${fn("create_form")}(${ctx.idType}, text, text, text);
create or replace function ${fn("create_form")}(tenant ${ctx.idType}, key text, title text, description text default null, fields jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${forms}%rowtype;
begin
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "create_form.tenant", manage)}) then
    ${fail("FORM_FORBIDDEN", "not allowed to manage forms")}
  end if;
  if create_form.key is null or create_form.key !~ '^[a-z][a-z0-9_-]{0,62}$' then
    ${fail("FORM_KEY_INVALID", "a form key is lowercase letters, digits, - and _, starting with a letter", "22023")}
  end if;
  if exists (select 1 from ${forms} x where x.${f("tenant")} = create_form.tenant and x.${f("key")} = create_form.key) then
    ${fail("FORM_KEY_TAKEN", "a form with this key exists", "23505")}
  end if;
  insert into ${forms} (${f("tenant")}, ${f("key")}, ${f("title")}, ${f("description")}, ${f("createdBy")})
  values (create_form.tenant, create_form.key, create_form.title, create_form.description, auth.uid())
  returning * into v_row;${writeExtraColumns(forms, extras, "create_form.fields", `x.${f("id")} = v_row.${f("id")}`, "v_row")}
  ${ctx.record({
    type: "form.created",
    payload: `jsonb_build_object('organizationId', v_row.${f("tenant")}, 'id', v_row.${f("id")}, 'key', v_row.${f("key")})`,
    subject: `'forms/' || v_row.${f("id")}::text`,
    tenant: `v_row.${f("tenant")}`,
    audit: {
      category: "configuration",
      targetType: "form",
      recordId: `v_row.${f("id")}::text`,
      targetLabel: `v_row.${f("title")}`,
    },
  })}
  return ${formJson("v_row")};
end;
$$;
${userGrant(`${fn("create_form")}(${ctx.idType}, text, text, text, jsonb)`)}

-- Changes the title, description, status or the extra columns in fields.
-- A form opens for submissions once it has a published version.
drop function if exists ${fn("update_form")}(uuid, text, text, text);
create or replace function ${fn("update_form")}(form_id uuid, title text default null, description text default null, status text default null, fields jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${forms}%rowtype;
begin
  select * into v_row from ${forms} x where x.${f("id")} = update_form.form_id for update;
  if not found then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", `v_row.${f("tenant")}`, manage)}) then
    ${fail("FORM_FORBIDDEN", "not allowed to manage forms")}
  end if;
  if update_form.status is not null and update_form.status not in ('open', 'closed', 'archived') then
    ${fail("FORM_STATUS_INVALID", "status is open, closed or archived", "22023")}
  end if;
  if update_form.status = 'open' and v_row.${f("currentVersion")} is null then
    ${fail("FORM_NOT_PUBLISHED", "publish a version before opening the form", "55000")}
  end if;
  update ${forms} x set
    ${f("title")} = coalesce(update_form.title, x.${f("title")}),
    ${f("description")} = coalesce(update_form.description, x.${f("description")}),
    ${f("status")} = coalesce(${ctx.cast("forms", "status", "update_form.status")}, x.${f("status")}),
    ${f("updatedAt")} = now()
  where x.${f("id")} = update_form.form_id
  returning * into v_row;${writeExtraColumns(forms, extras, "update_form.fields", `x.${f("id")} = v_row.${f("id")}`, "v_row")}
  return ${formJson("v_row")};
end;
$$;
${userGrant(`${fn("update_form")}(uuid, text, text, text, jsonb)`)}

-- Publishes a new version: checks the definition, copies custom fields in,
-- builds the version's JSON Schema and makes it current. A draft form opens.
create or replace function ${fn("publish_form_version")}(form_id uuid, definition jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_form ${forms}%rowtype;
  v_resolved jsonb;
  v_split jsonb;
  v_number integer;
  v_row ${versions}%rowtype;
begin
  select * into v_form from ${forms} x where x.${f("id")} = publish_form_version.form_id for update;
  if not found then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", `v_form.${f("tenant")}`, manage)}) then
    ${fail("FORM_FORBIDDEN", "not allowed to manage forms")}
  end if;
  ${ctx.hook("before_form_publish", [
    ["uuid", "publish_form_version.form_id"],
    ["jsonb", "publish_form_version.definition"],
  ])}
  v_resolved := ${fn("form_resolve")}(v_form.${f("tenant")}, publish_form_version.definition);
  v_split := ${fn("form_answer_split")}(v_resolved);
  if v_split -> 'key' <> '{}'::jsonb then
    ${
      scoring
        ? "v_resolved := v_split -> 'definition';"
        : fail(
            "FORM_SCORING_UNAVAILABLE",
            "scoring needs the form_answer_keys table and the score columns on form_submissions",
            "0A000",
          )
    }
  end if;
  select coalesce(max(x.${v("number")}), 0) + 1 into v_number from ${versions} x where x.${v("form")} = v_form.${f("id")};
  insert into ${versions} (${v("tenant")}, ${v("form")}, ${v("number")}, ${v("definition")}, ${v("schema")}, ${v("createdBy")})
  values (v_form.${f("tenant")}, v_form.${f("id")}, v_number, v_resolved, ${fn("form_schema")}(v_resolved), auth.uid())
  returning * into v_row;${
    scoring
      ? `
  if v_split -> 'key' <> '{}'::jsonb then
    insert into ${keys} (${k("version")}, ${k("tenant")}, ${k("answers")})
    values (v_row.${v("id")}, v_row.${v("tenant")}, v_split -> 'key');
  end if;`
      : ""
  }
  update ${forms} x set
    ${f("currentVersion")} = v_row.${v("id")},
    ${f("status")} = case when x.${f("status")} = 'draft' then 'open' else x.${f("status")} end,
    ${f("updatedAt")} = now()
  where x.${f("id")} = v_form.${f("id")};
  ${ctx.record({
    type: "form_version.published",
    payload: `jsonb_build_object('organizationId', v_row.${v("tenant")}, 'id', v_row.${v("id")}, 'formId', v_row.${v("form")}, 'number', v_row.${v("number")})`,
    subject: `'forms/' || v_row.${v("form")}::text`,
    tenant: `v_row.${v("tenant")}`,
    audit: {
      category: "configuration",
      targetType: "form",
      recordId: `v_row.${v("form")}::text`,
      targetLabel: `v_form.${f("title")}`,
      summary: `'published version ' || v_row.${v("number")}::text`,
    },
  })}
  ${ctx.hook("after_form_publish", [["uuid", `v_row.${v("id")}`]])}
  return ${versionJson("v_row")};
end;
$$;
${userGrant(`${fn("publish_form_version")}(uuid, jsonb)`)}

create or replace function ${fn("get_form")}(form_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${forms}%rowtype;
  v_version ${versions}%rowtype;
begin
  select * into v_row from ${forms} x where x.${f("id")} = get_form.form_id;
  if not found then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", `v_row.${f("tenant")}`, read)}) then
    ${fail("FORM_FORBIDDEN", "not allowed to read this form")}
  end if;
  select * into v_version from ${versions} x where x.${v("id")} = v_row.${f("currentVersion")};
  return ${formJson("v_row")} || jsonb_build_object('version', case when v_version.${v("id")} is null then null else ${versionJson("v_version")} end);
end;
$$;
${userGrant(`${fn("get_form")}(uuid)`)}

create or replace function ${fn("get_form_version")}(version_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${versions}%rowtype;
begin
  select * into v_row from ${versions} x where x.${v("id")} = get_form_version.version_id;
  if not found then
    ${fail("FORM_VERSION_NOT_FOUND", "form version not found", "P0002")}
  end if;
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", `v_row.${v("tenant")}`, read)}) then
    ${fail("FORM_FORBIDDEN", "not allowed to read this form")}
  end if;
  return ${versionJson("v_row")};
end;
$$;
${userGrant(`${fn("get_form_version")}(uuid)`)}

create or replace function ${fn("list_forms")}(tenant ${ctx.idType}, status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "list_forms.tenant", read)}) then
    ${fail("FORM_FORBIDDEN", "not allowed to read forms")}
  end if;
  select coalesce(jsonb_agg(${formJson("x")} order by x.${f("createdAt")} desc), '[]'::jsonb) into v_rows
  from ${forms} x
  where x.${f("tenant")} = list_forms.tenant
    and (list_forms.status is null or x.${f("status")}::text = list_forms.status);
  return v_rows;
end;
$$;
${userGrant(`${fn("list_forms")}(${ctx.idType}, text)`)}

-- Writes a submission against the form's current version, validating the
-- answers unless it is a draft. Only definer functions of this module call it.
create or replace function ${fn("form_submission_save")}(form_id uuid, answers jsonb, subject_type text, subject_id text, respondent uuid, source text, draft boolean, submission_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_form ${forms}%rowtype;
  v_schema jsonb;${
    scoring
      ? `
  v_definition jsonb;
  v_grade jsonb;`
      : ""
  }
  v_errors text[];
  v_row ${submissions}%rowtype;
  v_link jsonb;
begin
  select * into v_form from ${forms} x where x.${f("id")} = form_submission_save.form_id;
  if not found then
    ${notFound}
  end if;
  if v_form.${f("status")} <> 'open' then
    ${fail("FORM_CLOSED", "this form isn't taking submissions", "55000")}
  end if;
  if jsonb_typeof(form_submission_save.answers) is distinct from 'object' then
    ${fail("FORM_ANSWERS_INVALID", "answers must be an object", "22023")}
  end if;
  ${ctx.hook("before_form_submission", [
    ["uuid", "form_submission_save.form_id"],
    ["jsonb", "form_submission_save.answers"],
  ])}
  if not form_submission_save.draft then
    select x.${v("schema")}${scoring ? `, x.${v("definition")}` : ""} into v_schema${scoring ? ", v_definition" : ""} from ${versions} x where x.${v("id")} = v_form.${f("currentVersion")};
    v_errors := extensions.jsonschema_validation_errors(v_schema::json, form_submission_save.answers::json);
    if cardinality(v_errors) > 0 then
      ${answersInvalid(ctx.tableName("submissions").name)}
    end if;${
      scoring
        ? `
    v_grade := ${fn("form_score")}(v_definition, (select a.${k("answers")} from ${keys} a where a.${k("version")} = v_form.${f("currentVersion")}), form_submission_save.answers);`
        : ""
    }
  end if;
  if form_submission_save.submission_id is not null then
    select * into v_row from ${submissions} x where x.${s("id")} = form_submission_save.submission_id for update;
    if not found or v_row.${s("form")} <> form_submission_save.form_id or v_row.${s("respondent")} is distinct from form_submission_save.respondent then
      ${submissionNotFound}
    end if;
    if v_row.${s("status")} <> 'draft' then
      ${fail("FORM_SUBMISSION_LOCKED", "only a draft submission can change", "55000")}
    end if;
    update ${submissions} x set
      ${s("version")} = v_form.${f("currentVersion")},
      ${s("answers")} = form_submission_save.answers,
      ${s("status")} = ${ctx.cast("submissions", "status", "case when form_submission_save.draft then 'draft' else 'submitted' end")},
      ${s("submittedAt")} = case when form_submission_save.draft then null else now() end,
      ${s("subjectType")} = coalesce(form_submission_save.subject_type, x.${s("subjectType")}),
      ${s("subjectId")} = coalesce(form_submission_save.subject_id, x.${s("subjectId")}),${
        scoring
          ? `
      ${s("score")} = (v_grade ->> 'score')::numeric,
      ${s("maxScore")} = (v_grade ->> 'maxScore')::numeric,
      ${s("passed")} = (v_grade ->> 'passed')::boolean,`
          : ""
      }
      ${s("updatedAt")} = now()
    where x.${s("id")} = form_submission_save.submission_id
    returning * into v_row;
  else
    insert into ${submissions} (${s("tenant")}, ${s("form")}, ${s("version")}, ${s("subjectType")}, ${s("subjectId")}, ${s("respondent")}, ${s("answers")}, ${s("status")}, ${s("source")}, ${s("submittedAt")}${scoring ? `, ${s("score")}, ${s("maxScore")}, ${s("passed")}` : ""})
    values (v_form.${f("tenant")}, v_form.${f("id")}, v_form.${f("currentVersion")}, form_submission_save.subject_type, form_submission_save.subject_id, form_submission_save.respondent, form_submission_save.answers,
      case when form_submission_save.draft then 'draft' else 'submitted' end, form_submission_save.source,
      case when form_submission_save.draft then null else now() end${scoring ? ", (v_grade ->> 'score')::numeric, (v_grade ->> 'maxScore')::numeric, (v_grade ->> 'passed')::boolean" : ""})
    returning * into v_row;
  end if;
  if not form_submission_save.draft then${handlerCase}
    ${submissionRecord("form_submission.submitted", "v_row", `, 'versionId', v_row.${s("version")}, 'source', v_row.${s("source")}${scoring ? `, 'score', v_row.${s("score")}, 'maxScore', v_row.${s("maxScore")}, 'passed', v_row.${s("passed")}` : ", 'score', null, 'maxScore', null, 'passed', null"}`, false)}
    ${ctx.hook("after_form_submission", [["uuid", `v_row.${s("id")}`]])}
  end if;
  return ${submissionJson("v_row")};
end;
$$;
revoke execute on function ${fn("form_submission_save")}(uuid, jsonb, text, text, uuid, text, boolean, uuid) from public, anon, authenticated;

-- Submits answers as the caller, or saves them as a draft to finish later
-- (submission_id continues one). A subject links the submission to a record
-- the caller can read.
create or replace function ${fn("submit_form")}(form_id uuid, answers jsonb, subject_type text default null, subject_id text default null, submission_id uuid default null, draft boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select x.${f("tenant")} into v_tenant from ${forms} x where x.${f("id")} = submit_form.form_id;
  if not found then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or (auth.uid() is not null and ${ctx.can("tenant", "v_tenant", submit)})) then
    ${fail("FORM_FORBIDDEN", "not allowed to submit this form")}
  end if;
  if (submit_form.subject_type is null) <> (submit_form.subject_id is null) then
    ${fail("FORM_SUBJECT_INVALID", "pass both subject_type and subject_id, or neither", "22023")}
  end if;
  if submit_form.subject_type is not null and not (${SERVICE_CALLER} or ${subjectReadable(ctx, subjects, { type: "submit_form.subject_type", id: "submit_form.subject_id", tenant: "v_tenant" })}) then
    ${fail("FORM_FORBIDDEN", "not allowed to link this record")}
  end if;
  return ${fn("form_submission_save")}(submit_form.form_id, submit_form.answers, submit_form.subject_type, submit_form.subject_id, auth.uid(),
    case when ${SERVICE_CALLER} then 'service' else 'member' end, coalesce(submit_form.draft, false), submit_form.submission_id);
end;
$$;
${userGrant(`${fn("submit_form")}(uuid, jsonb, text, text, uuid, boolean)`)}
${
  shares
    ? `
-- The open form a public link (a share link to subject type '${FORM_SUBJECT}' with
-- role '${FORM_LINK_ROLE}') points at, with its current version.
create or replace function ${fn("get_public_form")}(token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_form_id uuid;
  v_row ${forms}%rowtype;
  v_version ${versions}%rowtype;
begin
  ${linkCheck("get_public_form.token")}
  select * into v_row from ${forms} x where x.${f("id")} = v_form_id;
  if v_row.${f("status")} <> 'open' then
    ${fail("FORM_CLOSED", "this form isn't taking submissions", "55000")}
  end if;
  select * into v_version from ${versions} x where x.${v("id")} = v_row.${f("currentVersion")};
  return jsonb_build_object('id', v_row.${f("id")}, 'title', v_row.${f("title")}, 'description', v_row.${f("description")}, 'version', ${versionJson("v_version", false)} - 'createdBy');
end;
$$;
revoke all on function ${fn("get_public_form")}(text) from public;
grant execute on function ${fn("get_public_form")}(text) to anon, authenticated, service_role;

-- Submits answers through a public link. Each caller (the user, else the
-- right-most x-forwarded-for hop) gets options.publicLimit submissions per
-- form when the rate-limit module is installed, and before_public_form_submission
-- receives the bot-check token to refuse it.
create or replace function ${fn("submit_public_form")}(token text, answers jsonb, bot_token text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_form_id uuid;
  v_headers jsonb;
  v_caller text;
  v_allowed boolean;
  v_retry integer;
  v_result jsonb;
begin
  ${linkCheck("submit_public_form.token")}${rateLimit}
  ${ctx.hook("before_public_form_submission", [
    ["uuid", "v_form_id"],
    ["jsonb", "submit_public_form.answers"],
    ["text", "submit_public_form.bot_token"],
  ])}
  v_result := ${fn("form_submission_save")}(v_form_id, submit_public_form.answers, null, null, auth.uid(), 'public', false, null);
  return jsonb_build_object('id', v_result -> 'id', 'status', v_result -> 'status', 'submittedAt', v_result -> 'submittedAt');
end;
$$;
revoke all on function ${fn("submit_public_form")}(text, jsonb, text) from public;
grant execute on function ${fn("submit_public_form")}(text, jsonb, text) to anon, authenticated, service_role;
`
    : ""
}
create or replace function ${fn("get_form_submission")}(submission_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${submissions}%rowtype;
begin
  select * into v_row from ${submissions} x where x.${s("id")} = get_form_submission.submission_id;
  if not found then
    ${submissionNotFound}
  end if;
  if not (${SERVICE_CALLER} or coalesce(v_row.${s("respondent")} = auth.uid(), false) or ${ctx.can("tenant", `v_row.${s("tenant")}`, review)}) then
    ${submissionNotFound}
  end if;
  return ${submissionJson("v_row")};
end;
$$;
${userGrant(`${fn("get_form_submission")}(uuid)`)}

-- Newest first. Reviewers see every submission; others see their own.
create or replace function ${fn("list_form_submissions")}(form_id uuid, status text default null, page_size integer default 50, before timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_all boolean;
  v_rows jsonb;
begin
  select x.${f("tenant")} into v_tenant from ${forms} x where x.${f("id")} = list_form_submissions.form_id;
  if not found then
    ${notFound}
  end if;
  v_all := ${SERVICE_CALLER} or ${ctx.can("tenant", "v_tenant", review)};
  select coalesce(jsonb_agg(${submissionJson("r")} order by r.${s("createdAt")} desc), '[]'::jsonb) into v_rows
  from (
    select * from ${submissions} x
    where x.${s("form")} = list_form_submissions.form_id
      and (v_all or x.${s("respondent")} = auth.uid())
      and (list_form_submissions.status is null or x.${s("status")}::text = list_form_submissions.status)
      and (list_form_submissions.before is null or x.${s("createdAt")} < list_form_submissions.before)
    order by x.${s("createdAt")} desc
    limit ${pageSize("list_form_submissions.page_size", 50, 200)}
  ) r;
  return v_rows;
end;
$$;
${userGrant(`${fn("list_form_submissions")}(uuid, text, integer, timestamptz)`)}

${formNpsFunction(ctx)}

create or replace function ${fn("review_form_submission")}(submission_id uuid, status text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${submissions}%rowtype;
begin
  select * into v_row from ${submissions} x where x.${s("id")} = review_form_submission.submission_id for update;
  if not found then
    ${submissionNotFound}
  end if;
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", `v_row.${s("tenant")}`, review)}) then
    ${fail("FORM_FORBIDDEN", "not allowed to review submissions")}
  end if;
  if review_form_submission.status is null or review_form_submission.status not in ('submitted', 'accepted', 'rejected') then
    ${fail("FORM_STATUS_INVALID", "status is submitted, accepted or rejected", "22023")}
  end if;
  if v_row.${s("status")} = 'draft' then
    ${fail("FORM_SUBMISSION_DRAFT", "a draft isn't submitted yet", "55000")}
  end if;
  update ${submissions} x set
    ${s("status")} = ${ctx.cast("submissions", "status", "review_form_submission.status")},
    ${s("reviewedBy")} = auth.uid(),
    ${s("reviewedAt")} = now(),
    ${s("updatedAt")} = now()
  where x.${s("id")} = review_form_submission.submission_id
  returning * into v_row;
  ${submissionRecord("form_submission.reviewed", "v_row", `, 'status', v_row.${s("status")}`, true)}
  return ${submissionJson("v_row")};
end;
$$;
${userGrant(`${fn("review_form_submission")}(uuid, text)`)}

-- Reviewers delete any submission; a respondent deletes their own draft.
create or replace function ${fn("delete_form_submission")}(submission_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${submissions}%rowtype;
begin
  select * into v_row from ${submissions} x where x.${s("id")} = delete_form_submission.submission_id for update;
  if not found then
    ${submissionNotFound}
  end if;
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", `v_row.${s("tenant")}`, review)}
    or (coalesce(v_row.${s("respondent")} = auth.uid(), false) and v_row.${s("status")} = 'draft')) then
    ${fail("FORM_FORBIDDEN", "not allowed to delete this submission")}
  end if;
  delete from ${submissions} x where x.${s("id")} = delete_form_submission.submission_id;
  ${submissionRecord("form_submission.deleted", "v_row", "", true)}
  return true;
end;
$$;
${userGrant(`${fn("delete_form_submission")}(uuid)`)}
`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "create_form",
      args: ["{id}", "text", "text", "text", "jsonb"],
      returns: "jsonb",
    },
    { name: "publish_form_version", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "get_form", args: ["uuid"], returns: "jsonb" },
    {
      name: "submit_form",
      args: ["uuid", "jsonb", "text", "text", "uuid", "boolean"],
      returns: "jsonb",
    },
    { name: "get_form_submission", args: ["uuid"], returns: "jsonb" },
  ];
}

const CONTRIBUTES: BlockContributes = {
  "share-links": (own) => [
    {
      subject: "form",
      exists: (subject) => shareLinkRow(own, "forms", subject),
    },
  ],
};

export const FORMS: BlockSqlDefinition = {
  contributes: CONTRIBUTES,
  name: "forms",
  scopes: ["tenant"],
  title: "Forms",
  description:
    "Forms with numbered versions (steps and show or skip logic), a JSON Schema 2020-12 per version that validates every submission, drafts, public links through share-links with a rate limit and a bot-check hook, handlers that turn a submission into a record, scoring against an answer key respondents can't read, and NPS rollups.",
  requires: ["memberships", "permissions", "jsonb-schemas"],
  integrates: ["custom-fields", "share-links", "rate-limit", "outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 2,
  upgrades: [
    {
      from: 1,
      description:
        "Scored forms: a field's correct answer and points, a pass mark, a score on each submission, the nps field type and form_nps.",
      sql: () => "",
    },
  ],
  names: NAMES,
  contract,
  build,
};
