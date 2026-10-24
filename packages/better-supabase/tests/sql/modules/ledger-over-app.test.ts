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

// The app's own journal: renamed columns, an enum account kind, no memo
// column, and no balances or holds (the module keeps those).
const APP = `
create type public.account_kind as enum ('asset', 'liability', 'credit');

create table public.books (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  kind public.account_kind not null,
  code text not null,
  name text not null,
  unit text not null,
  created_at timestamptz not null default now()
);

create table public.journal (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  kind text not null,
  created_at timestamptz not null default now()
);

create table public.journal_lines (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  journal_id uuid not null references public.journal (id),
  book_id uuid not null references public.books (id),
  amount bigint not null,
  unit text not null,
  created_at timestamptz not null default now()
);
`;

const OWN_TABLES = {
  "public.books": "app.sql",
  "public.journal": "app.sql",
  "public.journal_lines": "app.sql",
};

const BLOCKS: AnyBlocksConfig = {
  ledger: {
    tables: {
      accounts: "public.books",
      transactions: "public.journal",
      entries: "public.journal_lines",
    },
    columns: {
      accounts: { tenant: "org_id" },
      transactions: { tenant: "org_id", memo: null },
      entries: {
        tenant: "org_id",
        transaction: "journal_id",
        account: "book_id",
      },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["ledger"], {
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

const OPEN = `declare
  v_cash uuid;
  v_credit uuid;
  v_tx jsonb;
begin
  ${SERVICE}
  v_cash := (better_supabase.open_ledger_account('${TENANT}', 'asset', 'cash', 'Cash', 'EUR', 0::smallint, null, null, null, true) ->> 'id')::uuid;
  v_credit := (better_supabase.open_ledger_account('${TENANT}', 'credit', 'credit:ann', 'Ann credit', 'EUR') ->> 'id')::uuid;
  v_tx := better_supabase.post_ledger_transaction('${TENANT}', 'credit.grant',
    jsonb_build_array(jsonb_build_object('account', v_cash, 'amount', '-500'), jsonb_build_object('account', v_credit, 'amount', '500')),
    null, null, 'a memo the table has no column for');`;

describe("ledger over the app's tables", BOOT, () => {
  it("opens accounts with an enum kind, posts, lists and reverses", async () => {
    await expect(
      run(`do $$
${OPEN}
  if v_tx -> 'memo' <> 'null'::jsonb or jsonb_array_length(v_tx -> 'entries') <> 2 then
    raise exception 'posted %', v_tx;
  end if;
  if (select kind from public.books where id = v_credit) <> 'credit' then
    raise exception 'kind is %', (select kind from public.books where id = v_credit);
  end if;
  if jsonb_array_length(better_supabase.list_ledger_accounts('${TENANT}', 'credit')) <> 1 then
    raise exception 'list_ledger_accounts %', better_supabase.list_ledger_accounts('${TENANT}', 'credit');
  end if;
  if better_supabase.ledger_account_for('${TENANT}', 'credit', 'credit:ann', 'Ann credit', 'EUR') <> v_credit then
    raise exception 'ledger_account_for opened a second account';
  end if;
  perform better_supabase.reverse_ledger_transaction((v_tx ->> 'id')::uuid);
  if (select sum(amount) from public.journal_lines where book_id = v_credit) <> 0 then
    raise exception 'the reversal missed';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("keeps the app's entries append-only", async () => {
    await expect(
      run(`do $$
${OPEN}
  update public.journal_lines set amount = amount * 2;
end;
$$;`),
    ).rejects.toThrow(/can't be changed or deleted/);
  });
});
