import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../src/sql/render.ts";
import { upgradePlan } from "../../src/sql/upgrade.ts";
import { liteStack } from "../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ACCOUNT = "22222222-2222-4222-8222-222222222222";
const TRANSACTION = "33333333-3333-4333-8333-333333333333";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// A version 1 database with a posted entry: the column is not there yet, and
// the row predates it.
const POSTED = `
set session_replication_role = replica;
insert into better_supabase.ledger_accounts (id, tenant_id, kind, code, name, unit)
values ('${ACCOUNT}', '${TENANT}', 'asset', 'cash', 'Cash', 'EUR');
insert into better_supabase.ledger_transactions (id, tenant_id, kind, effective_at)
values ('${TRANSACTION}', '${TENANT}', 'test.post', '2020-01-01T00:00:00Z');
insert into better_supabase.ledger_entries (tenant_id, transaction_id, account_id, amount, unit)
values ('${TENANT}', '${TRANSACTION}', '${ACCOUNT}', 100, 'EUR');
set session_replication_role = origin;
alter table better_supabase.ledger_entries drop column effective_at;
`;

const CHECK = `do $$
begin
  if (select effective_at from better_supabase.ledger_entries) is distinct from '2020-01-01T00:00:00Z'::timestamptz then
    raise exception 'the entry did not take its transaction''s effective_at: % of %, tx %', (select array_agg(effective_at) from better_supabase.ledger_entries), (select count(*) from better_supabase.ledger_entries), (select array_agg(effective_at) from better_supabase.ledger_transactions);
  end if;

  begin
    update better_supabase.ledger_entries set amount = 1;
    raise exception 'the append-only trigger is off after the upgrade';
  exception when sqlstate '55000' then
    null;
  end;
end;
$$;`;

describe("the ledger upgrade from version 1", { timeout: 60_000 }, () => {
  it("backfills effective_at on entries the append-only trigger guards", async () => {
    const files = renderBlocks(["ledger"], {});
    const [plan] = upgradePlan([{ module: "ledger", version: 1 }], {});

    const boot = async (): Promise<void> => {
      await using stack = await liteStack({
        driver: "pglite",
        migrations: [
          ROLES,
          ...files
            .filter((file) => file.kind === "schema")
            .map((file) => file.contents),
          POSTED,
          ...(plan?.steps ?? []).map((step) => step.sql),
          CHECK,
        ],
      });

      expect(stack.url).not.toBe("");
    };

    expect(plan?.steps.map((step) => step.from)).toEqual([1, 2]);
    await expect(boot()).resolves.toBeUndefined();
  });
});
