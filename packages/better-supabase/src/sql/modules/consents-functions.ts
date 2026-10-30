import type { BlockSqlContext } from "../context.ts";
import type { ConsentsSql } from "./consents-sql.ts";

import { sqlString } from "../../core/template.ts";
import { fail, SERVICE_CALLER, serviceGrant, userGrant } from "../shared.ts";
import { subjectTenant } from "../subject-check-sql.ts";
import { consentsSql, LEGAL_BASES, PURPOSE_KEY } from "./consents-sql.ts";

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

function purposeFunctions(ctx: BlockSqlContext, q: ConsentsSql): string {
  const { fn, p, has, purposes, invalid, purposeJson } = q;

  const description = has("purposes", "description")
    ? `\n    ${p("description")} = v_description,`
    : "";

  const updated = has("purposes", "updatedAt")
    ? `\n    ${p("updatedAt")} = now(),`
    : "";

  const archived = fail(
    "CONSENT_PURPOSE_ARCHIVED",
    "the consent purpose is archived",
    "22023",
  );

  return `-- Creates or changes the purpose with key and version: what the organization
-- asks consent for, its lawful basis, whether it takes a signature and how many
-- months a consent lasts. A null tenant saves a system purpose every
-- organization uses, which takes the service role.
create or replace function ${fn("save_consent_purpose")}(
  tenant ${ctx.idType},
  key text,
  title text,
  version text default '1',
  description text default null,
  legal_basis text default 'consent',
  requires_signature boolean default false,
  valid_months integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${purposes};
  v_key text := lower(trim(save_consent_purpose.key));
  v_title text := trim(save_consent_purpose.title);
  v_version text := coalesce(nullif(trim(save_consent_purpose.version), ''), '1');
  v_description text := nullif(trim(save_consent_purpose.description), '');
  v_basis text := coalesce(save_consent_purpose.legal_basis, 'consent');
  v_signature boolean := coalesce(save_consent_purpose.requires_signature, false);
begin
  if save_consent_purpose.tenant is null then
    if not ${SERVICE_CALLER} then
      ${q.forbidden("only the service role saves a system purpose")}
    end if;
  elsif not ${q.allowed("save_consent_purpose.tenant", q.manage)} then
    ${q.forbidden("not allowed to manage consent purposes")}
  end if;
  if v_key is null or v_key !~ ${sqlString(PURPOSE_KEY)} then
    ${invalid("a purpose key is lowercase letters, digits, _, - and ., at most 63 characters")}
  end if;
  if coalesce(length(v_title), 0) not between 1 and 200 then
    ${invalid("a purpose needs a title of 1 to 200 characters")}
  end if;
  if length(v_version) > 40 then
    ${invalid("a purpose version is at most 40 characters")}
  end if;
  if length(v_description) > 4000 then
    ${invalid("a purpose description is at most 4000 characters")}
  end if;
  if v_basis not in (${list(LEGAL_BASES)}) then
    ${invalid("legal_basis is one of consent, contract, legal_obligation, vital_interest, public_task and legitimate_interest")}
  end if;
  if save_consent_purpose.valid_months is not null and save_consent_purpose.valid_months not between 1 and 1200 then
    ${invalid("valid_months is between 1 and 1200")}
  end if;
  select * into v_row from ${purposes} x
  where x.${p("tenant")} is not distinct from save_consent_purpose.tenant
    and x.${p("key")} = v_key and x.${p("version")} = v_version
  for update;
  if found then
    if v_row.${p("archivedAt")} is not null then
      ${archived}
    end if;
    update ${purposes} x set
      ${p("title")} = v_title,${description}
      ${p("legalBasis")} = ${q.cast("purposes", "legalBasis", "v_basis")},
      ${p("requiresSignature")} = v_signature,${updated}
      ${p("validMonths")} = save_consent_purpose.valid_months
    where x.${p("id")} = v_row.${p("id")}
    returning * into v_row;
    ${q.recordPurpose("consent_purpose.updated", "v_row", "changed a consent purpose")}
  else
    insert into ${purposes} (${p("tenant")}, ${p("key")}, ${p("title")}, ${has("purposes", "description") ? `${p("description")}, ` : ""}${p("legalBasis")}, ${p("version")}, ${p("requiresSignature")}, ${p("validMonths")})
    values (save_consent_purpose.tenant, v_key, v_title, ${has("purposes", "description") ? "v_description, " : ""}${q.cast("purposes", "legalBasis", "v_basis")}, v_version, v_signature, save_consent_purpose.valid_months)
    returning * into v_row;
    ${q.recordPurpose("consent_purpose.created", "v_row", "created a consent purpose")}
  end if;
  return ${purposeJson("v_row")};
end;
$$;
${userGrant(`${fn("save_consent_purpose")}(${ctx.idType}, text, text, text, text, text, boolean, integer)`)}

-- Archives a purpose: no new consent can be recorded for it, and the consents
-- already given stay as they are.
create or replace function ${fn("archive_consent_purpose")}(purpose_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${purposes};
begin
  select * into v_row from ${purposes} x where x.${p("id")} = archive_consent_purpose.purpose_id for update;
  if not found then
    ${q.purposeMissing}
  end if;
  if v_row.${p("tenant")} is null then
    if not ${SERVICE_CALLER} then
      ${q.forbidden("only the service role archives a system purpose")}
    end if;
  elsif not ${q.allowed(`v_row.${p("tenant")}`, q.manage)} then
    ${q.forbidden("not allowed to manage consent purposes")}
  end if;
  if v_row.${p("archivedAt")} is not null then
    return ${purposeJson("v_row")};
  end if;
  update ${purposes} x set${updated}
    ${p("archivedAt")} = now()
  where x.${p("id")} = v_row.${p("id")}
  returning * into v_row;
  ${q.recordPurpose("consent_purpose.updated", "v_row", "archived a consent purpose")}
  return ${purposeJson("v_row")};
end;
$$;
${userGrant(`${fn("archive_consent_purpose")}(uuid)`)}

-- The purposes an organization asks consent for: its own and the system ones,
-- by key, the newest version first.
create or replace function ${fn("list_consent_purposes")}(tenant ${ctx.idType}, include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (${SERVICE_CALLER} or list_consent_purposes.tenant in (select ${ctx.scope.members()})) then
    ${q.forbidden("not a member of this organization")}
  end if;
  return (
    select coalesce(jsonb_agg(${purposeJson("x")} order by x.${p("key")}, x.${p("createdAt")} desc, x.${p("id")}), '[]'::jsonb)
    from ${purposes} x
    where (x.${p("tenant")} = list_consent_purposes.tenant or x.${p("tenant")} is null)
      and (coalesce(list_consent_purposes.include_archived, false) or x.${p("archivedAt")} is null)
  );
end;
$$;
${userGrant(`${fn("list_consent_purposes")}(${ctx.idType}, boolean)`)}
`;
}

/** Checks that an evidence id names a row of `table` in tenant `v_tenant`. */
function evidence(
  q: ConsentsSql,
  variable: string,
  column: string,
  key: string,
  module: BlockSqlContext | undefined,
  table: string,
  what: string,
): string {
  const valid = `
  if v_evidence ? '${key}' and not pg_input_is_valid(v_evidence ->> '${key}', 'uuid') then
    ${q.invalid(`evidence.${key} is not a uuid`)}
  end if;
  ${variable} := (v_evidence ->> '${key}')::uuid;`;

  if (!q.has("consents", column)) {
    return `${valid}
  if ${variable} is not null then
    ${q.invalid(`the consents table has no ${column} column`)}
  end if;`;
  }

  if (module === undefined) {
    return valid;
  }

  return `${valid}
  if ${variable} is not null and not exists (
    select 1 from ${module.table(table)} x
    where x.${module.col(table, "id")} = ${variable} and x.${module.col(table, "tenant")}::text = v_tenant::text
  ) then
    ${q.invalid(`evidence.${key} is not ${what} of this organization`)}
  end if;`;
}

function recordFunction(ctx: BlockSqlContext, q: ConsentsSql): string {
  const { fn, c, p, has, purposes, consents, invalid, forbidden } = q;

  const tenant = subjectTenant(
    ctx,
    "record_consent.subject_type",
    "record_consent.subject_id",
  );

  const type = "record_consent.subject_type";
  const id = "record_consent.subject_id";

  const inserted = (
    [
      ["tenant", "v_tenant"],
      ["purpose", `v_purpose.${p("id")}`],
      ["subjectType", type],
      ["subjectId", id],
      ["givenBy", q.cast("consents", "givenBy", "v_given_by")],
      ["givenByContact", "v_contact"],
      ["givenByUser", "auth.uid()"],
      ["status", q.cast("consents", "status", "record_consent.status")],
      ["scope", "v_scope"],
      ["validUntil", "v_until"],
      ["signature", "v_signature"],
      ["submission", "v_submission"],
      ["attachment", "v_attachment"],
      ["createdBy", "auth.uid()"],
    ] as const
  ).filter(([column]) => has("consents", column));

  const sameKey = `x.${c("purpose")} in (
      select y.${p("id")} from ${purposes} y
      where y.${p("key")} = v_purpose.${p("key")} and (y.${p("tenant")} = v_tenant or y.${p("tenant")} is null)
    )`;

  const reason = has("consents", "withdrawnReason")
    ? `, ${c("withdrawnReason")} = 'superseded'`
    : "";

  return `-- Records a decision on a purpose for record subject_type/subject_id: status
-- granted or refused. A representative names the contact who decided. The
-- decision ends the grant it replaces. evidence is { signatureId,
-- submissionId, attachmentId }; a purpose that requires a signature needs
-- signatureId to grant.
create or replace function ${fn("record_consent")}(
  subject_type text,
  subject_id text,
  purpose_key text,
  status text,
  given_by text default 'self',
  given_by_contact_id uuid default null,
  valid_until timestamptz default null,
  scope jsonb default '{}'::jsonb,
  evidence jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant ${ctx.idType};
  v_purpose ${purposes};
  v_row ${consents};
  v_given_by text := coalesce(record_consent.given_by, 'self');
  v_contact uuid := record_consent.given_by_contact_id;
  v_scope jsonb := coalesce(record_consent.scope, '{}'::jsonb);
  v_evidence jsonb := coalesce(record_consent.evidence, '{}'::jsonb);
  v_until timestamptz := record_consent.valid_until;
  v_signature uuid;
  v_submission uuid;
  v_attachment uuid;
  v_representative uuid;
begin
  v_tenant := (${tenant})::${ctx.idType};
  if v_tenant is null or not ${q.recordable("v_tenant", type, id)} then
    ${forbidden("not allowed to record consent for this record")}
  end if;
  if not (${SERVICE_CALLER} or (${ctx.can("tenant", "v_tenant", q.record)} and ${q.canSubject(type, id)})) then
    v_representative := ${q.representative("v_tenant", type, id)};
    if v_representative is not null then
      v_given_by := 'representative';
      v_contact := v_representative;
    else
      v_given_by := 'self';
      v_contact := null;
    end if;
  end if;
  if record_consent.status is null or record_consent.status not in ('granted', 'refused') then
    ${invalid("status is granted or refused; withdraw_consent withdraws a consent")}
  end if;
  if v_given_by not in ('self', 'representative') then
    ${invalid("given_by is self or representative")}
  end if;
  if v_given_by = 'self' and v_contact is not null then
    ${invalid("only a representative's consent names a contact")}
  end if;
  if v_given_by = 'representative' then
    if v_contact is null then
      ${invalid("a representative's consent names the contact who gave it")}
    end if;
    if not ${q.actsFor("v_tenant", type, id, "v_contact")} then
      ${invalid("the contact doesn't represent this record with authority to act")}
    end if;
  end if;
  if jsonb_typeof(v_scope) <> 'object' or jsonb_typeof(v_evidence) <> 'object' then
    ${invalid("scope and evidence are JSON objects")}
  end if;
  select * into v_purpose from ${purposes} x
  where x.${p("key")} = record_consent.purpose_key
    and (x.${p("tenant")} = v_tenant or x.${p("tenant")} is null)
    and x.${p("archivedAt")} is null
  order by (x.${p("tenant")} is null), x.${p("createdAt")} desc, x.${p("id")}
  limit 1;
  if not found then
    if exists (
      select 1 from ${purposes} x
      where x.${p("key")} = record_consent.purpose_key and (x.${p("tenant")} = v_tenant or x.${p("tenant")} is null)
    ) then
      ${fail("CONSENT_PURPOSE_ARCHIVED", "the consent purpose is archived", "22023")}
    end if;
    ${q.purposeMissing}
  end if;${evidence(q, "v_signature", "signature", "signatureId", q.signatures, "signatures", "a signature")}${evidence(q, "v_submission", "submission", "submissionId", q.forms, "submissions", "a form submission")}${evidence(q, "v_attachment", "attachment", "attachmentId", q.attachments, "attachments", "an attachment")}
  if record_consent.status = 'granted' and v_purpose.${p("requiresSignature")} and v_signature is null then
    ${fail("CONSENT_SIGNATURE_REQUIRED", "this purpose needs a signature to grant consent", "22023")}
  end if;
  if record_consent.status = 'refused' then
    v_until := null;
  elsif v_until is null and v_purpose.${p("validMonths")} is not null then
    v_until := now() + make_interval(months => v_purpose.${p("validMonths")});
  end if;
  if v_until is not null and v_until <= now() then
    ${invalid("valid_until is in the past")}
  end if;
  ${ctx.hook("before_consent_record", [
    [ctx.idType, "v_tenant"],
    ["text", type],
    ["text", id],
    ["uuid", `v_purpose.${p("id")}`],
    ["text", "record_consent.status"],
  ])}
  update ${consents} x set
    ${c("status")} = ${q.cast("consents", "status", "'withdrawn'")},
    ${c("withdrawnAt")} = now()${reason}
  where x.${c("subjectType")} = ${type} and x.${c("subjectId")} = ${id}
    and x.${c("tenant")} = v_tenant and x.${c("status")} = 'granted'
    and ${sameKey};
  insert into ${consents} (${inserted.map(([column]) => c(column)).join(", ")})
  values (${inserted.map(([, value]) => value).join(", ")})
  returning * into v_row;
  if record_consent.status = 'granted' then
    ${q.recordConsent("consent.granted", "v_row", "v_purpose", "recorded a consent")}
  else
    ${q.recordConsent("consent.refused", "v_row", "v_purpose", "recorded a refused consent")}
  end if;
  ${ctx.hook("after_consent_record", [["uuid", `v_row.${c("id")}`]])}
  return ${q.consentJson("v_row", "v_purpose")};
end;
$$;
${userGrant(`${fn("record_consent")}(text, text, text, text, text, uuid, timestamptz, jsonb, jsonb)`)}
`;
}

function withdrawFunction(ctx: BlockSqlContext, q: ConsentsSql): string {
  const { fn, c, p, has, purposes, consents, invalid, forbidden } = q;
  const type = `v_row.${c("subjectType")}`;
  const id = `v_row.${c("subjectId")}`;

  const reason = has("consents", "withdrawnReason")
    ? `,\n    ${c("withdrawnReason")} = v_reason`
    : "";

  return `-- Withdraws a granted consent. The service role, members with
-- consents.record who read the record, the record's own guest, a
-- representative with authority to act and whoever recorded it may withdraw.
create or replace function ${fn("withdraw_consent")}(consent_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${consents};
  v_purpose ${purposes};
  v_reason text := nullif(trim(withdraw_consent.reason), '');
begin
  select * into v_row from ${consents} x where x.${c("id")} = withdraw_consent.consent_id for update;
  if not found then
    ${q.missing}
  end if;
  if not (${q.recordable(`v_row.${c("tenant")}`, type, id)} or coalesce(v_row.${c("givenByUser")} = auth.uid(), false)) then
    if ${q.readable(`v_row.${c("tenant")}`, type, id)} then
      ${forbidden("not allowed to withdraw this consent")}
    end if;
    ${q.missing}
  end if;
  if v_row.${c("status")} = 'withdrawn' then
    ${fail("CONSENT_ALREADY_WITHDRAWN", "the consent is already withdrawn", "22023")}
  end if;
  if v_row.${c("status")} <> 'granted' then
    ${invalid("only a granted consent can be withdrawn")}
  end if;
  if length(v_reason) > 1000 then
    ${invalid("a reason is at most 1000 characters")}
  end if;
  ${ctx.hook("before_consent_withdraw", [["uuid", `v_row.${c("id")}`]])}
  update ${consents} x set
    ${c("status")} = ${q.cast("consents", "status", "'withdrawn'")},
    ${c("withdrawnAt")} = now()${reason}
  where x.${c("id")} = v_row.${c("id")}
  returning * into v_row;
  select * into v_purpose from ${purposes} x where x.${p("id")} = v_row.${c("purpose")};
  ${q.recordConsent("consent.withdrawn", "v_row", "v_purpose", "withdrew a consent")}
  ${ctx.hook("after_consent_withdraw", [["uuid", `v_row.${c("id")}`]])}
  return ${q.consentJson("v_row", "v_purpose")};
end;
$$;
${userGrant(`${fn("withdraw_consent")}(uuid, text)`)}
`;
}

function readFunctions(ctx: BlockSqlContext, q: ConsentsSql): string {
  const { fn, c, p, purposes, consents } = q;

  const tenant = (func: string): string =>
    subjectTenant(ctx, `${func}.subject_type`, `${func}.subject_id`);

  return `-- Whether record subject_type/subject_id has a consent in force for the
-- current version of purpose_key: granted and not past valid_until. False for
-- a caller who can't read the record's consents.
create or replace function ${fn("consent_active")}(subject_type text, subject_id text, purpose_key text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant ${ctx.idType} := (${tenant("consent_active")})::${ctx.idType};
  v_purpose uuid;
begin
  if v_tenant is null or not ${q.readable("v_tenant", "consent_active.subject_type", "consent_active.subject_id")} then
    return false;
  end if;
  select x.${p("id")} into v_purpose from ${purposes} x
  where x.${p("key")} = consent_active.purpose_key
    and (x.${p("tenant")} = v_tenant or x.${p("tenant")} is null)
    and x.${p("archivedAt")} is null
  order by (x.${p("tenant")} is null), x.${p("createdAt")} desc, x.${p("id")}
  limit 1;
  return v_purpose is not null and exists (
    select 1 from ${consents} x
    where x.${c("tenant")} = v_tenant and x.${c("purpose")} = v_purpose
      and x.${c("subjectType")} = consent_active.subject_type and x.${c("subjectId")} = consent_active.subject_id
      and ${q.active("x")}
  );
end;
$$;
${userGrant(`${fn("consent_active")}(text, text, text)`)}

-- The consents of a record: the latest decision per purpose key, or with
-- include_history every decision, the newest first.
create or replace function ${fn("list_consents")}(subject_type text, subject_id text, include_history boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant ${ctx.idType} := (${tenant("list_consents")})::${ctx.idType};
begin
  if v_tenant is null or not ${q.readable("v_tenant", "list_consents.subject_type", "list_consents.subject_id")} then
    ${q.forbidden("not allowed to read the consents of this record")}
  end if;
  return (
    select coalesce(jsonb_agg(l.item order by l.key, l.created desc, l.id), '[]'::jsonb)
    from (
      select ${q.consentJson("x", "y")} as item, y.${p("key")} as key, x.${c("createdAt")} as created, x.${c("id")} as id,
        row_number() over (partition by y.${p("key")} order by x.${c("createdAt")} desc, x.${c("id")} desc) as n
      from ${consents} x
      join ${purposes} y on y.${p("id")} = x.${c("purpose")}
      where x.${c("tenant")} = v_tenant
        and x.${c("subjectType")} = list_consents.subject_type and x.${c("subjectId")} = list_consents.subject_id
    ) l
    where coalesce(list_consents.include_history, false) or l.n = 1
  );
end;
$$;
${userGrant(`${fn("list_consents")}(text, text, boolean)`)}

-- Marks every granted consent past valid_until expired and records
-- consent.expired for each. Run it on a schedule; returns how many expired.
create or replace function ${fn("expire_consents")}()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${consents};
  v_purpose ${purposes};
  v_count integer := 0;
begin
  for v_row in
    update ${consents} x set ${c("status")} = ${q.cast("consents", "status", "'expired'")}
    where x.${c("status")} = 'granted' and x.${c("validUntil")} <= now()
    returning x.*
  loop
    select * into v_purpose from ${purposes} y where y.${p("id")} = v_row.${c("purpose")};
    ${q.recordConsent("consent.expired", "v_row", "v_purpose", "a consent expired")}
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("expire_consents")}()`)}
`;
}

export function consentsFunctions(ctx: BlockSqlContext): string {
  const q = consentsSql(ctx);

  return `${purposeFunctions(ctx, q)}
${recordFunction(ctx, q)}
${withdrawFunction(ctx, q)}
${readFunctions(ctx, q)}`;
}
