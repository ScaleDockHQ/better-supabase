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

async function run(modules: AnyBlocksConfig, check: string): Promise<void> {
  const files = renderBlocks(["banking"], { modules });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      ...files
        .filter((file) => file.kind === "schema")
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

const save = (input: string, id = "null"): string =>
  `better_supabase.upsert_bank_account('${TENANT}', '${input}', ${id})`;

describe("banking options", { timeout: 120_000 }, () => {
  it("keeps one primary account per organization and accounts without a currency", async () => {
    await expect(
      run(
        {
          banking: {
            options: { primary: "organization", optionalCurrency: true },
          },
        },
        `do $$
declare
  v_eur uuid;
  v_none uuid;
  v_usd uuid;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  v_eur := (${save('{"name": "Main", "currency": "EUR", "primary": true}')} ->> 'id')::uuid;
  v_none := (${save('{"name": "Cash box", "primary": true}')} ->> 'id')::uuid;
  if (select currency from better_supabase.bank_accounts where id = v_none) is not null then
    raise exception 'the account got a currency';
  end if;
  if (select is_primary from better_supabase.bank_accounts where id = v_eur) then
    raise exception 'a second primary account kept the first one primary';
  end if;
  v_usd := (${save('{"name": "Dollars", "currency": "USD", "primary": true}')} ->> 'id')::uuid;
  if (select count(*) from better_supabase.bank_accounts where is_primary) <> 1 then
    raise exception 'more than one primary account';
  end if;
  perform better_supabase.import_bank_statement(v_none, '{"format": "csv", "transactions": [{"bookedOn": "2099-03-02", "amount": "1250", "currency": "EUR"}]}');
  begin
    perform better_supabase.import_bank_statement(v_none, '{"format": "csv", "transactions": [{"bookedOn": "2099-03-03", "amount": "900"}]}');
    raise exception 'imported a transaction without a currency';
  exception when sqlstate '22023' then
    null;
  end;
end;
$$;`,
      ),
    ).resolves.toBeUndefined();
  });

  it("keeps the defaults: one primary per currency and a required currency", () => {
    const sql = renderBlocks(["banking"])
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toMatch(/"currency" char\(3\) not null/u);
    expect(sql).toMatch(/\("tenant_id", "currency"\) where "is_primary"/u);
  });

  it("refuses an unknown primary scope", () => {
    expect(() =>
      renderBlocks(["banking"], {
        modules: { banking: { options: { primary: "team" } } },
      }),
    ).toThrow(/primary must be/u);
  });
});
