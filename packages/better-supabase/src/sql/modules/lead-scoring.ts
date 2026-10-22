import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  fail,
  lockTable,
  pageSize,
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
  triggerGrant,
  userGrant,
} from "../shared.ts";
import { moduleOperations } from "./access-model.ts";

const NAMES: ModuleNames = {
  options: ["personModel", "companyModel", "rescoreAfterHours"],
  tables: {
    checks: {
      name: "lead_score_checks",
      lifecycle: { tenant: "tenant", export: false },
      columns: {
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        stale: "stale",
        checkedAt: "checked_at",
      },
    },
  },
};

interface LeadNames {
  readonly fn: (name: string) => string;
  readonly c: (column: string) => string;
  readonly checks: string;
  readonly parties: ModuleContext;
  readonly scores: ModuleContext;
  readonly person: string;
  readonly company: string;
  readonly personModel: string;
  readonly companyModel: string | undefined;
  readonly hours: number;
  readonly compute: string;
  readonly allowed: (tenant: string) => string;
}

function names(ctx: ModuleContext): LeadNames {
  const parties = ctx.of("parties");
  const scores = ctx.of("scores");
  const keys = moduleOperations("scores");
  const company = ctx.text("companyModel", "");
  const hours = ctx.number("rescoreAfterHours", 24);

  if (!Number.isInteger(hours) || hours < 1 || hours > 8760) {
    throw new TypeError(
      "lead-scoring: rescoreAfterHours must be a whole number from 1 to 8760",
    );
  }

  const compute = scores.permission("compute", keys.compute);

  return {
    fn: (name) => ctx.fn(name),
    c: (column) => ctx.col("checks", column),
    checks: ctx.table("checks"),
    parties,
    scores,
    person: sqlString(parties.naming.rename("person")),
    company: sqlString(parties.naming.rename("company")),
    personModel: sqlString(ctx.text("personModel", "lead")),
    companyModel: company === "" ? undefined : sqlString(company),
    hours,
    compute,
    allowed: (tenant) =>
      `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, compute)}))`,
  };
}

/** The subject types scored, as a SQL list. */
const scoredTypes = (n: LeadNames): string =>
  n.companyModel === undefined
    ? `(${n.person})`
    : `(${n.person}, ${n.company})`;

/** The model key of a subject type, as a SQL expression. */
const modelOf = (n: LeadNames, type: string): string =>
  n.companyModel === undefined
    ? n.personModel
    : `case when ${type} = ${n.company} then ${n.companyModel} else ${n.personModel} end`;

/** Named so score_lead's upsert can target it past its own parameter names. */
function checksKey(ctx: ModuleContext): string {
  return sqlIdent(`${ctx.tableName("checks").name}_pkey`);
}

function tables(ctx: ModuleContext, n: LeadNames): string {
  const { c, checks } = n;
  const policy = sqlIdent(`${ctx.tableName("checks").name}_read`);

  return `create table if not exists ${checks} (
  ${c("tenant")} ${ctx.idType} not null,
  ${c("subjectType")} text not null,
  ${c("subjectId")} text not null,
  -- Set when the record, its segments or its mail changed since the last score.
  ${c("stale")} boolean not null default true,
  ${c("checkedAt")} timestamptz,
  constraint ${checksKey(ctx)} primary key (${c("subjectType")}, ${c("subjectId")})
);
create index if not exists ${sqlIdent(`${ctx.tableName("checks").name}_tenant_idx`)} on ${checks} (${c("tenant")});
create index if not exists ${sqlIdent(`${ctx.tableName("checks").name}_due_idx`)} on ${checks} (${c("checkedAt")} nulls first) where ${c("stale")};

${lockTable(checks, { read: true })}
drop policy if exists ${policy} on ${checks};
create policy ${policy} on ${checks} for select to authenticated
  using (${ctx.scope.check(c("tenant"), n.compute)});
`;
}

function mailStats(ctx: ModuleContext, type: string, id: string): string {
  if (!ctx.installed("mail-sync") || !ctx.of("mail-sync").manages) {
    return "'{}'::jsonb";
  }

  const mail = ctx.of("mail-sync");
  const m = (column: string): string => mail.col("messages", column);
  const l = (column: string): string => mail.col("links", column);

  return `(select jsonb_build_object(
      'sent', count(*) filter (where y.${m("direction")} = 'outbound'),
      'opened', count(*) filter (where y.${m("direction")} = 'outbound' and y.${m("openedAt")} is not null),
      'clicked', count(*) filter (where y.${m("direction")} = 'outbound' and y.${m("clickedAt")} is not null),
      'replied', count(*) filter (where y.${m("direction")} = 'inbound'),
      'lastSentAt', max(y.${m("sentAt")}) filter (where y.${m("direction")} = 'outbound'),
      'lastRepliedAt', max(y.${m("sentAt")}) filter (where y.${m("direction")} = 'inbound')
    )
    from ${mail.table("links")} k
    join ${mail.table("messages")} y on y.${m("thread")} = k.${l("thread")}
    where k.${l("subjectType")} = ${type} and k.${l("subjectId")} = ${id})`;
}

function segmentIds(ctx: ModuleContext, type: string, id: string): string {
  if (!ctx.installed("segments") || !ctx.of("segments").manages) {
    return "'[]'::jsonb";
  }

  const segments = ctx.of("segments");
  const g = (column: string): string => segments.col("segments", column);
  const s = (column: string): string => segments.col("members", column);

  return `(select coalesce(jsonb_agg(x.${s("segment")}::text order by x.${s("segment")}), '[]'::jsonb)
    from ${segments.table("members")} x
    join ${segments.table("segments")} g on g.${g("id")} = x.${s("segment")}
    where g.${g("subjectType")} = ${type} and x.${s("subjectId")} = ${id})`;
}

function enrichmentOf(ctx: ModuleContext, column: string, id: string): string {
  if (!ctx.installed("enrichment") || !ctx.of("enrichment").manages) {
    return "null";
  }

  const enrichment = ctx.of("enrichment");
  const e = (name: string): string => enrichment.col("enrichments", name);

  return `(select jsonb_build_object('status', x.${e("status")}, 'provider', x.${e("provider")}, 'fetchedAt', x.${e("fetchedAt")})
    from ${enrichment.table("enrichments")} x
    where x.${e(column)} = ${id}
    order by x.${e("fetchedAt")} desc nulls last
    limit 1)`;
}

function functions(ctx: ModuleContext, n: LeadNames): string {
  const { fn, c, checks, parties } = n;
  const pe = (column: string): string => parties.col("people", column);
  const co = (column: string): string => parties.col("companies", column);
  const people = parties.table("people");
  const companies = parties.table("companies");
  const models = n.scores.table("models");
  const sm = (column: string): string => n.scores.col("models", column);
  const computeScore = n.scores.fn("compute_score");

  const forbidden = fail(
    "LEAD_SCORING_FORBIDDEN",
    "not allowed to score leads",
  );

  const missing = fail("LEAD_SCORING_NOT_FOUND", "no such record", "P0002");
  const type = "lead_fields.subject_type";
  const id = "lead_fields.subject_id";

  const extras = (column: string): string => `jsonb_build_object(
      'segments', ${segmentIds(ctx, type, id)},
      'mail', ${mailStats(ctx, type, id)},
      'enrichment', ${enrichmentOf(ctx, column, `v_id`)}
    )`;

  const company =
    n.companyModel === undefined
      ? ""
      : `
  elsif ${type} = ${n.company} then
    select to_jsonb(x), x.${co("tenant")} into v_row, v_tenant from ${companies} x where x.${co("id")} = v_id;
    if v_row is null then
      return null;
    end if;
    v_row := v_row || jsonb_build_object('people', (select count(*) from ${parties.table("links")} k where k.${parties.col("links", "company")} = v_id));
    return v_row || ${extras("company")};`;

  return `-- The values a lead model's rules and metrics read for one record: its
-- columns by database name, segments (the ids of the segments it is in),
-- mail { sent, opened, clicked, replied, lastSentAt, lastRepliedAt } and
-- enrichment { status, provider, fetchedAt }. Null when there is no such
-- record in the organization.
create or replace function ${fn("lead_fields")}(tenant ${ctx.idType}, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_row jsonb;
  v_tenant ${ctx.idType};
begin
  if not ${n.allowed("lead_fields.tenant")} then
    ${forbidden}
  end if;
  begin
    v_id := ${id}::uuid;
  exception when invalid_text_representation then
    return null;
  end;
  if ${type} = ${n.person} then
    select to_jsonb(x), x.${pe("tenant")} into v_row, v_tenant from ${people} x where x.${pe("id")} = v_id;
    if v_row is null or v_tenant is distinct from lead_fields.tenant then
      return null;
    end if;
    return v_row || ${extras("person")};${company}
  end if;
  return null;
end;
$$;
${userGrant(`${fn("lead_fields")}(${ctx.idType}, text, text)`)}

-- Scores one record under its subject type's lead model and marks it fresh.
create or replace function ${fn("score_lead")}(tenant ${ctx.idType}, subject_type text, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_fields jsonb;
  v_result jsonb;
begin
  if not ${n.allowed("score_lead.tenant")} then
    ${forbidden}
  end if;
  if score_lead.subject_type not in ${scoredTypes(n)} then
    ${fail("LEAD_SCORING_SUBJECT", "lead scoring doesn't score this subject type", "22023")}
  end if;
  v_fields := ${fn("lead_fields")}(score_lead.tenant, score_lead.subject_type, score_lead.subject_id);
  if v_fields is null then
    ${missing}
  end if;
  v_result := ${computeScore}(score_lead.tenant, ${modelOf(n, "score_lead.subject_type")}, score_lead.subject_type, score_lead.subject_id, v_fields);
  insert into ${checks} (${c("tenant")}, ${c("subjectType")}, ${c("subjectId")}, ${c("stale")}, ${c("checkedAt")})
  values (score_lead.tenant, score_lead.subject_type, score_lead.subject_id, false, now())
  on conflict on constraint ${checksKey(ctx)} do update
    set ${c("stale")} = false, ${c("checkedAt")} = now();
  return v_result;
end;
$$;
${userGrant(`${fn("score_lead")}(${ctx.idType}, text, text)`)}

-- Scores up to max_count records that changed or weren't scored for
-- rescoreAfterHours, whose organization has an enabled lead model. Records
-- that were removed lose their check row. Returns how many it scored.
create or replace function ${fn("score_leads_due")}(max_count integer default 100)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_check ${checks};
  v_count integer := 0;
begin
  if not (${SERVICE_CALLER}) then
    ${forbidden}
  end if;
  insert into ${checks} (${c("tenant")}, ${c("subjectType")}, ${c("subjectId")})
  select x.${pe("tenant")}, ${n.person}, x.${pe("id")}::text
  from ${people} x
  where x.${pe("archivedAt")} is null
    and not exists (select 1 from ${checks} k where k.${c("subjectType")} = ${n.person} and k.${c("subjectId")} = x.${pe("id")}::text)
  limit ${pageSize("max_count", 100, 1000)}
  on conflict do nothing;
  for v_check in
    select k.* from ${checks} k
    where (k.${c("stale")} or k.${c("checkedAt")} < now() - interval '${String(n.hours)} hours')
      and exists (
        select 1 from ${models} m
        where m.${sm("tenant")} = k.${c("tenant")} and m.${sm("key")} = ${modelOf(n, `k.${c("subjectType")}`)}
          and m.${sm("subjectType")} = k.${c("subjectType")} and m.${sm("enabled")}
      )
    order by k.${c("checkedAt")} nulls first
    limit ${pageSize("max_count", 100, 1000)}
    for update of k skip locked
  loop
    if ${fn("lead_fields")}(v_check.${c("tenant")}, v_check.${c("subjectType")}, v_check.${c("subjectId")}) is null then
      delete from ${checks} k where k.${c("subjectType")} = v_check.${c("subjectType")} and k.${c("subjectId")} = v_check.${c("subjectId")};
      continue;
    end if;
    perform ${fn("score_lead")}(v_check.${c("tenant")}, v_check.${c("subjectType")}, v_check.${c("subjectId")});
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("score_leads_due")}(integer)`)}
`;
}

/** The triggers that mark a record stale when what its score reads changes. */
function triggers(ctx: ModuleContext, n: LeadNames): string {
  const { fn, c, checks, parties } = n;

  const mark = (
    select: string,
  ): string => `insert into ${checks} (${c("tenant")}, ${c("subjectType")}, ${c("subjectId")})
  ${select}
  on conflict (${c("subjectType")}, ${c("subjectId")}) do update set ${c("stale")} = true;`;

  const on = (
    name: string,
    table: string,
    events: string,
    body: string,
    level = "row",
  ): string => {
    const trigger = ctx.trigger(name);
    const func = fn(`lead_${name}`);

    return `
create or replace function ${func}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  ${body}
  return null;
end;
$$;
${triggerGrant(`${func}()`)}
drop trigger if exists ${trigger} on ${table};
create trigger ${trigger}
  after ${events} on ${table}
  for each ${level} execute function ${func}();
`;
  };

  const pe = (column: string): string => parties.col("people", column);
  const co = (column: string): string => parties.col("companies", column);

  const parts = [
    on(
      "person_changed",
      parties.table("people"),
      "insert or update",
      mark(`values (new.${pe("tenant")}, ${n.person}, new.${pe("id")}::text)`),
    ),
  ];

  if (n.companyModel !== undefined) {
    parts.push(
      on(
        "company_changed",
        parties.table("companies"),
        "insert or update",
        mark(
          `values (new.${co("tenant")}, ${n.company}, new.${co("id")}::text)`,
        ),
      ),
    );
  }

  if (ctx.installed("segments") && ctx.of("segments").manages) {
    const segments = ctx.of("segments");
    const g = (column: string): string => segments.col("segments", column);
    const s = (column: string): string => segments.col("members", column);

    parts.push(
      on(
        "segment_changed",
        segments.table("members"),
        "insert or delete",
        `if tg_op = 'DELETE' then
    ${mark(`select old.${s("tenant")}, g.${g("subjectType")}, old.${s("subjectId")}
  from ${segments.table("segments")} g
  where g.${g("id")} = old.${s("segment")} and g.${g("subjectType")} in ${scoredTypes(n)}`)}
  else
    ${mark(`select new.${s("tenant")}, g.${g("subjectType")}, new.${s("subjectId")}
  from ${segments.table("segments")} g
  where g.${g("id")} = new.${s("segment")} and g.${g("subjectType")} in ${scoredTypes(n)}`)}
  end if;`,
      ),
    );
  }

  if (ctx.installed("mail-sync") && ctx.of("mail-sync").manages) {
    const mail = ctx.of("mail-sync");
    const m = (column: string): string => mail.col("messages", column);
    const l = (column: string): string => mail.col("links", column);

    parts.push(
      on(
        "mail_changed",
        mail.table("messages"),
        `insert or update of ${m("openedAt")}, ${m("clickedAt")}`,
        mark(`select k.${l("tenant")}, k.${l("subjectType")}, k.${l("subjectId")}
  from ${mail.table("links")} k
  where k.${l("thread")} = new.${m("thread")} and k.${l("subjectType")} in ${scoredTypes(n)}`),
      ),
      on(
        "mail_linked",
        mail.table("links"),
        "insert",
        `if new.${l("subjectType")} in ${scoredTypes(n)} then
    ${mark(`values (new.${l("tenant")}, new.${l("subjectType")}, new.${l("subjectId")})`)}
  end if;`,
      ),
    );
  }

  return parts.join("");
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  if (!ctx.of("scores").manages || !ctx.of("parties").manages) {
    throw new TypeError(
      "lead-scoring needs the scores and parties modules in managed mode",
    );
  }

  const n = names(ctx);

  return `${schemaPreamble(ctx)}
${ctx.manages ? tables(ctx, n) : ""}
${functions(ctx, n)}
${triggers(ctx, n)}`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    { name: "lead_fields", args: ["{id}", "text", "text"], returns: "jsonb" },
    { name: "score_lead", args: ["{id}", "text", "text"], returns: "jsonb" },
    { name: "score_leads_due", args: ["integer"], returns: "integer" },
  ];
}

export const LEAD_SCORING: ModuleDefinition = {
  internal: [
    "lead_person_changed",
    "lead_company_changed",
    "lead_segment_changed",
    "lead_mail_changed",
    "lead_mail_linked",
  ],
  name: "lead-scoring",
  scopes: ["tenant"],
  title: "Lead scoring",
  description:
    "Scores people, and optionally companies, under a tenant-editable score model. Each record's columns, enrichment status, segments and mail opens, clicks and replies feed the model, and the record is scored again when any of them change.",
  requires: ["tenant", "access", "parties", "scores"],
  integrates: ["enrichment", "segments", "mail-sync"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
