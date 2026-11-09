import type { BlockSqlContext } from "../context.ts";
import type { ImportTargetContribution } from "../contributions.ts";

import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { fail, serviceGrant } from "../shared.ts";
import { lockModuleTable } from "./over-app.ts";

const plain = (qualified: string): string => qualified.replaceAll('"', "");

/** Profile tables the organizations module registers. */
export const ORGANIZATION_PROFILE_TABLES = {
  profiles: {
    name: "organization_profiles",
    app: {},
    optionalTable: true,
    columns: {
      tenant: "tenant_id",
      vatId: "vat_id",
      registrationId: "registration_id",
      defaultRate: "default_rate",
      currency: "currency",
      updatedAt: "updated_at",
    },
  },
  paymentAccounts: {
    name: "organization_payment_accounts",
    app: {},
    optionalTable: true,
    columns: {
      id: "id",
      tenant: "tenant_id",
      iban: "iban",
      bic: "bic",
      holder: "holder",
      label: "label",
      isPrimary: "is_primary",
      updatedAt: "updated_at",
    },
  },
} as const;

/** The organization's own profile and the payment accounts it imports. */
export function organizationProfileSql(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom" || !ctx.hasTable("profiles")) {
    return "";
  }

  const profile = ctx.table("profiles");
  const accounts = ctx.table("paymentAccounts");
  const p = (column: string): string => ctx.col("profiles", column);
  const a = (column: string): string => ctx.col("paymentAccounts", column);
  const fn = (name: string): string => ctx.fn(name);

  return `
create table if not exists ${profile} (
  ${p("tenant")} ${ctx.idType} primary key,
  ${p("vatId")} text,
  ${p("registrationId")} text,
  ${p("defaultRate")} numeric,
  ${p("currency")} text,
  ${p("updatedAt")} timestamptz not null default now()
);
${lockModuleTable(ctx, "profiles", { read: true })}
${renderPolicy(
  makePolicy({
    table: profile,
    name: ctx.naming.rename("organization_profiles_read"),
    command: "select",
    roles: ["authenticated"],
    using: `${p("tenant")} in (select ${ctx.of("memberships").fn("member_organization_ids")}())`,
  }),
  { target: profile },
)}

create table if not exists ${accounts} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${ctx.idType} not null,
  ${a("iban")} text not null,
  ${a("bic")} text,
  ${a("holder")} text,
  ${a("label")} text,
  ${a("isPrimary")} boolean not null default false,
  ${a("updatedAt")} timestamptz not null default now(),
  unique (${a("tenant")}, ${a("iban")})
);
create unique index if not exists ${ctx.naming.rename("organization_payment_accounts_primary_idx")}
  on ${accounts} (${a("tenant")}) where ${a("isPrimary")};
${lockModuleTable(ctx, "paymentAccounts", { read: true })}
${renderPolicy(
  makePolicy({
    table: accounts,
    name: ctx.naming.rename("organization_payment_accounts_read"),
    command: "select",
    roles: ["authenticated"],
    using: `${a("tenant")} in (select ${ctx.of("memberships").fn("member_organization_ids")}())`,
  }),
  { target: accounts },
)}

-- The organization's VAT, registration, default rate, currency and payment
-- accounts. An IBAN matches on a repeat import. A missing value leaves the
-- stored one, and the stored primary account stays unless an account says
-- isPrimary. A VAT number that is only a country prefix is skipped.
create or replace function ${fn("import_organization_profile")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_data jsonb := import_organization_profile.item -> 'data';
  v_tenant ${ctx.idType} := (import_organization_profile.item ->> 'tenant')::${ctx.idType};
  v_vat text := nullif(upper(btrim(v_data ->> 'vatId')), '');
  v_warnings jsonb := '[]'::jsonb;
  v_account jsonb;
  v_iban text;
  v_primary boolean;
  v_id uuid;
  v_updated timestamptz;
begin
  if jsonb_typeof(v_data) is distinct from 'object' then
    ${fail("IMPORT_ITEM_INVALID", "an organization profile needs data", "22023")}
  end if;
  if v_vat ~ '^[A-Z]{2}$' then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_VAT_PREFIX', 'message', 'a VAT number that is only a country prefix was skipped'));
    v_vat := null;
  end if;
  insert into ${profile} (${p("tenant")}) values (v_tenant) on conflict (${p("tenant")}) do nothing;
  if exists (
    select 1 from ${profile} x
    where x.${p("tenant")} = v_tenant
      and (v_vat is null or x.${p("vatId")} is not distinct from v_vat)
      and (v_data ->> 'registrationId' is null or x.${p("registrationId")} is not distinct from nullif(btrim(v_data ->> 'registrationId'), ''))
      and (v_data ->> 'defaultRate' is null or x.${p("defaultRate")} is not distinct from (v_data ->> 'defaultRate')::numeric)
      and (v_data ->> 'currency' is null or x.${p("currency")} is not distinct from nullif(btrim(v_data ->> 'currency'), ''))
  ) then
    v_updated := (select x.${p("updatedAt")} from ${profile} x where x.${p("tenant")} = v_tenant);
  else
    update ${profile} x set
      ${p("vatId")} = coalesce(v_vat, x.${p("vatId")}),
      ${p("registrationId")} = coalesce(nullif(btrim(v_data ->> 'registrationId'), ''), x.${p("registrationId")}),
      ${p("defaultRate")} = coalesce((v_data ->> 'defaultRate')::numeric, x.${p("defaultRate")}),
      ${p("currency")} = coalesce(nullif(btrim(v_data ->> 'currency'), ''), x.${p("currency")}),
      ${p("updatedAt")} = now()
    where x.${p("tenant")} = v_tenant
    returning x.${p("updatedAt")} into v_updated;
  end if;
  if jsonb_typeof(v_data -> 'accounts') = 'array' then
    for v_account in select value from jsonb_array_elements(v_data -> 'accounts') loop
      v_iban := upper(regexp_replace(coalesce(v_account ->> 'iban', ''), '\\s', '', 'g'));
      if not better_supabase.validate_iban(v_iban) then
        ${fail("IMPORT_ITEM_INVALID", "a payment account needs a valid IBAN", "22023")}
      end if;
      v_primary := case when v_account ? 'isPrimary' then (v_account ->> 'isPrimary')::boolean else null end;
      select x.${a("id")} into v_id from ${accounts} x
      where x.${a("tenant")} = v_tenant and x.${a("iban")} = v_iban
        and x.${a("bic")} is not distinct from coalesce(nullif(upper(btrim(v_account ->> 'bic')), ''), x.${a("bic")})
        and x.${a("holder")} is not distinct from coalesce(nullif(btrim(v_account ->> 'holder'), ''), x.${a("holder")})
        and x.${a("label")} is not distinct from coalesce(nullif(btrim(v_account ->> 'label'), ''), x.${a("label")})
        and (v_primary is null or x.${a("isPrimary")} = v_primary);
      if v_id is null then
        if v_primary is true then
          update ${accounts} x set ${a("isPrimary")} = false where x.${a("tenant")} = v_tenant and x.${a("iban")} <> v_iban;
        end if;
        insert into ${accounts} (${a("tenant")}, ${a("iban")}, ${a("bic")}, ${a("holder")}, ${a("label")}, ${a("isPrimary")})
        values (v_tenant, v_iban, nullif(upper(btrim(v_account ->> 'bic')), ''), nullif(btrim(v_account ->> 'holder'), ''),
          nullif(btrim(v_account ->> 'label'), ''), coalesce(v_primary, false))
        on conflict (${a("tenant")}, ${a("iban")}) do update set
          ${a("bic")} = coalesce(excluded.${a("bic")}, ${accounts}.${a("bic")}),
          ${a("holder")} = coalesce(excluded.${a("holder")}, ${accounts}.${a("holder")}),
          ${a("label")} = coalesce(excluded.${a("label")}, ${accounts}.${a("label")}),
          ${a("isPrimary")} = case when v_primary is true then true else ${accounts}.${a("isPrimary")} end,
          ${a("updatedAt")} = now();
      end if;
    end loop;
  end if;
  return jsonb_build_object('subjectId', v_tenant, 'updatedAt', coalesce(v_updated, now()), 'warnings', v_warnings);
end;
$$;
${serviceGrant(`${fn("import_organization_profile")}(uuid, jsonb, text)`)}

create or replace function ${fn("organization_profile_updated_at")}(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x.${p("updatedAt")} from ${profile} x where x.${p("tenant")}::text = organization_profile_updated_at.subject_id
$$;
${serviceGrant(`${fn("organization_profile_updated_at")}(text)`)}
`;
}

/** The organization profile import target. */
export function organizationProfileTargets(
  own: BlockSqlContext,
): readonly ImportTargetContribution[] {
  if (own.mode === "custom") {
    return [];
  }

  return [
    {
      entity: "organization_profile",
      subjectType: "organization_profile",
      write: plain(own.fn("import_organization_profile")),
      updatedAt: plain(own.fn("organization_profile_updated_at")),
    },
  ];
}
