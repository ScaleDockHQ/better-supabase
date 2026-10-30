import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const CUSTOMER = "22222222-2222-4222-8222-222222222222";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// The app's own purposes and consents tables: renamed columns, an enum status
// and no description, scope, evidence or creator columns.
const APP = `
create type public.consent_state as enum ('granted', 'refused', 'withdrawn', 'expired');

create table public.customers (
  id uuid primary key,
  org_id uuid not null
);

create table public.privacy_purposes (
  id uuid primary key default gen_random_uuid(),
  org_id uuid,
  key text not null,
  title text not null,
  legal_basis text not null default 'consent',
  version text not null default '1',
  requires_signature boolean not null default false,
  valid_months integer,
  archived_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index privacy_purposes_key on public.privacy_purposes (org_id, key, version) nulls not distinct;

create table public.privacy_consents (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  purpose_id uuid not null references public.privacy_purposes (id),
  subject_type text not null,
  subject_id text not null,
  given_by text not null default 'self',
  given_by_contact_id uuid,
  given_by_user_id uuid,
  state public.consent_state not null,
  granted_at timestamptz not null default now(),
  valid_until timestamptz,
  withdrawn_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index privacy_consents_granted on public.privacy_consents (subject_type, subject_id, purpose_id) where state = 'granted';
`;

const OWN_TABLES = {
  "public.privacy_purposes": "app.sql",
  "public.privacy_consents": "app.sql",
};

const BLOCKS: AnyBlocksConfig = {
  consents: {
    tables: {
      purposes: "public.privacy_purposes",
      consents: "public.privacy_consents",
    },
    columns: {
      purposes: { tenant: "org_id", description: null, updatedAt: null },
      consents: {
        tenant: "org_id",
        status: "state",
        scope: null,
        withdrawnReason: null,
        signature: null,
        submission: null,
        attachment: null,
        createdBy: null,
      },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(
    ["memberships", "permissions", "subjects", "consents"],
    {
      modules: BLOCKS,
      ownTables: OWN_TABLES,
      subjects: {
        customer: {
          table: "public.customers",
          idType: "uuid",
          tenant: "org_id",
        },
      },
    },
  );

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      APP,
      ...files
        .filter((file) => file.kind !== "data")
        .map((file) => file.contents),
    ],
    seed: [
      `insert into public.customers values ('${CUSTOMER}', '${TENANT}');`,
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("consents over the app's tables", BOOT, () => {
  it("records, replaces, withdraws and expires decisions in an enum column", async () => {
    await expect(
      run(`do $$
declare
  v_purpose jsonb;
  v_consent jsonb;
  v_next jsonb;
begin
  ${SERVICE}
  v_purpose := better_supabase.save_consent_purpose('${TENANT}', 'marketing.email', 'Marketing email', valid_months => 12);
  if v_purpose ->> 'key' <> 'marketing.email' or v_purpose -> 'description' <> 'null'::jsonb then
    raise exception 'purpose %', v_purpose;
  end if;
  v_consent := better_supabase.record_consent('customer', '${CUSTOMER}', 'marketing.email', 'granted');
  if not (v_consent ->> 'active')::boolean or v_consent ->> 'validUntil' is null then
    raise exception 'granted %', v_consent;
  end if;
  if not better_supabase.consent_active('customer', '${CUSTOMER}', 'marketing.email') then
    raise exception 'not active';
  end if;
  v_next := better_supabase.record_consent('customer', '${CUSTOMER}', 'marketing.email', 'granted');
  if (select state from public.privacy_consents where id = (v_consent ->> 'id')::uuid) <> 'withdrawn' then
    raise exception 'the first grant stayed';
  end if;
  perform better_supabase.withdraw_consent((v_next ->> 'id')::uuid);
  if better_supabase.consent_active('customer', '${CUSTOMER}', 'marketing.email') then
    raise exception 'still active';
  end if;
  if jsonb_array_length(better_supabase.list_consents('customer', '${CUSTOMER}', true)) <> 2 then
    raise exception 'history %', better_supabase.list_consents('customer', '${CUSTOMER}', true);
  end if;
  v_next := better_supabase.record_consent('customer', '${CUSTOMER}', 'marketing.email', 'granted');
  update public.privacy_consents set valid_until = now() - interval '1 day' where id = (v_next ->> 'id')::uuid;
  if better_supabase.expire_consents() <> 1 then
    raise exception 'expire';
  end if;
  if (select state from public.privacy_consents where id = (v_next ->> 'id')::uuid) <> 'expired' then
    raise exception 'not expired';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses evidence the app's table has no column for", async () => {
    await expect(
      run(`do $$
begin
  ${SERVICE}
  perform better_supabase.save_consent_purpose('${TENANT}', 'terms', 'Terms');
  perform better_supabase.record_consent('customer', '${CUSTOMER}', 'terms', 'granted', evidence => '{"signatureId": "${TENANT}"}'::jsonb);
end;
$$;`),
    ).rejects.toThrow(/CONSENT_INVALID|signature/);
  });
});
