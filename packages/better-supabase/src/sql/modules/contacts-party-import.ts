import type { BlockSqlContext } from "../context.ts";
import type { ImportTargetContribution } from "../contributions.ts";
import type { PartyNames } from "./contacts-functions.ts";

import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { fail, serviceGrant } from "../shared.ts";
import { appUniqueIndex, lockModuleTable } from "./over-app.ts";

const BUSINESS =
  "\\m(b\\.?v\\.?|n\\.?v\\.?|gmbh|ltd\\.?|llc|inc\\.?|bvba|vof|stichting|holding)\\M";

const plain = (qualified: string): string => qualified.replaceAll('"', "");

interface Field {
  readonly logical: string;
  readonly expr: string;
}

/** Columns the import writes, dropped when the app maps one to null. */
function written(
  ctx: BlockSqlContext,
  table: string,
  fields: readonly Field[],
): { cols: string; vals: string; sets: string; same: string } {
  const present = fields.filter((field) => ctx.has(table, field.logical));
  const col = (logical: string): string => ctx.col(table, logical);

  return {
    cols: present.map((field) => col(field.logical)).join(", "),
    vals: present.map((field) => field.expr).join(", "),
    sets: present
      .map((field) => `${col(field.logical)} = ${field.expr}`)
      .join(", "),
    same: present
      .map(
        (field) => `x.${col(field.logical)} is not distinct from ${field.expr}`,
      )
      .join(" and "),
  };
}

/** Locations, bank accounts and contact methods a party import can write. */
export function partyPlaceTables(
  ctx: BlockSqlContext,
  names: PartyNames,
): string {
  if (!ctx.manages) {
    return "";
  }

  const { t, c } = names;

  const table = (
    key: "locations" | "bankAccounts" | "channels",
    body: string,
    unique: readonly string[],
  ): string => {
    const id = c(key, "id");

    return `
create table if not exists ${t(key)} (
  ${id} uuid primary key default gen_random_uuid(),
  ${body}
  ${c(key, "createdAt")} timestamptz not null default now(),
  ${c(key, "updatedAt")} timestamptz not null default now()
);${appUniqueIndex(ctx, key, unique)}
${lockModuleTable(ctx, key, { read: true })}
${renderPolicy(
  makePolicy({
    table: t(key),
    name: `${ctx.tableName(key).name}_read`,
    command: "select",
    roles: ["authenticated"],
    using: ctx.scope.check(c(key, "tenant"), names.read),
  }),
  { target: t(key) },
)}
`;
  };

  return `${table(
    "locations",
    `${c("locations", "tenant")} ${ctx.idType} not null,
  ${c("locations", "party")} uuid not null,
  ${c("locations", "kind")} text not null default 'other',
  ${c("locations", "line1")} text,
  ${c("locations", "line2")} text,
  ${c("locations", "postalCode")} text,
  ${c("locations", "city")} text,
  ${c("locations", "country")} text,
  ${c("locations", "latitude")} double precision,
  ${c("locations", "longitude")} double precision,
  ${c("locations", "isPrimary")} boolean not null default false,`,
    ["tenant", "party", "kind", "line1"],
  )}
create unique index if not exists ${ctx.naming.rename("party_locations_primary_idx")}
  on ${t("locations")} (${c("locations", "tenant")}, ${c("locations", "party")}) where ${c("locations", "isPrimary")};
${table(
  "bankAccounts",
  `${c("bankAccounts", "tenant")} ${ctx.idType} not null,
  ${c("bankAccounts", "party")} uuid not null,
  ${c("bankAccounts", "iban")} text not null,
  ${c("bankAccounts", "bic")} text,
  ${c("bankAccounts", "holder")} text,
  ${c("bankAccounts", "isPrimary")} boolean not null default false,
  unique (${c("bankAccounts", "tenant")}, ${c("bankAccounts", "iban")}),`,
  ["tenant", "iban"],
)}
create unique index if not exists ${ctx.naming.rename("party_bank_accounts_primary_idx")}
  on ${t("bankAccounts")} (${c("bankAccounts", "tenant")}, ${c("bankAccounts", "party")}) where ${c("bankAccounts", "isPrimary")};
${table(
  "channels",
  `${c("channels", "tenant")} ${ctx.idType} not null,
  ${c("channels", "party")} uuid not null,
  ${c("channels", "partyKind")} text not null check (${c("channels", "partyKind")} in ('person', 'company')),
  ${c("channels", "channel")} text not null check (${c("channels", "channel")} in ('email', 'phone', 'mobile', 'fax', 'whatsapp')),
  ${c("channels", "label")} text,
  ${c("channels", "address")} text not null,
  ${c("channels", "isPrimary")} boolean not null default false,
  unique (${c("channels", "tenant")}, ${c("channels", "party")}, ${c("channels", "channel")}, ${c("channels", "address")}),`,
  ["tenant", "party", "channel", "address"],
)}
`;
}

/** Party, contact, method, location and bank-account import targets. */
export function partyImportSql(
  ctx: BlockSqlContext,
  names: PartyNames,
): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const { fn, t, c } = names;
  const company = written(ctx, "companies", companyFields(ctx, names));
  const person = written(ctx, "people", personFields(ctx, names));
  const co = (column: string): string => c("companies", column);
  const pe = (column: string): string => c("people", column);

  return `
-- One party. kind is person, company or auto (a legal suffix is a company).
-- A name comes from displayName, then legalName, then the person names, then
-- number. Anything but displayName adds IMPORT_NAME_FALLBACK. A repeat whose
-- stored columns already match returns without writing.
create or replace function ${fn("import_party")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_data jsonb := import_party.item -> 'data';
  v_tenant ${ctx.idType} := (import_party.item ->> 'tenant')::${ctx.idType};
  v_display text := nullif(btrim(v_data ->> 'displayName'), '');
  v_legal text := nullif(btrim(v_data ->> 'legalName'), '');
  v_person text := nullif(btrim(concat_ws(' ', v_data ->> 'givenName', v_data ->> 'infix', v_data ->> 'lastName')), '');
  v_number text := nullif(btrim(v_data ->> 'number'), '');
  v_name text := coalesce(v_display, v_legal, v_person, v_number);
  v_kind text := coalesce(nullif(v_data ->> 'kind', ''), 'auto');
  v_warnings jsonb := '[]'::jsonb;
  v_id uuid;
  v_updated timestamptz;
  v_same boolean;
begin
  if jsonb_typeof(v_data) is distinct from 'object' or v_name is null then
    ${fail("IMPORT_ITEM_INVALID", "a party needs a display name, a legal name, a person name or a number", "22023")}
  end if;
  if v_display is null then
    v_warnings := jsonb_build_array(jsonb_build_object('code', 'IMPORT_NAME_FALLBACK', 'message', 'the party name came from a fallback'));
  end if;
  if v_kind = 'auto' then
    v_kind := case when v_name ~* '${BUSINESS}' then 'company' else 'person' end;
  end if;
  if v_kind = 'company' then
    if import_party.subject_id is not null then
      select x.${co("id")}, x.${co("updatedAt")}, ${company.same} into v_id, v_updated, v_same
      from ${t("companies")} x
      where x.${co("id")} = import_party.subject_id::uuid and x.${co("tenant")} = v_tenant;
      if v_id is not null and v_same then
        return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated, 'warnings', v_warnings);
      end if;
      update ${t("companies")} x set ${company.sets}, ${co("updatedAt")} = now()
      where x.${co("id")} = import_party.subject_id::uuid and x.${co("tenant")} = v_tenant
      returning x.${co("id")}, x.${co("updatedAt")} into v_id, v_updated;
    end if;
    if v_id is null then
      insert into ${t("companies")} (${co("tenant")}, ${company.cols})
      values (v_tenant, ${company.vals})
      returning ${co("id")}, ${co("updatedAt")} into v_id, v_updated;
    end if;
  elsif v_kind = 'person' then
    if import_party.subject_id is not null then
      select x.${pe("id")}, x.${pe("updatedAt")}, ${person.same} into v_id, v_updated, v_same
      from ${t("people")} x
      where x.${pe("id")} = import_party.subject_id::uuid and x.${pe("tenant")} = v_tenant;
      if v_id is not null and v_same then
        return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated, 'warnings', v_warnings);
      end if;
      update ${t("people")} x set ${person.sets}, ${pe("updatedAt")} = now()
      where x.${pe("id")} = import_party.subject_id::uuid and x.${pe("tenant")} = v_tenant
      returning x.${pe("id")}, x.${pe("updatedAt")} into v_id, v_updated;
    end if;
    if v_id is null then
      insert into ${t("people")} (${pe("tenant")}, ${person.cols})
      values (v_tenant, ${person.vals})
      returning ${pe("id")}, ${pe("updatedAt")} into v_id, v_updated;
    end if;
  else
    ${fail("IMPORT_ITEM_INVALID", "kind is person, company or auto", "22023")}
  end if;
  return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated, 'warnings', v_warnings);
end;
$$;
${serviceGrant(`${fn("import_party")}(uuid, jsonb, text)`)}

create or replace function ${fn("party_updated_at")}(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select x.${co("updatedAt")} from ${t("companies")} x where x.${co("id")}::text = party_updated_at.subject_id),
    (select x.${pe("updatedAt")} from ${t("people")} x where x.${pe("id")}::text = party_updated_at.subject_id))
$$;
${serviceGrant(`${fn("party_updated_at")}(text)`)}
${linkTarget(ctx, names)}
${channelTarget(ctx, names)}
${locationTarget(ctx, names)}
${bankTarget(ctx, names)}
`;
}

function companyFields(ctx: BlockSqlContext, names: PartyNames): Field[] {
  const terms = ctx.has("companies", "customerTermsId")
    ? `(select p.${ctx.col("terms", "id")} from ${ctx.table("terms")} p where p.${ctx.col("terms", "tenant")} = v_tenant and p.${ctx.col("terms", "code")} = nullif(btrim(v_data ->> 'termsCode'), ''))`
    : "null::uuid";

  return [
    { logical: "name", expr: "v_name" },
    { logical: "legalName", expr: "coalesce(v_legal, v_name)" },
    { logical: "vatId", expr: "nullif(btrim(v_data ->> 'vatId'), '')" },
    {
      logical: "registrationId",
      expr: "nullif(btrim(v_data ->> 'registrationId'), '')",
    },
    {
      logical: "phone",
      expr: "better_supabase.normalize_phone(v_data ->> 'phone', v_data ->> 'region')",
    },
    {
      logical: "billingEmail",
      expr: "nullif(lower(btrim(v_data ->> 'billingEmail')), '')",
    },
    {
      logical: "billTo",
      expr: "nullif(coalesce(import_party.item -> 'resolved' ->> 'billTo', v_data ->> 'billToId'), '')::uuid",
    },
    {
      logical: "lifecycle",
      expr: ctx.cast(
        "companies",
        "lifecycle",
        `coalesce(nullif(v_data ->> 'lifecycle', ''), (${names.companyStages})[1])`,
      ),
    },
    { logical: "language", expr: "nullif(btrim(v_data ->> 'language'), '')" },
    {
      logical: "roles",
      expr: "case when jsonb_typeof(v_data -> 'roles') = 'array' then (select coalesce(array_agg(r), '{}'::text[]) from jsonb_array_elements_text(v_data -> 'roles') r) else null end",
    },
    { logical: "customerTermsId", expr: terms },
    {
      logical: "archivedAt",
      expr: "nullif(v_data ->> 'archivedAt', '')::timestamptz",
    },
  ];
}

function personFields(ctx: BlockSqlContext, names: PartyNames): Field[] {
  return [
    { logical: "name", expr: "v_name" },
    { logical: "givenName", expr: "nullif(btrim(v_data ->> 'givenName'), '')" },
    { logical: "lastName", expr: "nullif(btrim(v_data ->> 'lastName'), '')" },
    { logical: "initials", expr: "nullif(btrim(v_data ->> 'initials'), '')" },
    { logical: "infix", expr: "nullif(btrim(v_data ->> 'infix'), '')" },
    { logical: "email", expr: "nullif(lower(btrim(v_data ->> 'email')), '')" },
    {
      logical: "phone",
      expr: "better_supabase.normalize_phone(v_data ->> 'phone', v_data ->> 'region')",
    },
    {
      logical: "lifecycle",
      expr: ctx.cast(
        "people",
        "lifecycle",
        `coalesce(nullif(v_data ->> 'lifecycle', ''), (${names.personStages})[1])`,
      ),
    },
    { logical: "language", expr: "nullif(btrim(v_data ->> 'language'), '')" },
    {
      logical: "roles",
      expr: "case when jsonb_typeof(v_data -> 'roles') = 'array' then (select coalesce(array_agg(r), '{}'::text[]) from jsonb_array_elements_text(v_data -> 'roles') r) else null end",
    },
    {
      logical: "archivedAt",
      expr: "nullif(v_data ->> 'archivedAt', '')::timestamptz",
    },
  ];
}

function linkTarget(ctx: BlockSqlContext, names: PartyNames): string {
  const { fn, t, c } = names;
  const li = (column: string): string => c("links", column);

  const role = ctx.has("links", "role")
    ? `, ${li("role")} = nullif(btrim(v_data ->> 'role'), '')`
    : "";

  const sameRole = ctx.has("links", "role")
    ? `and x.${li("role")} is not distinct from nullif(btrim(v_data ->> 'role'), '')`
    : "";

  return `
create or replace function ${fn("import_party_contact")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_data jsonb := import_party_contact.item -> 'data';
  v_company uuid := nullif(coalesce(import_party_contact.item -> 'resolved' ->> 'company', v_data ->> 'companyId'), '')::uuid;
  v_person uuid := nullif(coalesce(import_party_contact.item -> 'resolved' ->> 'person', v_data ->> 'personId'), '')::uuid;
  v_primary boolean := coalesce((v_data ->> 'isPrimary')::boolean, false);
begin
  if v_company is null or v_person is null then
    ${fail("IMPORT_ITEM_INVALID", "a party contact needs a company and a person", "22023")}
  end if;
  if exists (
    select 1 from ${t("links")} x
    where x.${li("company")} = v_company and x.${li("person")} = v_person
      and x.${li("isPrimary")} is not distinct from v_primary
      ${sameRole}
  ) then
    return jsonb_build_object('subjectId', v_company::text || ':' || v_person::text, 'updatedAt',
      (select x.${li("createdAt")} from ${t("links")} x where x.${li("company")} = v_company and x.${li("person")} = v_person));
  end if;
  insert into ${t("links")} (${li("tenant")}, ${li("company")}, ${li("person")}, ${li("isPrimary")}${ctx.has("links", "role") ? `, ${li("role")}` : ""})
  values ((import_party_contact.item ->> 'tenant')::${ctx.idType}, v_company, v_person, v_primary${ctx.has("links", "role") ? `, nullif(btrim(v_data ->> 'role'), '')` : ""})
  on conflict (${li("company")}, ${li("person")}) do update
    set ${li("isPrimary")} = excluded.${li("isPrimary")}${role};
  return jsonb_build_object('subjectId', v_company::text || ':' || v_person::text, 'updatedAt', now());
end;
$$;
${serviceGrant(`${fn("import_party_contact")}(uuid, jsonb, text)`)}

create or replace function ${fn("party_contact_updated_at")}(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x.${li("createdAt")} from ${t("links")} x
  where x.${li("company")}::text = split_part(party_contact_updated_at.subject_id, ':', 1)
    and x.${li("person")}::text = split_part(party_contact_updated_at.subject_id, ':', 2)
$$;
${serviceGrant(`${fn("party_contact_updated_at")}(text)`)}
`;
}

function channelTarget(ctx: BlockSqlContext, names: PartyNames): string {
  const { fn, t, c } = names;
  const ch = (column: string): string => c("channels", column);

  return `
create or replace function ${fn("import_contact_method")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_data jsonb := import_contact_method.item -> 'data';
  v_party uuid := nullif(coalesce(import_contact_method.item -> 'resolved' ->> 'party', v_data ->> 'partyId'), '')::uuid;
  v_kind text := coalesce(nullif(v_data ->> 'partyKind', ''), 'person');
  v_channel text := nullif(v_data ->> 'channel', '');
  v_address text := nullif(btrim(v_data ->> 'address'), '');
  v_id uuid;
  v_updated timestamptz;
begin
  if v_channel in ('email') then
    v_address := nullif(lower(v_address), '');
  elsif v_channel in ('phone', 'mobile', 'fax', 'whatsapp') then
    v_address := nullif(better_supabase.normalize_phone(v_address, v_data ->> 'region'), '');
  end if;
  if v_party is null or v_kind not in ('person', 'company') or v_channel not in ('email', 'phone', 'mobile', 'fax', 'whatsapp') or v_address is null then
    ${fail("IMPORT_ITEM_INVALID", "a contact method needs a party, a channel and an address", "22023")}
  end if;
  select x.${ch("id")}, x.${ch("updatedAt")} into v_id, v_updated from ${t("channels")} x
  where x.${ch("tenant")} = (import_contact_method.item ->> 'tenant')::${ctx.idType}
    and x.${ch("party")} = v_party and x.${ch("channel")} = v_channel and x.${ch("address")} = v_address
    and x.${ch("label")} is not distinct from nullif(btrim(v_data ->> 'label'), '')
    and x.${ch("isPrimary")} is not distinct from coalesce((v_data ->> 'isPrimary')::boolean, false);
  if v_id is not null then
    return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
  end if;
  insert into ${t("channels")} (${ch("tenant")}, ${ch("party")}, ${ch("partyKind")}, ${ch("channel")}, ${ch("label")}, ${ch("address")}, ${ch("isPrimary")})
  values ((import_contact_method.item ->> 'tenant')::${ctx.idType}, v_party, v_kind, v_channel, nullif(btrim(v_data ->> 'label'), ''), v_address, coalesce((v_data ->> 'isPrimary')::boolean, false))
  on conflict (${ch("tenant")}, ${ch("party")}, ${ch("channel")}, ${ch("address")}) do update
    set ${ch("label")} = excluded.${ch("label")}, ${ch("isPrimary")} = excluded.${ch("isPrimary")}, ${ch("updatedAt")} = now()
  returning ${ch("id")}, ${ch("updatedAt")} into v_id, v_updated;
  return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
end;
$$;
${serviceGrant(`${fn("import_contact_method")}(uuid, jsonb, text)`)}

create or replace function ${fn("contact_method_updated_at")}(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x.${ch("updatedAt")} from ${t("channels")} x where x.${ch("id")}::text = contact_method_updated_at.subject_id
$$;
${serviceGrant(`${fn("contact_method_updated_at")}(text)`)}
`;
}

function locationTarget(ctx: BlockSqlContext, names: PartyNames): string {
  const { fn, t, c } = names;
  const lo = (column: string): string => c("locations", column);

  const fields = written(ctx, "locations", [
    { logical: "party", expr: "v_party" },
    {
      logical: "kind",
      expr: "coalesce(nullif(v_data ->> 'kind', ''), 'other')",
    },
    { logical: "line1", expr: "nullif(btrim(v_data ->> 'line1'), '')" },
    { logical: "line2", expr: "nullif(btrim(v_data ->> 'line2'), '')" },
    {
      logical: "postalCode",
      expr: "nullif(btrim(v_data ->> 'postalCode'), '')",
    },
    { logical: "city", expr: "nullif(btrim(v_data ->> 'city'), '')" },
    { logical: "country", expr: "nullif(btrim(v_data ->> 'country'), '')" },
    {
      logical: "latitude",
      expr: "nullif(v_data ->> 'latitude', '')::double precision",
    },
    {
      logical: "longitude",
      expr: "nullif(v_data ->> 'longitude', '')::double precision",
    },
    {
      logical: "isPrimary",
      expr: "coalesce((v_data ->> 'isPrimary')::boolean, false)",
    },
  ]);

  return `
create or replace function ${fn("import_party_location")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_data jsonb := import_party_location.item -> 'data';
  v_party uuid := nullif(coalesce(import_party_location.item -> 'resolved' ->> 'party', v_data ->> 'partyId'), '')::uuid;
  v_id uuid;
  v_updated timestamptz;
  v_same boolean;
begin
  if v_party is null then
    ${fail("IMPORT_ITEM_INVALID", "a location needs a party", "22023")}
  end if;
  if import_party_location.subject_id is not null then
    select x.${lo("id")}, x.${lo("updatedAt")}, ${fields.same} into v_id, v_updated, v_same
    from ${t("locations")} x
    where x.${lo("id")} = import_party_location.subject_id::uuid and x.${lo("tenant")} = (import_party_location.item ->> 'tenant')::${ctx.idType};
    if v_id is not null and v_same then
      return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
    end if;
    update ${t("locations")} x set ${fields.sets}, ${lo("updatedAt")} = now()
    where x.${lo("id")} = import_party_location.subject_id::uuid
    returning x.${lo("id")}, x.${lo("updatedAt")} into v_id, v_updated;
  end if;
  if v_id is null then
    insert into ${t("locations")} (${lo("tenant")}, ${fields.cols})
    values ((import_party_location.item ->> 'tenant')::${ctx.idType}, ${fields.vals})
    returning ${lo("id")}, ${lo("updatedAt")} into v_id, v_updated;
  end if;
  return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
end;
$$;
${serviceGrant(`${fn("import_party_location")}(uuid, jsonb, text)`)}

create or replace function ${fn("party_location_updated_at")}(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x.${lo("updatedAt")} from ${t("locations")} x where x.${lo("id")}::text = party_location_updated_at.subject_id
$$;
${serviceGrant(`${fn("party_location_updated_at")}(text)`)}
`;
}

function bankTarget(ctx: BlockSqlContext, names: PartyNames): string {
  const { fn, t, c } = names;
  const ba = (column: string): string => c("bankAccounts", column);

  return `
create or replace function ${fn("import_party_bank_account")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_data jsonb := import_party_bank_account.item -> 'data';
  v_party uuid := nullif(coalesce(import_party_bank_account.item -> 'resolved' ->> 'party', v_data ->> 'partyId'), '')::uuid;
  v_iban text := upper(regexp_replace(coalesce(v_data ->> 'iban', ''), '\\s', '', 'g'));
  v_id uuid;
  v_updated timestamptz;
begin
  if v_party is null or not better_supabase.validate_iban(v_iban) then
    ${fail("IMPORT_ITEM_INVALID", "a bank account needs a party and a valid IBAN", "22023")}
  end if;
  select x.${ba("id")}, x.${ba("updatedAt")} into v_id, v_updated from ${t("bankAccounts")} x
  where x.${ba("tenant")} = (import_party_bank_account.item ->> 'tenant')::${ctx.idType} and x.${ba("iban")} = v_iban
    and x.${ba("bic")} is not distinct from nullif(upper(btrim(v_data ->> 'bic')), '')
    and x.${ba("holder")} is not distinct from nullif(btrim(v_data ->> 'holder'), '')
    and x.${ba("isPrimary")} is not distinct from coalesce((v_data ->> 'isPrimary')::boolean, x.${ba("isPrimary")});
  if v_id is not null then
    return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
  end if;
  insert into ${t("bankAccounts")} (${ba("tenant")}, ${ba("party")}, ${ba("iban")}, ${ba("bic")}, ${ba("holder")}, ${ba("isPrimary")})
  values ((import_party_bank_account.item ->> 'tenant')::${ctx.idType}, v_party, v_iban,
    nullif(upper(btrim(v_data ->> 'bic')), ''), nullif(btrim(v_data ->> 'holder'), ''), coalesce((v_data ->> 'isPrimary')::boolean, false))
  on conflict (${ba("tenant")}, ${ba("iban")}) do update
    set ${ba("bic")} = excluded.${ba("bic")}, ${ba("holder")} = excluded.${ba("holder")},
      ${ba("isPrimary")} = coalesce((v_data ->> 'isPrimary')::boolean, ${t("bankAccounts")}.${ba("isPrimary")}),
      ${ba("updatedAt")} = now()
  returning ${ba("id")}, ${ba("updatedAt")} into v_id, v_updated;
  return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
end;
$$;
${serviceGrant(`${fn("import_party_bank_account")}(uuid, jsonb, text)`)}

create or replace function ${fn("party_bank_account_updated_at")}(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x.${ba("updatedAt")} from ${t("bankAccounts")} x where x.${ba("id")}::text = party_bank_account_updated_at.subject_id
$$;
${serviceGrant(`${fn("party_bank_account_updated_at")}(text)`)}

create or replace function ${fn("party_bank_account_id")}(tenant ${ctx.idType}, item jsonb)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select x.${ba("id")}::text from ${t("bankAccounts")} x
  where x.${ba("tenant")} = party_bank_account_id.tenant
    and x.${ba("iban")} = upper(regexp_replace(coalesce(party_bank_account_id.item -> 'data' ->> 'iban', ''), '\\s', '', 'g'))
$$;
${serviceGrant(`${fn("party_bank_account_id")}(${ctx.idType}, jsonb)`)}
`;
}

/** What `contributes.imports` adds for parties. */
export function partyImportTargets(
  own: BlockSqlContext,
): readonly ImportTargetContribution[] {
  if (own.mode === "custom") {
    return [];
  }

  const target = (
    entity: string,
    write: string,
    updatedAt: string,
    refs?: Readonly<Record<string, string>>,
    naturalKey?: string,
  ): ImportTargetContribution => ({
    entity,
    subjectType: entity,
    write: plain(own.fn(write)),
    updatedAt: plain(own.fn(updatedAt)),
    ...(refs === undefined ? {} : { refs }),
    ...(naturalKey === undefined
      ? {}
      : { naturalKey: plain(own.fn(naturalKey)) }),
  });

  return [
    target("party", "import_party", "party_updated_at", { billTo: "party" }),
    target(
      "party_contact",
      "import_party_contact",
      "party_contact_updated_at",
      { company: "party", person: "party" },
    ),
    target(
      "contact_method",
      "import_contact_method",
      "contact_method_updated_at",
      { party: "party" },
    ),
    target(
      "party_location",
      "import_party_location",
      "party_location_updated_at",
      { party: "party" },
    ),
    target(
      "party_bank_account",
      "import_party_bank_account",
      "party_bank_account_updated_at",
      { party: "party" },
      "party_bank_account_id",
    ),
  ];
}
