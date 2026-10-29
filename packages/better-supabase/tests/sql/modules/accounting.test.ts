import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { ACCOUNTING } from "../../../src/sql/modules/accounting.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = ["memberships", "permissions", "accounting"];

const sqlOf = (
  layout: Layout = {},
  modules: readonly string[] = BASE,
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "accounting")
    .map((file) => file.contents)
    .join("\n");

const withOptions = (options: Record<string, unknown>): Layout => ({
  modules: { accounting: { options } },
});

describe("accounting module", () => {
  it("seeds the generic chart, its roles and the default journals", () => {
    const sql = sqlOf();

    expect(sql).toContain("'1200', 'Accounts receivable'");
    expect(sql).toContain("('retained_earnings', ");
    expect(sql).toContain("then the generic chart");
    expect(sql).toContain("'EUR'");
  });

  it("seeds nothing with chart none and takes another functional currency", () => {
    const sql = sqlOf(
      withOptions({ chart: "none", functionalCurrency: "USD" }),
    );

    expect(sql).not.toContain("'1200', 'Accounts receivable'");
    expect(sql).toContain("'USD'");
  });

  it("refuses options it can't build", () => {
    expect(() => sqlOf(withOptions({ chart: "dutch" }))).toThrow(
      'blocks.accounting.options.chart must be "generic" or "none"',
    );
    expect(() => sqlOf(withOptions({ functionalCurrency: "euro" }))).toThrow(
      "must be an ISO 4217 code",
    );
    expect(() => sqlOf(withOptions({ fiscalYearStartMonth: 13 }))).toThrow(
      "must be a month from 1 to 12",
    );
    expect(() => sqlOf(withOptions({ subtypes: ["cash"] }))).toThrow(
      "must include the generic chart's",
    );
    expect(() =>
      sqlOf(withOptions({ chart: "none", subtypes: ["Not valid"] })),
    ).toThrow("must be lower-case identifiers");
  });

  it("keeps posting internal and the reports on the caller's rights", () => {
    const sql = sqlOf();

    expect(sql).toMatch(
      /revoke execute on function "better_supabase"\."accounting_post"\(uuid, boolean\) from public, anon, authenticated;/,
    );

    for (const report of [
      "accounting_trial_balance",
      "accounting_profit_and_loss",
      "accounting_balance_sheet",
      "accounting_general_ledger",
    ]) {
      const start = sql.indexOf(`function "better_supabase"."${report}"`);
      const body = sql.slice(start, sql.indexOf("$$;", start));

      expect(body).toContain("security invoker");
    }
  });

  it("numbers entries per journal and fiscal year under a lock", () => {
    const sql = sqlOf();

    expect(sql).toContain("pg_advisory_xact_lock");
    expect(sql).toContain("FISCAL_YEAR_CLOSED");
    expect(sql).toContain("ACCOUNTING_ENTRY_UNBALANCED");
  });

  it("adds extra entry columns", () => {
    const sql = sqlOf(
      withOptions({ extraColumns: { channel: "text not null default 'web'" } }),
    );

    expect(sql).toContain("\"channel\" text not null default 'web'");
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { accounting: { mode: "custom" } } };
    expect(sqlOf(custom).trim()).toBe("");
    // SAFETY: custom mode returns before reading anything else on the context.
    const context = { mode: "custom" } as unknown as BlockSqlContext;
    expect(ACCOUNTING.build(context, {})).toBe("");
    const [contract] = customContracts(["accounting"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining([
        "setup_accounting",
        "save_accounting_entry",
        "post_accounting_entry",
        "close_fiscal_year",
        "accounting_trial_balance",
      ]),
    );
  });
});
