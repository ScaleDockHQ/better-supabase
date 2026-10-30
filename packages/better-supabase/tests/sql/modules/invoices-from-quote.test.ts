import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const MEMBER = "33333333-3333-4333-8333-333333333333";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

const PGCRYPTO = `
create schema if not exists extensions;
create or replace function extensions.gen_random_bytes(n integer) returns bytea
language sql volatile as $$
  select decode(substr(repeat(md5(random()::text), 8), 1, n * 2), 'hex')
$$;
create or replace function extensions.digest(data text, kind text) returns bytea
language sql immutable as $$
  select sha256(convert_to(data, 'UTF8'))
$$;
`;

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config('request.jwt.claim.sub', '', true);`;

const BOOT = { timeout: 60_000 };

const NAMES = ["quotes", "invoices"] as const;

async function run(
  check: string,
  modules: AnyBlocksConfig,
  setup = "",
): Promise<void> {
  const files = renderBlocks(NAMES, { modules });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      PGCRYPTO,
      ...files
        .filter((file) => file.kind !== "data")
        .map((file) => file.contents),
    ],
    seed: [
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      setup,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

const sqlOf = (modules: AnyBlocksConfig): string =>
  renderBlocks(NAMES, { modules })
    .filter((file) => file.module === "invoices")
    .map((file) => file.contents)
    .join("\n");

const OPT_IN = {
  depositAmount: "deposit_amount",
  discountBps: "discount_bps",
  discountAmount: "discount_amount",
};

// Both tables carry the same line and header columns of the app's.
const SHARED: AnyBlocksConfig = {
  quotes: {
    options: {
      extraColumns: { vat_regime: "text not null default 'standard'" },
      lineExtraColumns: { line_type: "text", unit: "text" },
    },
  },
  invoices: {
    columns: { invoices: OPT_IN },
    options: {
      extraColumns: { vat_regime: "text not null default 'standard'" },
      lineExtraColumns: { line_type: "text", unit: "text" },
    },
  },
};

const accepted = (
  attrs: string,
): string => `v_quote := (better_supabase.create_quote('${TENANT}', '${attrs}'::jsonb,
    '[{"description": "Work", "quantity": 2, "unitAmount": "5000", "taxRateBps": 2100, "fields": {"line_type": "labor", "unit": "hour"}}]'::jsonb) ->> 'id')::uuid;
  perform better_supabase.send_quote(v_quote);
  perform better_supabase.decide_quote(v_quote, 'accepted', null, 'Ann');`;

describe("invoices from quotes with the app's columns", BOOT, () => {
  it("keeps the document discount on the header and copies the line and header columns", async () => {
    await expect(
      run(
        `do $$
declare
  v_quote uuid;
  v_invoice jsonb;
begin
  ${SERVICE}
  ${accepted('{"title": "Work", "currency": "EUR", "discountBps": 1000, "fields": {"vat_regime": "reverse_charge"}}')}
  v_invoice := better_supabase.invoice_from_quote(v_quote, null);
  if (v_invoice ->> 'discount_bps')::integer <> 1000 or v_invoice ->> 'vat_regime' <> 'reverse_charge'
    or jsonb_array_length(v_invoice -> 'lines') <> 1
    or v_invoice -> 'lines' -> 0 -> 'fields' <> '{"line_type": "labor", "unit": "hour"}'::jsonb
    or (v_invoice ->> 'total')::bigint <> (select total from better_supabase.quotes where id = v_quote) then
    raise exception 'final %', v_invoice;
  end if;
end;
$$;`,
        SHARED,
      ),
    ).resolves.toBeUndefined();
  });

  it("makes a fixed deposit invoice and deducts it from the final one", async () => {
    await expect(
      run(
        `do $$
declare
  v_quote uuid;
  v_deposit jsonb;
  v_final jsonb;
begin
  ${SERVICE}
  ${accepted('{"title": "Work", "currency": "EUR"}')}
  v_deposit := better_supabase.invoice_from_quote(v_quote, null, 6050);
  if v_deposit ->> 'deposit_amount' <> '6050' or (v_deposit ->> 'total')::bigint <> 6050 then
    raise exception 'deposit %', v_deposit;
  end if;
  perform better_supabase.issue_invoice((v_deposit ->> 'id')::uuid, current_date);
  v_final := better_supabase.invoice_from_quote(v_quote, null);
  if (v_final ->> 'total')::bigint <> 12100 - 6050 or v_final ->> 'deposit_amount' is not null then
    raise exception 'final %', v_final;
  end if;
  if better_supabase.invoice_from_quote(v_quote, null) ->> 'id' <> v_final ->> 'id' then
    raise exception 'the final invoice is made once';
  end if;
end;
$$;`,
        SHARED,
      ),
    ).resolves.toBeUndefined();
  });

  it("deducts a deposit on the final invoice's tax basis and skips a credited one", async () => {
    await expect(
      run(
        `do $$
declare
  v_quote uuid;
  v_gross jsonb;
  v_credited jsonb;
  v_final jsonb;
begin
  ${SERVICE}
  ${accepted('{"title": "Work", "currency": "EUR"}')}
  v_gross := better_supabase.invoice_from_quote(v_quote, null, 6050);
  v_credited := better_supabase.invoice_from_quote(v_quote, null, 1210);
  update better_supabase.invoices set prices_include_tax = true where id = (v_gross ->> 'id')::uuid;
  perform better_supabase.issue_invoice((v_gross ->> 'id')::uuid, current_date);
  perform better_supabase.issue_invoice((v_credited ->> 'id')::uuid, current_date);
  update better_supabase.invoices set credited_total = total where id = (v_credited ->> 'id')::uuid;
  v_final := better_supabase.invoice_from_quote(v_quote, null);
  if (select string_agg(unit_amount::text || ':' || tax_rate_bps, ',' order by position)
      from better_supabase.invoice_lines where parent_id = (v_final ->> 'id')::uuid and unit_amount < 0)
    <> '-4132:2100' then
    raise exception 'deductions %', v_final;
  end if;
end;
$$;`,
        SHARED,
      ),
    ).resolves.toBeUndefined();
  });

  it("makes a new final invoice after the first is archived", async () => {
    await expect(
      run(
        `do $$
declare
  v_quote uuid;
  v_first jsonb;
  v_second jsonb;
begin
  ${SERVICE}
  ${accepted('{"title": "Work", "currency": "EUR"}')}
  v_first := better_supabase.invoice_from_quote(v_quote, null);
  update better_supabase.invoices set archived_at = now() where id = (v_first ->> 'id')::uuid;
  v_second := better_supabase.invoice_from_quote(v_quote, null);
  if v_second ->> 'id' = v_first ->> 'id' then
    raise exception 'archived invoice returned';
  end if;
  if better_supabase.invoice_from_quote(v_quote, null) ->> 'id' <> v_second ->> 'id' then
    raise exception 'the final invoice is made once';
  end if;
end;
$$;`,
        {
          ...SHARED,
          invoices: {
            ...SHARED["invoices"],
            columns: { invoices: { ...OPT_IN, archivedAt: "archived_at" } },
          },
        },
      ),
    ).resolves.toBeUndefined();
  });

  it("finds deposits by their kind and the quote link", async () => {
    await expect(
      run(
        `do $$
declare
  v_quote uuid;
  v_share jsonb;
  v_fixed jsonb;
  v_final jsonb;
begin
  ${SERVICE}
  alter table better_supabase.invoices drop constraint invoices_kind_check;
  alter table better_supabase.invoices add constraint invoices_kind_check check (kind in ('invoice', 'deposit', 'credit_note'));
  ${accepted('{"title": "Work", "currency": "EUR"}')}
  v_share := better_supabase.invoice_from_quote(v_quote, 2000);
  v_fixed := better_supabase.invoice_from_quote(v_quote, null, 1210);
  if (select string_agg(kind, ',') from better_supabase.invoices) <> 'deposit,deposit' or v_share ->> 'kind' <> 'invoice' then
    raise exception 'deposit kinds %', (select jsonb_agg(i) from better_supabase.invoices i);
  end if;
  perform better_supabase.issue_invoice((v_share ->> 'id')::uuid, current_date);
  perform better_supabase.issue_invoice((v_fixed ->> 'id')::uuid, current_date);
  v_final := better_supabase.invoice_from_quote(v_quote, null);
  if (v_final ->> 'total')::bigint <> 12100 - 2420 - 1210 or jsonb_array_length(v_final -> 'lines') <> 3
    or (select kind from better_supabase.invoices where id = (v_final ->> 'id')::uuid) <> 'invoice' then
    raise exception 'final %', v_final;
  end if;
end;
$$;`,
        {
          invoices: {
            columns: { invoices: { depositBps: null } },
            options: { depositKind: "deposit" },
            values: { invoices: { kind: { invoice: ["invoice", "deposit"] } } },
          },
        },
      ),
    ).resolves.toBeUndefined();
  });

  it("refuses a deposit amount over the total, or both a share and an amount", async () => {
    for (const call of ["(v_quote, null, 999999)", "(v_quote, 1000, 500)"]) {
      await expect(
        run(
          `do $$
declare
  v_quote uuid;
begin
  ${SERVICE}
  ${accepted('{"title": "Work", "currency": "EUR"}')}
  perform better_supabase.invoice_from_quote${call};
end;
$$;`,
          SHARED,
        ),
      ).rejects.toThrow(/at most the quote's total|a share \(deposit_bps\)/);
    }
  });

  it("refuses a fixed deposit without a column for it, and a member without the create key", async () => {
    await expect(
      run(
        `do $$
declare
  v_quote uuid;
begin
  ${SERVICE}
  ${accepted('{"title": "Work", "currency": "EUR"}')}
  perform better_supabase.invoice_from_quote(v_quote, null, 500);
end;
$$;`,
        {},
      ),
    ).rejects.toThrow(/no deposit amount column/);
    await expect(
      run(
        `do $$
declare
  v_quote uuid;
begin
  ${SERVICE}
  ${accepted('{"title": "Work", "currency": "EUR"}')}
  perform set_config('request.jwt.claims', '{"sub":"${MEMBER}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${MEMBER}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform better_supabase.invoice_from_quote(v_quote, null, 500);
end;
$$;`,
        SHARED,
        `create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select permission <> 'invoices.write' $$;`,
      ),
    ).rejects.toThrow(/no such quote you can invoice/);
  });

  it("keeps the discount lines and the deposit markers by default", () => {
    const sql = sqlOf({});
    expect(sql).toContain("'description', 'Discount'");
    expect(sql).toContain(`x."deposit_bps" is null and`);
    expect(sql).not.toContain("v_header");
    expect(sqlOf(SHARED)).toContain("v_header := jsonb_build_object(");
    expect(() =>
      sqlOf({ invoices: { options: { depositKind: "deposit" } } }),
    ).toThrow(/depositKind must be one of the values/);
  });
});
