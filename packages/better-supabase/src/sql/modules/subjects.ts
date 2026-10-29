import type { SubjectPermission } from "../../config/types/subjects.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlNames,
} from "../context.ts";
import type { SummarySection } from "../contributions.ts";
import type {
  BlockSqlAccessProvider,
  BlockSqlDefinition,
  BlockSqlLayout,
} from "../module-types.ts";
import type { RegisteredSubject } from "../subject-registry.ts";

import { fillTemplate } from "../../core/access-sql.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import { uniqueContributions } from "../contributions.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  SERVICE_CALLER,
  schemaPreamble,
  serviceGrant,
  userGrant,
} from "../shared.ts";
import {
  checkCall,
  registeredIdMatches,
  registeredSubjects,
  urlExpression,
} from "../subject-registry.ts";
import { accessModel } from "./permissions-model.ts";

const NAMES: BlockSqlNames = { tables: {} };

/**
 * The provider's per-row grant for `entry.rows` on row `s`, through its
 * `rowsWith` template (`rowsWithFor` with `user`), or `undefined` without
 * `rows`. `false` for another user when the provider can't answer for them.
 */
function rowGrant(
  where: string,
  subject: RegisteredSubject,
  entry: SubjectPermission,
  provider: BlockSqlAccessProvider | undefined,
  user?: string,
): string | undefined {
  if (entry.rows === undefined || entry.key === undefined) {
    return undefined;
  }

  const template =
    user === undefined
      ? provider?.functions.rowsWith
      : provider?.functions.rowsWithFor;

  if (provider?.functions.rowsWith === undefined) {
    throw new TypeError(
      `${where}.rows needs blocks.permissions.model "provider" and an authorization provider with functions.rowsWith`,
    );
  }

  if (template === undefined) {
    return "false";
  }

  const id = `s.${subject.id}::text`;

  return `${id} in (select r.id::text from ${fillTemplate(
    `authorization.functions.${user === undefined ? "rowsWith" : "rowsWithFor"}`,
    template,
    {
      resource: entry.rows,
      permission: sqlString(entry.key),
      ids: `array[${id}]`,
      ...(user === undefined ? {} : { user }),
    },
  )} as r(id))`;
}

/**
 * The ways one `permissions.<action>` entry grants the action on row `s`:
 * `held` for its key, the provider's row grants and the owner column, or-ed.
 */
function entryCheck(
  where: string,
  subject: RegisteredSubject,
  value: string | SubjectPermission,
  provider: BlockSqlAccessProvider | undefined,
  held: (key: string) => string,
  user: string | undefined,
): string {
  if (typeof value === "string") {
    return held(value);
  }

  if (value.check !== undefined && user !== undefined) {
    return "false";
  }

  const rows = rowGrant(where, subject, value, provider, user);

  const parts = [
    ...(value.key === undefined ? [] : [held(value.key)]),
    ...(rows === undefined ? [] : [rows]),
    ...(value.owner === undefined
      ? []
      : [`s.${sqlIdent(value.owner)} = ${user ?? "auth.uid()"}`]),
  ];

  const all = [
    ...(value.also === undefined ? [] : [held(value.also)]),
    ...(parts.length === 0
      ? []
      : [parts.length === 1 ? parts[0]! : `(${parts.join(" or ")})`]),
    ...(value.check === undefined
      ? []
      : [`coalesce(${checkCall(value.check, subject.id)}, false)`]),
  ];

  return all.length === 1 ? all[0]! : `(${all.join(" and ")})`;
}

/**
 * The permission check for `action` on row `s`, `true` when the action has no
 * key.
 */
function actionCheck(
  ctx: BlockSqlContext,
  subject: RegisteredSubject,
  provider: BlockSqlAccessProvider | undefined,
): string {
  const permissions = Object.entries(subject.config.permissions ?? {});

  if (permissions.length === 0) {
    return "true";
  }

  const scope = subject.config.scope;

  const held = (key: string): string => {
    const parts = [
      ...(subject.tenant === undefined
        ? []
        : [ctx.can("tenant", `s.${subject.tenant}`, sqlString(key))]),
      ...(scope === undefined
        ? []
        : [ctx.can(scope, `s.${subject.id}::text`, sqlString(key))]),
    ];

    return parts.length === 1 ? parts[0]! : `(${parts.join(" or ")})`;
  };

  return `(${SERVICE_CALLER} or case can_subject.action\n${permissions
    .map(
      ([action, value]) =>
        `          when ${sqlString(action)} then ${entryCheck(`records.${subject.type}.permissions.${action}`, subject, value, provider, held, undefined)}`,
    )
    .join("\n")}\n          else true\n        end)`;
}

/**
 * `user` holds the key for `action` on row `s`, through `can_user`. An action
 * without a key is false: nothing but the row's policies would decide it, and
 * they answer for the caller only.
 */
function actionCheckFor(
  subject: RegisteredSubject,
  user: string,
  provider: BlockSqlAccessProvider | undefined,
): string {
  const permissions = Object.entries(subject.config.permissions ?? {});

  if (permissions.length === 0) {
    return "false";
  }

  const scope = subject.config.scope;

  const held = (key: string): string => {
    const userCan = (scopeName: string, id: string): string =>
      `coalesce(better_supabase.can_user(${user}, ${sqlString(scopeName)}, ${id}, ${sqlString(key)}), false)`;

    const parts = [
      ...(subject.tenant === undefined
        ? []
        : [userCan("tenant", `s.${subject.tenant}`)]),
      ...(scope === undefined ? [] : [userCan(scope, `s.${subject.id}::text`)]),
    ];

    return parts.length === 1 ? parts[0]! : `(${parts.join(" or ")})`;
  };

  return `case can_subject_for.action\n${permissions
    .map(
      ([action, value]) =>
        `          when ${sqlString(action)} then ${entryCheck(`records.${subject.type}.permissions.${action}`, subject, value, provider, held, user)}`,
    )
    .join("\n")}\n          else false\n        end`;
}

/** The row `s` is `id` and, with `deletedAt`, not soft-deleted. */
function rowMatches(subject: RegisteredSubject, id: string): string {
  const match = registeredIdMatches(subject, id);

  return subject.config.deletedAt === undefined
    ? match
    : `${match} and s.${sqlIdent(subject.config.deletedAt)} is null`;
}

function cases(
  subjects: readonly RegisteredSubject[],
  branch: (subject: RegisteredSubject) => string | undefined,
): string {
  const whens = subjects.flatMap((subject) => {
    const body = branch(subject);

    return body === undefined
      ? []
      : [`    when ${sqlString(subject.type)} then\n      ${body}`];
  });

  return whens.length === 0 ? "    when '' then null;" : whens.join("\n");
}

/** The most refs one `subject_titles` call resolves. */
const MAX_TITLE_REFS = 500;

/** The `subject_titles` step that adds the refs of `subject`'s type. */
function titlesBranch(subject: RegisteredSubject): string {
  const ids = `select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = ${sqlString(subject.type)}`;
  const idType = subject.config.idType;

  const match =
    idType === undefined
      ? `s.${subject.id}::text = any(array(${ids}))`
      : `s.${subject.id} = any(array(${ids})::${idType}[])`;

  const live =
    subject.config.deletedAt === undefined
      ? ""
      : ` and s.${sqlIdent(subject.config.deletedAt)} is null`;

  const title =
    subject.config.title === undefined
      ? "null::text"
      : `s.${sqlIdent(subject.config.title)}::text`;

  const url =
    subject.config.url === undefined
      ? "null::text"
      : urlExpression(subject.config.url);

  return `  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', ${sqlString(subject.type)}, 'id', s.${subject.id}::text,
      'title', ${title}, 'url', ${url}))
    from ${subject.qualified} s
    where ${match}${live}), '[]'::jsonb);`;
}

/** The most sections one `record_summary` call counts. */
const MAX_SUMMARY_SECTIONS = 20;

/**
 * The sections `record_summary` counts: one per installed managed block that
 * contributes one, for rows the caller reads through policies.
 */
function summarySections(ctx: BlockSqlContext): readonly SummarySection[] {
  return uniqueContributions(
    "subjects",
    ctx.contributions("subjects"),
    (each) => each.summary?.name,
  ).flatMap((each) => (each.summary === undefined ? [] : [each.summary]));
}

/** The `record_summary` step that counts one section. */
function summaryBranch(section: SummarySection): string {
  const seen =
    section.readAt === undefined
      ? "record_summary.seen_at"
      : `coalesce(${section.readAt}, record_summary.seen_at)`;

  return `  if ${sqlString(section.name)} = any (record_summary.sections) then
    select count(*), max(${section.latest})
      into v_count, v_latest
      from ${section.from}
      where ${section.subjectType}::text = record_summary.subject_type
        and ${section.subjectId}::text = record_summary.subject_id${
          section.live === undefined ? "" : `\n        and ${section.live}`
        };
    v_seen := ${seen};
    v_counts := v_counts || jsonb_build_object(${sqlString(section.name)}, v_count);
    v_unread := v_unread || jsonb_build_object(${sqlString(section.name)},
      v_seen is not null and v_latest is not null and v_latest > v_seen);
  end if;`;
}

/** The most items one `my_work` call returns. */
const MAX_WORK_ITEMS = 200;

/**
 * The `my_work` organization filter on `column`, for the branches blocks
 * contribute.
 */
export function myWorkTenant(column: string): string {
  return `(my_work.tenant is null or ${column} = my_work.tenant)`;
}

/**
 * `my_work`: one branch per installed managed block that contributes one, each
 * selecting `kind, subject_type, subject_id, ref, title, at`; a null title
 * falls back to `subject_title`.
 */
function myWork(ctx: BlockSqlContext): string {
  const fn = (name: string): string => ctx.fn(name);
  const contributed = ctx.contributions("subjects");

  const branches = contributed.flatMap((each) =>
    each.work === undefined ? [] : [each.work],
  );

  const helper = contributed.flatMap((each) => each.sql ?? []).join("");

  const body =
    branches.length === 0
      ? "  return '[]'::jsonb;"
      : `  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'kind', w.kind,
      'subject', jsonb_build_object('type', w.subject_type, 'id', w.subject_id),
      'ref', w.ref,
      'title', coalesce(w.title, ${fn("subject_title")}(w.subject_type, w.subject_id)),
      'url', ${fn("subject_url")}(w.subject_type, w.subject_id),
      'at', w.at
    ) order by w.at desc nulls last, w.kind, w.ref), '[]'::jsonb)
    from (
      select * from (
    ${branches.join("\n    union all\n    ")}
      ) u (kind, subject_type, subject_id, ref, title, at)
      order by u.at desc nulls last, u.kind, u.ref
      limit least(greatest(coalesce(my_work.page_size, 50), 1), ${MAX_WORK_ITEMS})
    ) w
  );`;

  return `${helper}
-- What waits on the caller across the installed blocks, newest first. Runs as
-- the caller, so each row is one they can read.
create or replace function ${fn("my_work")}(tenant ${ctx.idType} default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    return '[]'::jsonb;
  end if;
${body}
end;
$$;
${userGrant(`${fn("my_work")}(${ctx.idType}, integer)`)}
`;
}

function build(ctx: BlockSqlContext, layout: BlockSqlLayout): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const subjects = registeredSubjects(ctx.subjects, ctx.naming);

  const provider =
    accessModel(ctx) === "provider" ? layout.accessProvider : undefined;

  const fn = (name: string): string => ctx.fn(name);

  return `${schemaPreamble(ctx)}
-- The app's subject registry (config.subjects, ADR 0020). Each function runs
-- as the caller, so the subject table's own policies decide what is visible.
create or replace function ${fn("subject_types")}()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select ${sqlString(`{${subjects.map((subject) => subject.type).join(",")}}`)}::text[]
$$;
${userGrant(`${fn("subject_types")}()`)}

create or replace function ${fn("subject_title")}(subject_type text, subject_id text)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  case subject_title.subject_type
${cases(subjects, (subject) =>
  subject.config.title === undefined
    ? undefined
    : `return (select s.${sqlIdent(subject.config.title)}::text from ${subject.qualified} s where ${rowMatches(subject, "subject_title.subject_id")});`,
)}
    else
      return null;
  end case;
  return null;
end;
$$;
${userGrant(`${fn("subject_title")}(text, text)`)}

create or replace function ${fn("subject_url")}(subject_type text, subject_id text)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  case subject_url.subject_type
${cases(subjects, (subject) =>
  subject.config.url === undefined
    ? undefined
    : `return (select ${urlExpression(subject.config.url)} from ${subject.qualified} s where ${rowMatches(subject, "subject_url.subject_id")});`,
)}
    else
      return null;
  end case;
  return null;
end;
$$;
${userGrant(`${fn("subject_url")}(text, text)`)}

-- Titles and paths for many subjects in one call: refs is a JSON array of
-- { "type", "id" }, the result one of { type, id, title, url }. A row the
-- caller can't see, an unknown type or a soft-deleted row returns nothing.
create or replace function ${fn("subject_titles")}(refs jsonb)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  found jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(subject_titles.refs) is distinct from 'array' then
    raise exception 'refs must be a JSON array of { type, id }'
      using errcode = '22023', hint = 'SUBJECT_REFS_INVALID';
  end if;
  if jsonb_array_length(subject_titles.refs) > ${MAX_TITLE_REFS} then
    raise exception 'subject_titles takes at most ${MAX_TITLE_REFS} refs'
      using errcode = '22023', hint = 'SUBJECT_REFS_TOO_MANY';
  end if;
${subjects.map((subject) => titlesBranch(subject)).join("\n")}
  return found;
exception
  when invalid_text_representation then
    raise exception 'a subject id does not match its type''s id column'
      using errcode = '22023', hint = 'SUBJECT_ID_INVALID';
end;
$$;
${userGrant(`${fn("subject_titles")}(jsonb)`)}

-- True when the caller can see the subject row and, for an action with a
-- key in config.subjects.<type>.permissions, holds that key in the
-- subject's tenant (or on the record, through the subject's scope), and the
-- action's check function, when it names one, returns true for the row.
create or replace function ${fn("can_subject")}(subject_type text, subject_id text, action text)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  case can_subject.subject_type
${cases(
  subjects,
  (subject) =>
    `return exists (
        select 1 from ${subject.qualified} s
        where ${rowMatches(subject, "can_subject.subject_id")}
          and ${actionCheck(ctx, subject, provider)}
      );`,
)}
    else
      return false;
  end case;
  return false;
end;
$$;
${userGrant(`${fn("can_subject")}(text, text, text)`)}

-- A record page's header and tab badges in one call: the subject's title and
-- path, how many rows each named section has and whether any is newer than
-- seen_at. Runs as the caller, so each count is what the caller can read;
-- null when the caller can't read the subject. An unknown section is left out.
create or replace function ${fn("record_summary")}(subject_type text, subject_id text, sections text[], seen_at timestamptz default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_counts jsonb := '{}'::jsonb;
  v_unread jsonb := '{}'::jsonb;
  v_count bigint;
  v_latest timestamptz;
  v_seen timestamptz;
begin
  if coalesce(cardinality(record_summary.sections), 0) > ${MAX_SUMMARY_SECTIONS} then
    raise exception 'record_summary takes at most ${MAX_SUMMARY_SECTIONS} sections'
      using errcode = '22023', hint = 'RECORD_SECTIONS_TOO_MANY';
  end if;
  if not ${fn("can_subject")}(record_summary.subject_type, record_summary.subject_id, 'read') then
    return null;
  end if;
${summarySections(ctx)
  .map((section) => summaryBranch(section))
  .join("\n")}
  return jsonb_build_object(
    'type', record_summary.subject_type,
    'id', record_summary.subject_id,
    'title', ${fn("subject_title")}(record_summary.subject_type, record_summary.subject_id),
    'url', ${fn("subject_url")}(record_summary.subject_type, record_summary.subject_id),
    'counts', v_counts,
    'unread', v_unread);
end;
$$;
${userGrant(`${fn("record_summary")}(text, text, text[], timestamptz)`)}

-- can_subject for another user, for server code that decides who receives
-- an event. It reads the row past its policies and asks can_user for the
-- action's key in config.subjects.<type>.permissions, so an action without
-- a key is false and a share-link grant never counts. A provider that
-- can't answer for others (no idsWithFor) gives false.
create or replace function ${fn("can_subject_for")}(member uuid, subject_type text, subject_id text, action text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  case can_subject_for.subject_type
${cases(
  subjects,
  (subject) =>
    `return exists (
        select 1 from ${subject.qualified} s
        where ${rowMatches(subject, "can_subject_for.subject_id")}
          and ${actionCheckFor(subject, "can_subject_for.member", provider)}
      );`,
)}
    else
      return false;
  end case;
  return false;
exception
  when feature_not_supported then
    return false;
end;
$$;
${serviceGrant(`${fn("can_subject_for")}(uuid, text, text, text)`)}
${myWork(ctx)}${presenceSql(ctx)}`;
}

/** The prefix of a subject's presence topic, `presence:<type>:<id>`. */
const PRESENCE_TOPIC_PREFIX = "presence";

/**
 * Realtime presence on `presence:<type>:<id>`: who has a record open. A caller
 * who can read the subject joins, tracks and sees the others there.
 */
function presenceSql(ctx: BlockSqlContext): string {
  const fn = (name: string): string => ctx.fn(name);
  const receive = ctx.trigger("subject_presence_receive");
  const send = ctx.trigger("subject_presence_send");
  const prefix = sqlString(`${PRESENCE_TOPIC_PREFIX}:`);

  const check = `realtime.messages.extension = 'presence'
        and (select realtime.topic()) like ${prefix} || '%'
        and ${fn("subject_presence_allowed")}((select realtime.topic()))`;

  return `
-- Whether the caller may join presence topic \`topic\`
-- (presence:<type>:<id>): they can read that subject.
create or replace function ${fn("subject_presence_allowed")}(topic text)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_parts text[] := regexp_match(subject_presence_allowed.topic, '^${PRESENCE_TOPIC_PREFIX}:([a-z][a-z0-9_-]{0,62}):([^:]{1,200})$');
begin
  if v_parts is null then
    return false;
  end if;
  return coalesce(${fn("can_subject")}(v_parts[1], v_parts[2], 'read'), false);
exception
  when invalid_text_representation then
    return false;
end;
$$;
${userGrant(`${fn("subject_presence_allowed")}(text)`)}

do $$
begin
  if to_regclass('realtime.messages') is not null then
        ${renderPolicy(makePolicy({ table: "realtime.messages", name: receive, command: "select", roles: ["authenticated"], using: check }), { drop: true, target: "realtime.messages" })}
        ${renderPolicy(makePolicy({ table: "realtime.messages", name: send, command: "insert", roles: ["authenticated"], check }), { drop: true, target: "realtime.messages" })}
  end if;
end;
$$;
`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    { name: "subject_types", args: [], returns: "text[]" },
    { name: "subject_title", args: ["text", "text"], returns: "text" },
    { name: "subject_url", args: ["text", "text"], returns: "text" },
    { name: "subject_titles", args: ["jsonb"], returns: "jsonb" },
    { name: "can_subject", args: ["text", "text", "text"], returns: "boolean" },
    {
      name: "record_summary",
      args: ["text", "text", "text[]", "timestamptz"],
      returns: "jsonb",
    },
    {
      name: "can_subject_for",
      args: ["uuid", "text", "text", "text"],
      returns: "boolean",
    },
    { name: "my_work", args: ["{id}", "integer"], returns: "jsonb" },
    { name: "subject_presence_allowed", args: ["text"], returns: "boolean" },
  ];
}

export const SUBJECTS: BlockSqlDefinition = {
  name: "subjects",
  scopes: ["tenant"],
  title: "Subjects",
  description:
    "The app-wide subject registry from config.subjects: subject_title, subject_url, subject_titles, can_subject, can_subject_for and record_summary for every registered type, my_work across the installed blocks, and Realtime presence on presence:<type>:<id> for readers of the subject.",
  requires: ["permissions"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
