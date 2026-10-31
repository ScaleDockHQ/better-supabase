import type { BlockSqlContext } from "../context.ts";
import type { ImportTargetContribution } from "../contributions.ts";
import type { PartyNames } from "./contacts-functions.ts";

import { DELIVERY_CHANNELS } from "../../blocks/contacts/roles.ts";
import { sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { fail, serviceGrant, userGrant } from "../shared.ts";
import { EMAIL_PATTERN } from "./contacts-identities.ts";
import { lookup } from "./contacts-roles.ts";
import { appUniqueIndex, lockModuleTable } from "./over-app.ts";

const channelList = DELIVERY_CHANNELS.map((channel) => sqlString(channel)).join(
  ", ",
);

/**
 * The `payment_terms` table: due days, an early-payment discount and a credit
 * restriction.
 */
export function termsTable(ctx: BlockSqlContext, names: PartyNames): string {
  if (!ctx.manages) {
    return "";
  }

  const { t, c } = names;
  const x = (column: string): string => c("terms", column);

  return `
create table if not exists ${t("terms")} (
  ${x("id")} uuid primary key default gen_random_uuid(),
  ${x("tenant")} ${ctx.idType} not null,
  ${x("code")} text not null check (length(${x("code")}) between 1 and 50),
  ${x("name")} text not null check (length(${x("name")}) between 1 and 300),
  ${x("days")} integer not null default 30 check (${x("days")} between 0 and 3650),
  ${x("discountBps")} integer not null default 0 check (${x("discountBps")} between 0 and 10000),
  ${x("discountDays")} integer not null default 0 check (${x("discountDays")} between 0 and 3650),
  ${x("creditRestrictionBps")} integer not null default 0 check (${x("creditRestrictionBps")} between 0 and 10000),
  ${x("createdAt")} timestamptz not null default now(),
  ${x("updatedAt")} timestamptz not null default now(),
  unique (${x("tenant")}, ${x("code")})
);${appUniqueIndex(ctx, "terms", ["tenant", "code"])}
${lockModuleTable(ctx, "terms", { read: true })}
${renderPolicy(makePolicy({ table: t("terms"), name: `${ctx.tableName("terms").name}_read`, command: "select", roles: ["authenticated"], using: ctx.scope.check(x("tenant"), names.read) }), { drop: true, target: t("terms") })}
`;
}

/**
 * The `document_delivery_preferences` table: how a party gets each kind of
 * document.
 */
export function deliveryTable(ctx: BlockSqlContext, names: PartyNames): string {
  if (!ctx.manages) {
    return "";
  }

  const { t, c } = names;
  const d = (column: string): string => c("deliveryPreferences", column);

  return `
create table if not exists ${t("deliveryPreferences")} (
  ${d("id")} uuid primary key default gen_random_uuid(),
  ${d("tenant")} ${ctx.idType} not null,
  ${d("party")} uuid not null,
  ${d("documentType")} text not null check (length(${d("documentType")}) between 1 and 100),
  ${d("channel")} text not null check (${d("channel")} in (${channelList})),
  ${d("copies")} integer not null default 1 check (${d("copies")} between 1 and 20),
  ${d("email")} text check (${d("email")} = lower(${d("email")}) and ${d("email")} ~ ${EMAIL_PATTERN}),
  ${d("createdAt")} timestamptz not null default now(),
  ${d("updatedAt")} timestamptz not null default now(),
  unique (${d("tenant")}, ${d("party")}, ${d("documentType")}, ${d("channel")})
);${appUniqueIndex(ctx, "deliveryPreferences", ["tenant", "party", "documentType", "channel"])}
create index if not exists ${ctx.naming.rename("document_delivery_preferences_party_idx")} on ${t("deliveryPreferences")} (${d("party")});
${lockModuleTable(ctx, "deliveryPreferences", { read: true })}
${renderPolicy(makePolicy({ table: t("deliveryPreferences"), name: `${ctx.tableName("deliveryPreferences").name}_read`, command: "select", roles: ["authenticated"], using: ctx.scope.check(d("tenant"), names.read) }), { drop: true, target: t("deliveryPreferences") })}
`;
}

/**
 * The payment terms and delivery preference calls: save, list and delete terms;
 * set and list a party's delivery preferences; and the writers the import
 * targets call.
 */
export function termsFunctions(
  ctx: BlockSqlContext,
  names: PartyNames,
): string {
  const { t, c, fn, scope } = names;
  const x = (column: string): string => c("terms", column);
  const d = (column: string): string => c("deliveryPreferences", column);
  const idType = ctx.idType;

  const termJson = (alias: string): string =>
    `jsonb_build_object('id', ${alias}.${x("id")}, 'organizationId', ${alias}.${x("tenant")}, 'code', ${alias}.${x("code")}, 'name', ${alias}.${x("name")}, 'days', ${alias}.${x("days")}, 'discountBps', ${alias}.${x("discountBps")}, 'discountDays', ${alias}.${x("discountDays")}, 'creditRestrictionBps', ${alias}.${x("creditRestrictionBps")}, 'createdAt', ${alias}.${x("createdAt")}, 'updatedAt', ${alias}.${x("updatedAt")})`;

  const prefJson = (alias: string): string =>
    `jsonb_build_object('id', ${alias}.${d("id")}, 'organizationId', ${alias}.${d("tenant")}, 'partyId', ${alias}.${d("party")}, 'documentType', ${alias}.${d("documentType")}, 'channel', ${alias}.${d("channel")}, 'copies', ${alias}.${d("copies")}, 'email', ${alias}.${d("email")})`;

  const allowed = (tenant: string, permission: string): string =>
    `(auth.role() = 'service_role' or ${scope.can(tenant, permission)})`;

  const invalidTerm = fail(
    "PAYMENT_TERM_INVALID",
    "payment terms need a code and a name; days are 0 to 3650, the discount and the credit restriction are 0 to 10000 basis points, discountDays 0 to 3650",
    "22023",
  );

  const integerKey = (key: string, max: number): string =>
    `(v_data ? '${key}' and (coalesce(v_data ->> '${key}', '') !~ '^[0-9]{1,5}$' or (v_data ->> '${key}')::integer > ${max}))`;

  return `
-- Creates or changes payment terms. data: code (unique per organization),
-- name, days (due days), discountBps and discountDays (an early-payment
-- discount the buyer may deduct), creditRestrictionBps (the part of the
-- document the tax does not apply to). A key that is not in data keeps its
-- value. Internal: save_payment_term and the import target call it.
create or replace function ${fn("payment_term_write")}(tenant ${idType}, data jsonb, id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_data jsonb := coalesce(payment_term_write.data, '{}'::jsonb);
  v_id uuid := payment_term_write.id;
  v_row ${t("terms")};
begin
  if jsonb_typeof(v_data) <> 'object'
    or ${integerKey("days", 3650)} or ${integerKey("discountBps", 10_000)}
    or ${integerKey("discountDays", 3650)} or ${integerKey("creditRestrictionBps", 10_000)}
    or coalesce((v_data ->> 'discountDays')::integer, 0) > coalesce((v_data ->> 'days')::integer, 30)
    or (v_data ? 'code' and length(coalesce(trim(v_data ->> 'code'), '')) not between 1 and 50)
    or (v_data ? 'name' and length(coalesce(trim(v_data ->> 'name'), '')) not between 1 and 300) then
    ${invalidTerm}
  end if;
  if v_id is null and v_data ->> 'code' is not null then
    select x.${x("id")} into v_id from ${t("terms")} x
    where x.${x("tenant")} = payment_term_write.tenant and x.${x("code")} = trim(v_data ->> 'code');
  end if;
  if v_id is null then
    if not (v_data ? 'code' and v_data ? 'name') then
      ${invalidTerm}
    end if;
    insert into ${t("terms")} (${x("tenant")}, ${x("code")}, ${x("name")}, ${x("days")}, ${x("discountBps")}, ${x("discountDays")}, ${x("creditRestrictionBps")})
    values (payment_term_write.tenant, trim(v_data ->> 'code'), trim(v_data ->> 'name'),
      coalesce((v_data ->> 'days')::integer, 30), coalesce((v_data ->> 'discountBps')::integer, 0),
      coalesce((v_data ->> 'discountDays')::integer, 0), coalesce((v_data ->> 'creditRestrictionBps')::integer, 0))
    returning * into v_row;
  else
    begin
      update ${t("terms")} x set
        ${x("code")} = coalesce(trim(v_data ->> 'code'), x.${x("code")}),
        ${x("name")} = coalesce(trim(v_data ->> 'name'), x.${x("name")}),
        ${x("days")} = coalesce((v_data ->> 'days')::integer, x.${x("days")}),
        ${x("discountBps")} = coalesce((v_data ->> 'discountBps')::integer, x.${x("discountBps")}),
        ${x("discountDays")} = coalesce((v_data ->> 'discountDays')::integer, x.${x("discountDays")}),
        ${x("creditRestrictionBps")} = coalesce((v_data ->> 'creditRestrictionBps')::integer, x.${x("creditRestrictionBps")}),
        ${x("updatedAt")} = now()
      where x.${x("id")} = v_id and x.${x("tenant")} = payment_term_write.tenant
      returning * into v_row;
    exception when unique_violation then
      ${fail("PAYMENT_TERM_CODE_TAKEN", "another payment terms row has this code", "23505")}
    end;
    if v_row.${x("id")} is null then
      ${fail("PAYMENT_TERM_NOT_FOUND", "payment terms not found", "P0002")}
    end if;
  end if;
  return ${termJson("v_row")};
end;
$$;
revoke execute on function ${fn("payment_term_write")}(${idType}, jsonb, uuid) from public, anon, authenticated;

-- Creates payment terms, or changes the ones with the same code. Needs
-- contacts.manage. Returns the row.
create or replace function ${fn("save_payment_term")}(tenant ${idType}, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not ${allowed("save_payment_term.tenant", names.manage)} then
    ${fail("PARTY_FORBIDDEN", "not allowed to manage payment terms")}
  end if;
  return ${fn("payment_term_write")}(save_payment_term.tenant, save_payment_term.attrs, null);
end;
$$;
${userGrant(`${fn("save_payment_term")}(${idType}, jsonb)`)}

create or replace function ${fn("list_payment_terms")}(tenant ${idType})
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${termJson("x")} order by x.${x("code")}), '[]'::jsonb)
  from ${t("terms")} x
  where x.${x("tenant")} = list_payment_terms.tenant
$$;
${userGrant(`${fn("list_payment_terms")}(${idType})`)}

-- Deletes payment terms. Parties that point at them lose the link; invoices
-- keep the terms they copied. Needs contacts.manage.
create or replace function ${fn("delete_payment_term")}(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${idType};
begin
  select x.${x("tenant")} into v_tenant from ${t("terms")} x where x.${x("id")} = delete_payment_term.id;
  if v_tenant is null then
    return false;
  end if;
  if not ${allowed("v_tenant", names.manage)} then
    ${fail("PARTY_FORBIDDEN", "not allowed to manage payment terms")}
  end if;
  delete from ${t("terms")} x where x.${x("id")} = delete_payment_term.id;
  return found;
end;
$$;
${userGrant(`${fn("delete_payment_term")}(uuid)`)}

-- Replaces how a party gets its documents. prefs: [{ documentType, channel
-- (email, post or portal), copies (default 1), email }]; an email channel
-- without an email uses the party's own. Returns the stored list. Needs
-- contacts.write.
create or replace function ${fn("set_document_delivery_preferences")}(party uuid, prefs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind text;
  v_tenant ${idType};
  v_name text;
begin
${lookup(names, "set_document_delivery_preferences.party")}
  if v_kind is null then
    ${fail("PARTY_NOT_FOUND", "company or person not found", "P0002")}
  end if;
  if not ${allowed("v_tenant", names.write)} then
    ${fail("PARTY_FORBIDDEN", "not allowed to change companies and people")}
  end if;
  if jsonb_typeof(set_document_delivery_preferences.prefs) is distinct from 'array'
    or jsonb_array_length(set_document_delivery_preferences.prefs) > 100
    or exists (
      select 1 from jsonb_array_elements(set_document_delivery_preferences.prefs) e
      where jsonb_typeof(e) <> 'object'
        or length(coalesce(trim(e ->> 'documentType'), '')) not between 1 and 100
        or coalesce(e ->> 'channel', '') not in (${channelList})
        or coalesce(e ->> 'copies', '1') !~ '^[0-9]{1,2}$'
        or coalesce(nullif(e ->> 'copies', '')::integer, 1) not between 1 and 20
        or (e ->> 'email' is not null and lower(trim(e ->> 'email')) !~ ${EMAIL_PATTERN})
    ) or (
      select count(*) <> count(distinct (trim(e ->> 'documentType'), e ->> 'channel'))
      from jsonb_array_elements(set_document_delivery_preferences.prefs) e
    ) then
    ${fail("DELIVERY_PREFERENCE_INVALID", "prefs is an array of at most 100 { documentType, channel, copies, email } with a unique documentType and channel", "22023")}
  end if;
  delete from ${t("deliveryPreferences")} x where x.${d("party")} = set_document_delivery_preferences.party and x.${d("tenant")} = v_tenant;
  insert into ${t("deliveryPreferences")} (${d("tenant")}, ${d("party")}, ${d("documentType")}, ${d("channel")}, ${d("copies")}, ${d("email")})
  select v_tenant, set_document_delivery_preferences.party, trim(e ->> 'documentType'), e ->> 'channel',
    coalesce(nullif(e ->> 'copies', '')::integer, 1), nullif(lower(trim(e ->> 'email')), '')
  from jsonb_array_elements(set_document_delivery_preferences.prefs) e;
  return ${fn("list_document_delivery_preferences")}(set_document_delivery_preferences.party);
end;
$$;
${userGrant(`${fn("set_document_delivery_preferences")}(uuid, jsonb)`)}

create or replace function ${fn("list_document_delivery_preferences")}(party uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${prefJson("x")} order by x.${d("documentType")}, x.${d("channel")}), '[]'::jsonb)
  from ${t("deliveryPreferences")} x
  where x.${d("party")} = list_document_delivery_preferences.party
$$;
${userGrant(`${fn("list_document_delivery_preferences")}(uuid)`)}

-- The writer of one delivery preference for imports. data: { partyId,
-- documentType, channel, copies, email }.
create or replace function ${fn("delivery_preference_write")}(tenant ${idType}, data jsonb, id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("deliveryPreferences")};
begin
  if jsonb_typeof(delivery_preference_write.data) is distinct from 'object'
    or coalesce(delivery_preference_write.data ->> 'partyId', '') !~ '^[0-9a-fA-F-]{36}$'
    or length(coalesce(trim(delivery_preference_write.data ->> 'documentType'), '')) not between 1 and 100
    or coalesce(delivery_preference_write.data ->> 'channel', '') not in (${channelList})
    or coalesce(delivery_preference_write.data ->> 'copies', '1') !~ '^[0-9]{1,2}$'
    or coalesce(nullif(delivery_preference_write.data ->> 'copies', '')::integer, 1) not between 1 and 20
    or (delivery_preference_write.data ->> 'email' is not null and lower(trim(delivery_preference_write.data ->> 'email')) !~ ${EMAIL_PATTERN}) then
    ${fail("DELIVERY_PREFERENCE_INVALID", "a delivery preference needs a party, a document type and a channel of email, post or portal", "22023")}
  end if;
  insert into ${t("deliveryPreferences")} (${d("tenant")}, ${d("party")}, ${d("documentType")}, ${d("channel")}, ${d("copies")}, ${d("email")})
  values (delivery_preference_write.tenant, (delivery_preference_write.data ->> 'partyId')::uuid, trim(delivery_preference_write.data ->> 'documentType'),
    delivery_preference_write.data ->> 'channel', coalesce(nullif(delivery_preference_write.data ->> 'copies', '')::integer, 1),
    nullif(lower(trim(delivery_preference_write.data ->> 'email')), ''))
  on conflict (${d("tenant")}, ${d("party")}, ${d("documentType")}, ${d("channel")}) do update
    set ${d("copies")} = excluded.${d("copies")}, ${d("email")} = excluded.${d("email")}, ${d("updatedAt")} = now()
  returning * into v_row;
  return ${prefJson("v_row")};
end;
$$;
revoke execute on function ${fn("delivery_preference_write")}(${idType}, jsonb, uuid) from public, anon, authenticated;
${resolveFunction(ctx, names)}${importFunctions(ctx, names)}`;
}

/**
 * `resolve_payment_terms`: the terms an invoice copies. A terms id names them
 * directly; otherwise the party's customer terms (or supplier terms for a
 * purchase) are the ones. Internal: the invoices block calls it.
 */
function resolveFunction(ctx: BlockSqlContext, names: PartyNames): string {
  const { t, c, fn } = names;
  const idType = ctx.idType;
  const x = (column: string): string => c("terms", column);

  const owners = (["companies", "people"] as const)
    .filter(
      (table) =>
        ctx.has(table, "customerTermsId") || ctx.has(table, "supplierTermsId"),
    )
    .map((table) => {
      const pick = (logical: string): string =>
        ctx.has(table, logical) ? `p.${c(table, logical)}` : "null::uuid";

      return `select case when resolve_payment_terms.direction = 'purchase' then ${pick("supplierTermsId")} else ${pick("customerTermsId")} end as id
      from ${t(table)} p where p.${c(table, "id")}::text = resolve_payment_terms.party and p.${c(table, "tenant")} = resolve_payment_terms.tenant`;
    });

  const byParty =
    owners.length === 0
      ? "null::uuid"
      : `(select o.id from (${owners.join("\n      union all\n      ")}) o where o.id is not null limit 1)`;

  return `
-- The payment terms an invoice copies: terms_id when it is given, otherwise
-- the party's customer terms (supplier terms for direction purchase). Null
-- when there are none. Internal: create_invoice calls it.
create or replace function ${fn("resolve_payment_terms")}(tenant ${idType}, terms_id uuid, party text, direction text default 'sales')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', z.${x("id")}, 'days', z.${x("days")}, 'discountBps', z.${x("discountBps")}, 'discountDays', z.${x("discountDays")}, 'creditRestrictionBps', z.${x("creditRestrictionBps")})
  from ${t("terms")} z
  where z.${x("tenant")} = resolve_payment_terms.tenant
    and z.${x("id")} = coalesce(resolve_payment_terms.terms_id, ${byParty})
$$;
revoke execute on function ${fn("resolve_payment_terms")}(${idType}, uuid, text, text) from public, anon, authenticated;
`;
}

/** The import targets of payment terms and delivery preferences (ADR 0141). */
function importFunctions(ctx: BlockSqlContext, names: PartyNames): string {
  const { t, c, fn } = names;
  const idType = ctx.idType;

  const target = (
    name: string,
    writer: string,
    table: string,
    label: string,
  ): string => `
-- The import target of the ${label} entity: item.data is the input of the writer.
create or replace function ${fn(`import_${name}`)}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb;
begin
  if jsonb_typeof(import_${name}.item -> 'data') is distinct from 'object' then
    ${fail("IMPORT_ITEM_INVALID", `a ${label} item needs data`, "22023")}
  end if;
  v_row := ${fn(writer)}((import_${name}.item ->> 'tenant')::${idType}, import_${name}.item -> 'data', import_${name}.subject_id::uuid);
  return jsonb_build_object('subjectId', v_row ->> 'id', 'updatedAt', v_row ->> 'updatedAt');
end;
$$;
${serviceGrant(`${fn(`import_${name}`)}(uuid, jsonb, text)`)}

-- When a ${label} row last changed, for the conflict check of imports.
create or replace function ${fn(`${name}_updated_at`)}(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x.${c(table, "updatedAt")} from ${t(table)} x where x.${c(table, "id")}::text = ${name}_updated_at.subject_id
$$;
${serviceGrant(`${fn(`${name}_updated_at`)}(text)`)}
`;

  return `${target("payment_term", "payment_term_write", "terms", "payment terms")}${target("document_delivery_preference", "delivery_preference_write", "deliveryPreferences", "delivery preference")}`;
}

const plain = (qualified: string): string => qualified.replaceAll('"', "");

/** What `contributes.imports` returns: payment terms and delivery preferences. */
export function termsImportTargets(
  own: BlockSqlContext,
): readonly ImportTargetContribution[] {
  return own.mode === "custom"
    ? []
    : [
        {
          entity: "payment_term",
          subjectType: "payment_term",
          write: plain(own.fn("import_payment_term")),
          updatedAt: plain(own.fn("payment_term_updated_at")),
        },
        {
          entity: "document_delivery_preference",
          subjectType: "document_delivery_preference",
          write: plain(own.fn("import_document_delivery_preference")),
          updatedAt: plain(own.fn("document_delivery_preference_updated_at")),
        },
      ];
}
