import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// The app's own expense tables: renamed columns, and no limit, receipt
// threshold, note, ledger transaction or merchant columns.
const APP = `
create table public.spend_categories (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  code text not null,
  title text not null,
  currency text,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.claims (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  owner_id uuid not null,
  title text not null,
  currency text not null,
  approval_id uuid,
  submitted_at timestamptz,
  approved_at timestamptz,
  reimbursed_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.claim_items (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  claim_id uuid not null references public.claims (id) on delete cascade,
  category_id uuid not null references public.spend_categories (id),
  spent_on date not null,
  description text not null,
  amount bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
`;

const OWN_TABLES = {
  "public.spend_categories": "app.sql",
  "public.claims": "app.sql",
  "public.claim_items": "app.sql",
};

const BLOCKS: AnyBlocksConfig = {
  expenses: {
    tables: {
      categories: "public.spend_categories",
      reports: "public.claims",
      lines: "public.claim_items",
    },
    columns: {
      categories: {
        tenant: "org_id",
        key: "code",
        name: "title",
        limitAmount: null,
        receiptOver: null,
      },
      reports: {
        tenant: "org_id",
        user: "owner_id",
        note: null,
        approvalTransaction: null,
        reimbursement: null,
      },
      lines: { tenant: "org_id", report: "claim_id", merchant: null },
    },
  },
};

// Everyone may do everything in the tenant: these tests are about the tables.
const ALLOW = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.can_user(member uuid, scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid $$;
insert into auth.users (id) values ('${ALICE}');
insert into better_supabase.memberships (organization_id, user_id, role) values ('${TENANT}', '${ALICE}', 'owner');
`;

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

const AS_ALICE = `perform set_config('request.jwt.claims', '{"sub":"${ALICE}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${ALICE}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["expenses"], {
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
      ALLOW,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("expenses over the app's tables", BOOT, () => {
  it("files, submits, approves and reimburses a report", async () => {
    await expect(
      run(`do $$
declare
  v_category uuid;
  v_report jsonb;
  v_id uuid;
begin
  ${SERVICE}
  v_category := (better_supabase.save_expense_category('${TENANT}', 'travel', 'Travel', 'EUR') ->> 'id')::uuid;
  perform better_supabase.save_expense_category('${TENANT}', 'travel', 'Trips', 'EUR');
  if (select count(*) from public.spend_categories) <> 1 or (select title from public.spend_categories where id = v_category) <> 'Trips' then
    raise exception 'category upsert';
  end if;
  ${AS_ALICE}
  v_report := better_supabase.create_expense_report('${TENANT}', 'Conference', 'EUR');
  v_id := (v_report ->> 'id')::uuid;
  perform better_supabase.add_expense_line(v_id, v_category, '2099-01-10', 12500, 'Train');
  if jsonb_array_length(better_supabase.check_expense_report(v_id)) <> 0 then
    raise exception 'violations %', better_supabase.check_expense_report(v_id);
  end if;
  perform better_supabase.submit_expense_report(v_id);
  if (select submitted_at from public.claims where id = v_id) is null then
    raise exception 'not submitted';
  end if;
  perform better_supabase.approve_expense_report(v_id);
  ${SERVICE}
  v_report := better_supabase.reimburse_expense_report(v_id);
  if (select reimbursed_at from public.claims where id = v_id) is null then
    raise exception 'not reimbursed %', v_report;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses a spend limit the app's table has no column for", async () => {
    await expect(
      run(`do $$
begin
  ${SERVICE}
  perform better_supabase.save_expense_category('${TENANT}', 'travel', 'Travel', 'EUR', 50000);
end;
$$;`),
    ).rejects.toThrow(/no limit column/);
  });
});
