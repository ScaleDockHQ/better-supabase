import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// The app's own CRM tables: renamed columns, enum lifecycles, a link table
// without a unique (account, contact) pair, and no VAT id, owner, address,
// creator or role columns.
const APP = `
create type public.account_stage as enum ('lead', 'prospect', 'customer', 'churned');

create table public.accounts (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  title text not null,
  web_domain text,
  website text,
  stage public.account_stage not null default 'lead',
  merged_into uuid references public.accounts (id),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  notes text
);

create table public.contacts (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  full_name text not null,
  email text,
  phone text,
  job_title text,
  stage public.account_stage not null default 'lead',
  owner_id uuid,
  user_id uuid,
  merged_into uuid references public.contacts (id),
  archived_at timestamptz,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.account_contacts (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  account_id uuid not null references public.accounts (id) on delete cascade,
  contact_id uuid not null references public.contacts (id) on delete cascade,
  is_primary boolean not null default false,
  created_at timestamptz not null default now()
);
`;

const OWN_TABLES = {
  "public.accounts": "app.sql",
  "public.contacts": "app.sql",
  "public.account_contacts": "app.sql",
};

const BLOCKS: AnyBlocksConfig = {
  contacts: {
    tables: {
      companies: "public.accounts",
      people: "public.contacts",
      links: "public.account_contacts",
    },
    columns: {
      companies: {
        tenant: "org_id",
        name: "title",
        domain: "web_domain",
        lifecycle: "stage",
        vatId: null,
        owner: null,
        address: null,
        createdBy: null,
      },
      people: {
        tenant: "org_id",
        name: "full_name",
        title: "job_title",
        lifecycle: "stage",
        owner: "owner_id",
      },
      links: {
        tenant: "org_id",
        company: "account_id",
        person: "contact_id",
        role: null,
      },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["memberships", "permissions", "contacts"], {
    modules: BLOCKS,
    ownTables: OWN_TABLES,
  });

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
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("contacts over the app's tables", BOOT, () => {
  it("saves companies and people in enum lifecycle columns and links them", async () => {
    await expect(
      run(`do $$
declare
  v_company jsonb;
  v_person jsonb;
  v_company_id uuid;
  v_person_id uuid;
  v_people jsonb;
begin
  ${SERVICE}
  v_company := better_supabase.save_company('${TENANT}', null, '{"name": "Acme", "domain": "ACME.test", "lifecycle": "prospect"}'::jsonb);
  v_company_id := (v_company ->> 'id')::uuid;
  if v_company ->> 'stage' <> 'prospect' or v_company ->> 'web_domain' <> 'acme.test' then
    raise exception 'created %', v_company;
  end if;
  v_company := better_supabase.save_company('${TENANT}', v_company_id, '{"lifecycle": "customer", "website": "https://acme.test"}'::jsonb);
  if (select stage from public.accounts where id = v_company_id) <> 'customer' then
    raise exception 'updated %', v_company;
  end if;
  v_person := better_supabase.save_person('${TENANT}', null, '{"name": "Ada", "email": "ada@acme.test", "title": "CTO"}'::jsonb);
  v_person_id := (v_person ->> 'id')::uuid;
  if v_person ->> 'stage' <> 'lead' or v_person ->> 'job_title' <> 'CTO' then
    raise exception 'person %', v_person;
  end if;
  perform better_supabase.set_company_person(v_company_id, v_person_id, null, false);
  perform better_supabase.set_company_person(v_company_id, v_person_id, null, true);
  v_people := better_supabase.company_people_of(v_company_id);
  if jsonb_array_length(v_people) <> 1 or (v_people -> 0 ->> 'is_primary')::boolean is not true then
    raise exception 'company_people_of %', v_people;
  end if;
  if jsonb_array_length(better_supabase.list_companies('${TENANT}', 'acme', 'customer', null, null, null, 50)) <> 1 then
    raise exception 'list_companies missed the company';
  end if;
  if jsonb_array_length(better_supabase.list_companies('${TENANT}', null, 'lead', null, null, null, 50)) <> 0 then
    raise exception 'list_companies matched another stage';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses a field the app's table has no column for", async () => {
    await expect(
      run(`do $$
begin
  ${SERVICE}
  perform better_supabase.save_company('${TENANT}', null, '{"name": "Acme", "vatId": "NL1"}'::jsonb);
end;
$$;`),
    ).rejects.toThrow(/has no vatId column/);
  });
});
