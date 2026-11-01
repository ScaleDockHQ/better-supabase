import type { BlockSqlContext } from "../context.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { fail, lockTable, pageSize, SERVICE_CALLER } from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";

/**
 * The restrictions a statement of reasons names, as in Article 17(1) of
 * Regulation (EU) 2022/2065 (the Digital Services Act).
 */
const DSA_RESTRICTIONS = [
  "removal",
  "disabled_access",
  "demotion",
  "visibility_suspension",
  "monetary_suspension",
  "service_suspension",
  "service_termination",
  "account_suspension",
  "account_termination",
] as const;

const restrictionList = DSA_RESTRICTIONS.map((value) => sqlString(value)).join(
  ", ",
);

/** The tables of the DSA workflow: statements, notices, flaggers, appeals. */
export function moderationDsaTables(ctx: BlockSqlContext): string {
  if (!ctx.manages) {
    return "";
  }

  const items = ctx.table("items");
  const statements = ctx.table("statements");
  const notices = ctx.table("notices");
  const flaggers = ctx.table("flaggers");
  const appeals = ctx.table("appeals");
  const i = (column: string): string => ctx.col("items", column);
  const s = (column: string): string => ctx.col("statements", column);
  const n = (column: string): string => ctx.col("notices", column);
  const f = (column: string): string => ctx.col("flaggers", column);
  const p = (column: string): string => ctx.col("appeals", column);

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  return `-- Statements of reasons (DSA Article 17): what was restricted, the facts, the
-- legal or contractual ground, automated means and the ways to appeal.
create table if not exists ${statements} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("tenant")} ${ctx.idType} not null,
  ${s("item")} uuid not null references ${items} (${i("id")}) on delete cascade,
  ${s("restriction")} text not null check (${s("restriction")} in (${restrictionList})),
  ${s("facts")} text not null check (length(${s("facts")}) between 1 and 5000),
  ${s("legalGround")} text check (${s("legalGround")} is null or length(${s("legalGround")}) <= 2000),
  ${s("termsGround")} text check (${s("termsGround")} is null or length(${s("termsGround")}) <= 2000),
  ${s("automatedDetection")} boolean not null default false,
  ${s("automatedDecision")} boolean not null default false,
  ${s("redress")} text[] not null default array['internal_complaint', 'out_of_court', 'judicial'],
  ${s("issuedBy")} uuid,
  ${s("createdAt")} timestamptz not null default now(),
  check (${s("legalGround")} is not null or ${s("termsGround")} is not null)
);
create index if not exists ${name("statements", "item_idx")} on ${statements} (${s("item")}, ${s("createdAt")} desc);
create index if not exists ${name("statements", "tenant_idx")} on ${statements} (${s("tenant")}, ${s("createdAt")} desc);

-- Notices of illegal content (DSA Article 16).
create table if not exists ${notices} (
  ${n("id")} uuid primary key default gen_random_uuid(),
  ${n("tenant")} ${ctx.idType} not null,
  ${n("item")} uuid references ${items} (${i("id")}) on delete set null,
  ${n("subjectType")} text not null check (${n("subjectType")} ~ '^[a-z][a-z0-9_-]{0,62}$'),
  ${n("subjectId")} text not null check (length(${n("subjectId")}) between 1 and 200),
  ${n("explanation")} text not null check (length(${n("explanation")}) between 1 and 5000),
  ${n("url")} text check (${n("url")} is null or length(${n("url")}) <= 2000),
  ${n("notifierName")} text check (${n("notifierName")} is null or length(${n("notifierName")}) <= 200),
  ${n("notifierEmail")} text check (${n("notifierEmail")} is null or length(${n("notifierEmail")}) <= 320),
  ${n("notifier")} uuid references auth.users (id) on delete set null,
  ${n("trusted")} boolean not null default false,
  ${n("status")} text not null default 'received' check (${n("status")} in ('received', 'actioned', 'rejected')),
  ${n("outcome")} text check (${n("outcome")} is null or length(${n("outcome")}) <= 2000),
  ${n("decidedBy")} uuid,
  ${n("decidedAt")} timestamptz,
  ${n("createdAt")} timestamptz not null default now()
);
create index if not exists ${name("notices", "queue_idx")} on ${notices} (${n("tenant")}, ${n("trusted")} desc, ${n("createdAt")}) where ${n("status")} = 'received';
create index if not exists ${name("notices", "notifier_idx")} on ${notices} (${n("notifier")});

-- Trusted flaggers (DSA Article 22): notices from them are marked and come
-- first in the queue.
create table if not exists ${flaggers} (
  ${f("id")} uuid primary key default gen_random_uuid(),
  ${f("tenant")} ${ctx.idType} not null,
  ${f("user")} uuid not null references auth.users (id) on delete cascade,
  ${f("name")} text not null check (length(${f("name")}) between 1 and 200),
  ${f("awardedBy")} text check (${f("awardedBy")} is null or length(${f("awardedBy")}) <= 200),
  ${f("revokedAt")} timestamptz,
  ${f("createdAt")} timestamptz not null default now()
);
create unique index if not exists ${name("flaggers", "active_idx")} on ${flaggers} (${f("tenant")}, ${f("user")}) where ${f("revokedAt")} is null;

-- Appeals (DSA Article 20) against a statement of reasons or a rejected notice.
create table if not exists ${appeals} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  ${p("tenant")} ${ctx.idType} not null,
  ${p("statement")} uuid references ${statements} (${s("id")}) on delete cascade,
  ${p("notice")} uuid references ${notices} (${n("id")}) on delete cascade,
  ${p("appellant")} uuid references auth.users (id) on delete set null,
  ${p("reasons")} text not null check (length(${p("reasons")}) between 1 and 5000),
  ${p("status")} text not null default 'open' check (${p("status")} in ('open', 'upheld', 'reversed')),
  ${p("outcome")} text check (${p("outcome")} is null or length(${p("outcome")}) <= 2000),
  ${p("decidedBy")} uuid,
  ${p("decidedAt")} timestamptz,
  ${p("createdAt")} timestamptz not null default now(),
  check ((${p("statement")} is not null) <> (${p("notice")} is not null))
);
create unique index if not exists ${name("appeals", "open_statement_idx")} on ${appeals} (${p("statement")}) where ${p("status")} = 'open' and ${p("statement")} is not null;
create unique index if not exists ${name("appeals", "open_notice_idx")} on ${appeals} (${p("notice")}) where ${p("status")} = 'open' and ${p("notice")} is not null;
create index if not exists ${name("appeals", "tenant_idx")} on ${appeals} (${p("tenant")}, ${p("createdAt")} desc);
`;
}

/** Read policies for the DSA tables. */
export function moderationDsaPolicies(
  ctx: BlockSqlContext,
  read: string,
): string {
  if (!ctx.manages) {
    return "";
  }

  const name = (logical: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_read`);

  const tenantRead = (logical: string): string => {
    const table = ctx.table(logical);

    return `${lockTable(table, { read: true })}
drop policy if exists ${name(logical)} on ${table};
${renderPolicy(makePolicy({ table, name: name(logical), command: "select", roles: ["authenticated"], using: ctx.scope.check(ctx.col(logical, "tenant"), read) }), { target: table })}`;
  };

  const own = (logical: string, column: string): string => {
    const table = ctx.table(logical);

    return `${lockTable(table, { read: true })}
drop policy if exists ${name(logical)} on ${table};
${renderPolicy(makePolicy({ table, name: name(logical), command: "select", roles: ["authenticated"], using: `${ctx.col(logical, column)} = (select auth.uid()) or ${ctx.scope.check(ctx.col(logical, "tenant"), read)}` }), { target: table })}`;
  };

  return `${tenantRead("statements")}
${own("notices", "notifier")}
${tenantRead("flaggers")}
${own("appeals", "appellant")}
`;
}

/** The DSA functions: notices, statements, flaggers, appeals and the report. */
export function moderationDsaFunctions(ctx: BlockSqlContext): string {
  const items = ctx.table("items");
  const statements = ctx.table("statements");
  const notices = ctx.table("notices");
  const flaggers = ctx.table("flaggers");
  const appeals = ctx.table("appeals");
  const actions = ctx.table("actions");
  const reports = ctx.table("reports");
  const i = (column: string): string => ctx.col("items", column);
  const s = (column: string): string => ctx.col("statements", column);
  const n = (column: string): string => ctx.col("notices", column);
  const f = (column: string): string => ctx.col("flaggers", column);
  const p = (column: string): string => ctx.col("appeals", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const permissions = moduleOperations("moderation");
  const read = ctx.permission("read", permissions.read);
  const report = ctx.permission("report", permissions.report);
  const manage = ctx.permission("manage", permissions.manage);

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  const forbidden = (message: string): string =>
    fail("MODERATION_FORBIDDEN", message);

  const invalid = (message: string): string =>
    fail("MODERATION_INVALID", message, "22023");

  const missing = (code: string, message: string): string =>
    fail(code, message, "P0002");

  const statementJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${s("id")}, 'organizationId', ${row}.${s("tenant")}, 'itemId', ${row}.${s("item")}, 'restriction', ${row}.${s("restriction")}, 'facts', ${row}.${s("facts")}, 'legalGround', ${row}.${s("legalGround")}, 'termsGround', ${row}.${s("termsGround")}, 'automatedDetection', ${row}.${s("automatedDetection")}, 'automatedDecision', ${row}.${s("automatedDecision")}, 'redress', to_jsonb(${row}.${s("redress")}), 'issuedBy', ${row}.${s("issuedBy")}, 'createdAt', ${row}.${s("createdAt")})`;

  const noticeJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${n("id")}, 'organizationId', ${row}.${n("tenant")}, 'itemId', ${row}.${n("item")}, 'subjectType', ${row}.${n("subjectType")}, 'subjectId', ${row}.${n("subjectId")}, 'explanation', ${row}.${n("explanation")}, 'url', ${row}.${n("url")}, 'notifierName', ${row}.${n("notifierName")}, 'notifierEmail', ${row}.${n("notifierEmail")}, 'notifierId', ${row}.${n("notifier")}, 'trusted', ${row}.${n("trusted")}, 'status', ${row}.${n("status")}, 'outcome', ${row}.${n("outcome")}, 'decidedBy', ${row}.${n("decidedBy")}, 'decidedAt', ${row}.${n("decidedAt")}, 'createdAt', ${row}.${n("createdAt")})`;

  const flaggerJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${f("id")}, 'organizationId', ${row}.${f("tenant")}, 'userId', ${row}.${f("user")}, 'name', ${row}.${f("name")}, 'awardedBy', ${row}.${f("awardedBy")}, 'revokedAt', ${row}.${f("revokedAt")}, 'createdAt', ${row}.${f("createdAt")})`;

  const appealJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${p("id")}, 'organizationId', ${row}.${p("tenant")}, 'statementId', ${row}.${p("statement")}, 'noticeId', ${row}.${p("notice")}, 'appellantId', ${row}.${p("appellant")}, 'reasons', ${row}.${p("reasons")}, 'status', ${row}.${p("status")}, 'outcome', ${row}.${p("outcome")}, 'decidedBy', ${row}.${p("decidedBy")}, 'decidedAt', ${row}.${p("decidedAt")}, 'createdAt', ${row}.${p("createdAt")})`;

  const grantFn = (name: string, args: string): string =>
    `revoke execute on function ${fn(name)}(${args}) from public, anon;
grant execute on function ${fn(name)}(${args}) to authenticated, service_role;`;

  return `-- Takes a notice of illegal content (DSA Article 16) for a subject. The
-- notice is marked trusted when the caller is an active trusted flagger, and
-- the subject gets a moderation item when it has none.
create or replace function ${fn("submit_notice")}(tenant ${idType}, subject_type text, subject_id text, explanation text, url text default null, notifier_name text default null, notifier_email text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_item uuid;
  v_trusted boolean;
  v_row ${notices};
begin
  if v_me is null then
    ${forbidden("sign in to submit a notice")}
  end if;
  if not ${ctx.can("tenant", "submit_notice.tenant", report)} then
    ${forbidden("not allowed to submit a notice")}
  end if;
  if submit_notice.subject_type is null or submit_notice.subject_type !~ '^[a-z][a-z0-9_-]{0,62}$'
    or submit_notice.subject_id is null or length(submit_notice.subject_id) not between 1 and 200 then
    ${invalid("a notice needs a subject type and id")}
  end if;
  if submit_notice.explanation is null or length(trim(submit_notice.explanation)) = 0 or length(submit_notice.explanation) > 5000 then
    ${invalid("a notice needs an explanation of at most 5000 characters")}
  end if;
  insert into ${items} (${i("tenant")}, ${i("subjectType")}, ${i("subjectId")})
  values (submit_notice.tenant, submit_notice.subject_type, submit_notice.subject_id)
  on conflict (${i("tenant")}, ${i("subjectType")}, ${i("subjectId")}) do nothing;
  select x.${i("id")} into v_item from ${items} x
  where x.${i("tenant")} = submit_notice.tenant and x.${i("subjectType")} = submit_notice.subject_type and x.${i("subjectId")} = submit_notice.subject_id;
  select exists (
    select 1 from ${flaggers} x
    where x.${f("tenant")} = submit_notice.tenant and x.${f("user")} = v_me and x.${f("revokedAt")} is null
  ) into v_trusted;
  insert into ${notices} (${n("tenant")}, ${n("item")}, ${n("subjectType")}, ${n("subjectId")}, ${n("explanation")}, ${n("url")}, ${n("notifierName")}, ${n("notifierEmail")}, ${n("notifier")}, ${n("trusted")})
  values (submit_notice.tenant, v_item, submit_notice.subject_type, submit_notice.subject_id, trim(submit_notice.explanation), nullif(trim(submit_notice.url), ''), nullif(trim(submit_notice.notifier_name), ''), nullif(trim(submit_notice.notifier_email), ''), v_me, v_trusted)
  returning * into v_row;
  ${ctx.record({
    type: "moderation_notice.received",
    payload: `jsonb_build_object('organizationId', v_row.${n("tenant")}, 'id', v_row.${n("id")}, 'itemId', v_row.${n("item")}, 'subjectType', v_row.${n("subjectType")}, 'subjectId', v_row.${n("subjectId")}, 'trusted', v_row.${n("trusted")})`,
    subject: `'moderation-notices/' || v_row.${n("id")}::text`,
    tenant: `v_row.${n("tenant")}`,
    audit: false,
  })}
  return ${noticeJson("v_row")};
end;
$$;
${grantFn("submit_notice", `${idType}, text, text, text, text, text, text`)}

-- The notices of an organization, trusted flaggers first, then oldest first.
-- Without a status it lists the notices that wait for a decision.
create or replace function ${fn("list_notices")}(tenant ${idType}, status text default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_rows jsonb;
begin
  if not ${allowed("list_notices.tenant", read)} then
    ${forbidden("not allowed to read notices")}
  end if;
  select coalesce(jsonb_agg(q.notice order by q.trusted desc, q.created asc), '[]'::jsonb) into v_rows
  from (
    select ${noticeJson("x")} as notice, x.${n("trusted")} as trusted, x.${n("createdAt")} as created
    from ${notices} x
    where x.${n("tenant")} = list_notices.tenant
      and x.${n("status")} = coalesce(list_notices.status, 'received')
    order by x.${n("trusted")} desc, x.${n("createdAt")} asc
    limit ${pageSize("list_notices.page_size", 50, 200)}
  ) q;
  return v_rows;
end;
$$;
${grantFn("list_notices", `${idType}, text, integer`)}

-- Decides a notice: hide or remove the content, or reject the notice. The
-- notifier is told through the moderation_notice.decided event.
create or replace function ${fn("decide_notice")}(notice_id uuid, decision text, outcome text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${notices};
  v_item ${items};
begin
  select * into v_row from ${notices} x where x.${n("id")} = decide_notice.notice_id for update;
  if v_row.${n("id")} is null then
    ${missing("MODERATION_NOTICE_NOT_FOUND", "notice not found")}
  end if;
  if not ${allowed(`v_row.${n("tenant")}`, manage)} then
    ${forbidden("not allowed to decide on notices")}
  end if;
  if decide_notice.decision is null or decide_notice.decision not in ('hide', 'remove', 'reject') then
    ${invalid("decision must be hide, remove or reject")}
  end if;
  if length(decide_notice.outcome) > 2000 then
    ${invalid("outcome must be at most 2000 characters")}
  end if;
  if v_row.${n("status")} <> 'received' then
    ${invalid("this notice was decided already")}
  end if;
  if decide_notice.decision <> 'reject' then
    if v_row.${n("item")} is null then
      ${missing("MODERATION_ITEM_NOT_FOUND", "moderation item not found")}
    end if;
    perform ${fn("moderation_apply")}(v_row.${n("item")}, decide_notice.decision, decide_notice.outcome, false);
  end if;
  update ${notices} x
  set ${n("status")} = case when decide_notice.decision = 'reject' then 'rejected' else 'actioned' end,
    ${n("outcome")} = nullif(trim(decide_notice.outcome), ''), ${n("decidedBy")} = auth.uid(), ${n("decidedAt")} = now()
  where x.${n("id")} = v_row.${n("id")}
  returning * into v_row;
  ${ctx.record({
    type: "moderation_notice.decided",
    payload: `jsonb_build_object('organizationId', v_row.${n("tenant")}, 'id', v_row.${n("id")}, 'itemId', v_row.${n("item")}, 'status', v_row.${n("status")}, 'decision', decide_notice.decision, 'notifierId', v_row.${n("notifier")})`,
    subject: `'moderation-notices/' || v_row.${n("id")}::text`,
    tenant: `v_row.${n("tenant")}`,
    audit: {
      category: "data",
      targetType: "moderation_notice",
      recordId: `v_row.${n("id")}::text`,
      summary: `'notice ' || v_row.${n("status")}`,
    },
  })}
  return ${noticeJson("v_row")};
end;
$$;
${grantFn("decide_notice", "uuid, text, text")}

-- Records a statement of reasons (DSA Article 17) for an item a moderator
-- restricted. A statement names the legal ground, the terms ground or both.
create or replace function ${fn("issue_statement")}(item_id uuid, restriction text, facts text, legal_ground text default null, terms_ground text default null, automated_detection boolean default false, automated_decision boolean default false, redress text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item ${items};
  v_row ${statements};
begin
  select * into v_item from ${items} x where x.${i("id")} = issue_statement.item_id;
  if v_item.${i("id")} is null then
    ${missing("MODERATION_ITEM_NOT_FOUND", "moderation item not found")}
  end if;
  if not ${allowed(`v_item.${i("tenant")}`, manage)} then
    ${forbidden("not allowed to issue statements of reasons")}
  end if;
  if issue_statement.restriction is null or issue_statement.restriction not in (${restrictionList}) then
    ${invalid("restriction must be one of the Article 17 restrictions")}
  end if;
  if issue_statement.facts is null or length(trim(issue_statement.facts)) = 0 or length(issue_statement.facts) > 5000 then
    ${invalid("a statement needs facts and circumstances of at most 5000 characters")}
  end if;
  if nullif(trim(issue_statement.legal_ground), '') is null and nullif(trim(issue_statement.terms_ground), '') is null then
    ${invalid("a statement needs a legal ground or a terms ground")}
  end if;
  insert into ${statements} (${s("tenant")}, ${s("item")}, ${s("restriction")}, ${s("facts")}, ${s("legalGround")}, ${s("termsGround")}, ${s("automatedDetection")}, ${s("automatedDecision")}, ${s("redress")}, ${s("issuedBy")})
  values (v_item.${i("tenant")}, v_item.${i("id")}, issue_statement.restriction, trim(issue_statement.facts), nullif(trim(issue_statement.legal_ground), ''), nullif(trim(issue_statement.terms_ground), ''),
    coalesce(issue_statement.automated_detection, false), coalesce(issue_statement.automated_decision, false),
    coalesce(issue_statement.redress, array['internal_complaint', 'out_of_court', 'judicial']), auth.uid())
  returning * into v_row;
  ${ctx.record({
    type: "moderation_statement.issued",
    payload: `jsonb_build_object('organizationId', v_row.${s("tenant")}, 'id', v_row.${s("id")}, 'itemId', v_row.${s("item")}, 'restriction', v_row.${s("restriction")}, 'authorId', v_item.${i("author")})`,
    subject: `'moderation-statements/' || v_row.${s("id")}::text`,
    tenant: `v_row.${s("tenant")}`,
    audit: {
      category: "data",
      targetType: "moderation_statement",
      recordId: `v_row.${s("id")}::text`,
      summary: `'statement of reasons: ' || v_row.${s("restriction")}`,
    },
  })}
  return ${statementJson("v_row")};
end;
$$;
${grantFn("issue_statement", "uuid, text, text, text, text, boolean, boolean, text[]")}

-- The statements of reasons for one item, newest first. The item's author
-- reads their own through the same call.
create or replace function ${fn("list_statements")}(item_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item ${items};
begin
  select * into v_item from ${items} x where x.${i("id")} = list_statements.item_id;
  if v_item.${i("id")} is null then
    ${missing("MODERATION_ITEM_NOT_FOUND", "moderation item not found")}
  end if;
  if not ((auth.uid() is not null and v_item.${i("author")} is not distinct from auth.uid()) or ${allowed(`v_item.${i("tenant")}`, read)}) then
    ${forbidden("not allowed to read statements of reasons")}
  end if;
  return coalesce((select jsonb_agg(${statementJson("y")} order by y.${s("createdAt")} desc) from ${statements} y where y.${s("item")} = v_item.${i("id")}), '[]'::jsonb);
end;
$$;
${grantFn("list_statements", "uuid")}

-- Awards or revokes trusted flagger status (DSA Article 22) for a user.
create or replace function ${fn("set_trusted_flagger")}(tenant ${idType}, user_id uuid, name text default null, awarded_by text default null, active boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${flaggers};
begin
  if not ${allowed("set_trusted_flagger.tenant", manage)} then
    ${forbidden("not allowed to manage trusted flaggers")}
  end if;
  if set_trusted_flagger.active is false then
    update ${flaggers} x set ${f("revokedAt")} = now()
    where x.${f("tenant")} = set_trusted_flagger.tenant and x.${f("user")} = set_trusted_flagger.user_id and x.${f("revokedAt")} is null
    returning * into v_row;
    if v_row.${f("id")} is null then
      ${missing("MODERATION_FLAGGER_NOT_FOUND", "no active trusted flagger for this user")}
    end if;
    return ${flaggerJson("v_row")};
  end if;
  if set_trusted_flagger.name is null or length(trim(set_trusted_flagger.name)) not between 1 and 200 then
    ${invalid("a trusted flagger needs a name of at most 200 characters")}
  end if;
  select * into v_row from ${flaggers} x
  where x.${f("tenant")} = set_trusted_flagger.tenant and x.${f("user")} = set_trusted_flagger.user_id and x.${f("revokedAt")} is null;
  if v_row.${f("id")} is null then
    insert into ${flaggers} (${f("tenant")}, ${f("user")}, ${f("name")}, ${f("awardedBy")})
    values (set_trusted_flagger.tenant, set_trusted_flagger.user_id, trim(set_trusted_flagger.name), nullif(trim(set_trusted_flagger.awarded_by), ''))
    returning * into v_row;
  else
    update ${flaggers} x
    set ${f("name")} = trim(set_trusted_flagger.name), ${f("awardedBy")} = nullif(trim(set_trusted_flagger.awarded_by), '')
    where x.${f("id")} = v_row.${f("id")}
    returning * into v_row;
  end if;
  return ${flaggerJson("v_row")};
end;
$$;
${grantFn("set_trusted_flagger", `${idType}, uuid, text, text, boolean`)}

-- Files an appeal (DSA Article 20) against a statement of reasons, or against
-- a rejected notice. Only the affected content's author or the notifier can.
create or replace function ${fn("file_appeal")}(statement_id uuid default null, notice_id uuid default null, reasons text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_tenant ${idType};
  v_row ${appeals};
begin
  if v_me is null then
    ${forbidden("sign in to file an appeal")}
  end if;
  if (file_appeal.statement_id is null) = (file_appeal.notice_id is null) then
    ${invalid("an appeal names a statement or a notice")}
  end if;
  if file_appeal.reasons is null or length(trim(file_appeal.reasons)) = 0 or length(file_appeal.reasons) > 5000 then
    ${invalid("an appeal needs reasons of at most 5000 characters")}
  end if;
  if file_appeal.statement_id is not null then
    select s.${s("tenant")} into v_tenant
    from ${statements} s join ${items} x on x.${i("id")} = s.${s("item")}
    where s.${s("id")} = file_appeal.statement_id and x.${i("author")} = v_me;
  else
    select x.${n("tenant")} into v_tenant from ${notices} x
    where x.${n("id")} = file_appeal.notice_id and x.${n("notifier")} = v_me and x.${n("status")} = 'rejected';
  end if;
  if v_tenant is null then
    ${forbidden("you can only appeal a decision that affects you")}
  end if;
  begin
    insert into ${appeals} (${p("tenant")}, ${p("statement")}, ${p("notice")}, ${p("appellant")}, ${p("reasons")})
    values (v_tenant, file_appeal.statement_id, file_appeal.notice_id, v_me, trim(file_appeal.reasons))
    returning * into v_row;
  exception when unique_violation then
    ${invalid("an appeal is open for this decision already")}
  end;
  ${ctx.record({
    type: "moderation_appeal.filed",
    payload: `jsonb_build_object('organizationId', v_row.${p("tenant")}, 'id', v_row.${p("id")}, 'statementId', v_row.${p("statement")}, 'noticeId', v_row.${p("notice")}, 'appellantId', v_row.${p("appellant")})`,
    subject: `'moderation-appeals/' || v_row.${p("id")}::text`,
    tenant: `v_row.${p("tenant")}`,
    audit: false,
  })}
  return ${appealJson("v_row")};
end;
$$;
${grantFn("file_appeal", "uuid, uuid, text")}

-- Decides an appeal. The decision needs a person, not an automated means
-- (DSA Article 20(6)). Reversing an appeal against a statement restores the
-- content; reversing one against a notice puts the notice back in the queue.
create or replace function ${fn("decide_appeal")}(appeal_id uuid, outcome text, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${appeals};
  v_item ${items};
begin
  select * into v_row from ${appeals} x where x.${p("id")} = decide_appeal.appeal_id for update;
  if v_row.${p("id")} is null then
    ${missing("MODERATION_APPEAL_NOT_FOUND", "appeal not found")}
  end if;
  if not ${allowed(`v_row.${p("tenant")}`, manage)} then
    ${forbidden("not allowed to decide on appeals")}
  end if;
  if decide_appeal.outcome is null or decide_appeal.outcome not in ('upheld', 'reversed') then
    ${invalid("outcome must be upheld or reversed")}
  end if;
  if length(decide_appeal.reason) > 2000 then
    ${invalid("reason must be at most 2000 characters")}
  end if;
  if v_row.${p("status")} <> 'open' then
    ${invalid("this appeal was decided already")}
  end if;
  if decide_appeal.outcome = 'reversed' then
    if v_row.${p("statement")} is not null then
      select x.* into v_item from ${items} x join ${statements} s on s.${s("item")} = x.${i("id")} where s.${s("id")} = v_row.${p("statement")};
      if v_item.${i("status")} in ('hidden', 'removed') then
        perform ${fn("moderation_apply")}(v_item.${i("id")}, 'restore', decide_appeal.reason, false);
      end if;
    else
      update ${notices} x set ${n("status")} = 'received', ${n("decidedAt")} = null, ${n("decidedBy")} = null
      where x.${n("id")} = v_row.${p("notice")};
    end if;
  end if;
  update ${appeals} x
  set ${p("status")} = decide_appeal.outcome, ${p("outcome")} = nullif(trim(decide_appeal.reason), ''), ${p("decidedBy")} = auth.uid(), ${p("decidedAt")} = now()
  where x.${p("id")} = v_row.${p("id")}
  returning * into v_row;
  ${ctx.record({
    type: "moderation_appeal.decided",
    payload: `jsonb_build_object('organizationId', v_row.${p("tenant")}, 'id', v_row.${p("id")}, 'statementId', v_row.${p("statement")}, 'noticeId', v_row.${p("notice")}, 'status', v_row.${p("status")}, 'appellantId', v_row.${p("appellant")})`,
    subject: `'moderation-appeals/' || v_row.${p("id")}::text`,
    tenant: `v_row.${p("tenant")}`,
    audit: {
      category: "data",
      targetType: "moderation_appeal",
      recordId: `v_row.${p("id")}::text`,
      summary: `'appeal ' || v_row.${p("status")}`,
    },
  })}
  return ${appealJson("v_row")};
end;
$$;
${grantFn("decide_appeal", "uuid, text, text")}

-- The transparency report (DSA Articles 15 and 24) for a period, as CSV with
-- the columns metric, dimension and value: notices by status and from trusted
-- flaggers, statements by restriction and automated means, appeals by
-- outcome, and moderation decisions by action.
create or replace function ${fn("transparency_report")}(tenant ${idType}, period_start timestamptz, period_end timestamptz)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_csv text;
begin
  if not ${allowed("transparency_report.tenant", read)} then
    ${forbidden("not allowed to read the transparency report")}
  end if;
  if transparency_report.period_start is null or transparency_report.period_end is null or transparency_report.period_end <= transparency_report.period_start then
    ${invalid("the period needs a start before its end")}
  end if;
  with rows (metric, dimension, value, sort) as (
    select 'notices', 'received', count(*), 10 from ${notices} x
    where x.${n("tenant")} = transparency_report.tenant and x.${n("createdAt")} >= transparency_report.period_start and x.${n("createdAt")} < transparency_report.period_end
    union all
    select 'notices', 'trusted_flagger', count(*), 11 from ${notices} x
    where x.${n("tenant")} = transparency_report.tenant and x.${n("trusted")} and x.${n("createdAt")} >= transparency_report.period_start and x.${n("createdAt")} < transparency_report.period_end
    union all
    select 'notices', x.${n("status")}, count(*), 12 from ${notices} x
    where x.${n("tenant")} = transparency_report.tenant and x.${n("createdAt")} >= transparency_report.period_start and x.${n("createdAt")} < transparency_report.period_end
    group by x.${n("status")}
    union all
    select 'statements', x.${s("restriction")}, count(*), 20 from ${statements} x
    where x.${s("tenant")} = transparency_report.tenant and x.${s("createdAt")} >= transparency_report.period_start and x.${s("createdAt")} < transparency_report.period_end
    group by x.${s("restriction")}
    union all
    select 'statements', 'automated_detection', count(*), 21 from ${statements} x
    where x.${s("tenant")} = transparency_report.tenant and x.${s("automatedDetection")} and x.${s("createdAt")} >= transparency_report.period_start and x.${s("createdAt")} < transparency_report.period_end
    union all
    select 'statements', 'automated_decision', count(*), 22 from ${statements} x
    where x.${s("tenant")} = transparency_report.tenant and x.${s("automatedDecision")} and x.${s("createdAt")} >= transparency_report.period_start and x.${s("createdAt")} < transparency_report.period_end
    union all
    select 'appeals', 'received', count(*), 30 from ${appeals} x
    where x.${p("tenant")} = transparency_report.tenant and x.${p("createdAt")} >= transparency_report.period_start and x.${p("createdAt")} < transparency_report.period_end
    union all
    select 'appeals', x.${p("status")}, count(*), 31 from ${appeals} x
    where x.${p("tenant")} = transparency_report.tenant and x.${p("createdAt")} >= transparency_report.period_start and x.${p("createdAt")} < transparency_report.period_end
    group by x.${p("status")}
    union all
    select 'decisions', x.${ctx.col("actions", "action")}::text, count(*), 40 from ${actions} x
    where x.${ctx.col("actions", "tenant")} = transparency_report.tenant and x.${ctx.col("actions", "createdAt")} >= transparency_report.period_start and x.${ctx.col("actions", "createdAt")} < transparency_report.period_end
    group by x.${ctx.col("actions", "action")}
    union all
    select 'reports', 'received', count(*), 50 from ${reports} x
    where x.${ctx.col("reports", "tenant")} = transparency_report.tenant and x.${ctx.col("reports", "createdAt")} >= transparency_report.period_start and x.${ctx.col("reports", "createdAt")} < transparency_report.period_end
  )
  select 'metric,dimension,value' || coalesce(E'\\n' || string_agg(r.metric || ',' || r.dimension || ',' || r.value::text, E'\\n' order by r.sort, r.dimension), '')
  into v_csv from rows r;
  return v_csv;
end;
$$;
${grantFn("transparency_report", `${idType}, timestamptz, timestamptz`)}
`;
}
