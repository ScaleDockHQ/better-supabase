import { describe, expect, it } from "vitest";

import {
  accountingSeeds,
  NL_RGS_CHART,
} from "../../../src/sql/modules/accounting-seeds.ts";
import {
  ACCOUNT_ROLES,
  GENERIC_CHART,
} from "../../../src/sql/modules/accounting-shared.ts";
import { renderBlocks } from "../../../src/sql/render.ts";

const sqlOf = (options: Record<string, unknown> = {}): string =>
  renderBlocks(["memberships", "permissions", "accounting"], {
    modules: { accounting: { options } },
  })
    .filter((file) => file.module === "accounting")
    .map((file) => file.contents)
    .join("\n");

const seedFunction = (sql: string): string => {
  const start = sql.search(
    /create or replace function [^\n]*"seed_accounting_defaults"\(/,
  );

  return sql.slice(start, sql.indexOf("\n$$;", start));
};

describe("accounting seeds", () => {
  it("lists the chart variants", () => {
    expect(accountingSeeds.variants).toEqual(["generic", "nl-rgs"]);
  });

  it("gives every account role an account in each chart", () => {
    for (const chart of [GENERIC_CHART, NL_RGS_CHART]) {
      expect(chart.flatMap((account) => account.role ?? []).toSorted()).toEqual(
        [...ACCOUNT_ROLES].toSorted(),
      );
    }
  });

  it("seeds the generic chart by default and for variant generic", () => {
    const body = seedFunction(sqlOf());

    expect(body).toContain(
      "if (p_variant is null or p_variant = 'generic') then",
    );
    expect(body).toContain("'Accounts receivable'");
  });

  it("seeds the Dutch chart only for variant nl-rgs", () => {
    const body = seedFunction(sqlOf());

    expect(body).toContain("if p_variant is not distinct from 'nl-rgs' then");
    expect(body).toContain("'Debiteuren'");
    expect(body).toContain("'Memoriaal'");
  });

  it("keeps the dimensions for every variant", () => {
    const body = seedFunction(sqlOf());

    expect(body).toContain("'cost_center', 'Cost center'");
  });

  it("declares only the dimensions with chart none", () => {
    const body = seedFunction(sqlOf({ chart: "none" }));

    expect(body).toContain("'cost_object'");
    expect(body).not.toContain("Accounts receivable");
    expect(body).not.toContain("Debiteuren");
  });

  it("references accounts of the same organization only", () => {
    const body = seedFunction(sqlOf());

    expect(body).toMatch(
      /select x\."id" from "better_supabase"\."accounting_accounts" x where x\."tenant_id" = p_tenant and x\."code" = '1100'/,
    );
  });

  it("keeps setup_accounting as a wrapper that seeds an empty chart once", () => {
    const sql = sqlOf();

    expect(sql).toContain("create or replace function");
    expect(sql).toMatch(
      /if not exists \(select 1 from "better_supabase"\."accounting_accounts" y where y\."tenant_id" = setup_accounting\.tenant\) then\n\s+perform "better_supabase"\."seed_accounting_defaults"\(setup_accounting\.tenant, 'generic'\);/,
    );
    expect(sqlOf({ chart: "none" })).not.toContain(
      'perform "better_supabase"."seed_accounting_defaults"',
    );
  });
});
