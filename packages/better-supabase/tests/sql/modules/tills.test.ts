import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { TILLS } from "../../../src/sql/modules/tills.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = ["memberships", "permissions", "subjects", "tills"];

const sqlOf = (
  modules: readonly string[] = BASE,
  layout: Layout = {},
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "tills")
    .map((file) => file.contents)
    .join("\n");

describe("tills module", () => {
  it("renders the tables and the checks", () => {
    const sql = sqlOf();

    expect(sql).toContain("till_sessions");
    expect(sql).toContain("till_movements");
    expect(sql).toContain("till_counts");
    expect(sql).toContain("till_deposits");
    expect(sql).toContain("'open', 'closed'");
    expect(sql).toContain("'cash_sale', 'cash_refund', 'cash_in', 'cash_out'");
    expect(sql).toContain("'pending', 'reconciled'");
  });

  it("allows one open session per till", () => {
    expect(sqlOf()).toMatch(/\("till_id"\) where "status" = 'open'/);
  });

  it("books nothing without the accounting block", () => {
    const sql = sqlOf();

    expect(sql).not.toContain("accounting_post_source");
    expect(sql).not.toContain("accounting_till_count_lines");
  });

  it("books count differences and deposits when accounting is installed", () => {
    const sql = sqlOf([...BASE, "accounting"]);

    expect(sql).toContain("accounting_till_count_lines");
    expect(sql).toContain("accounting_till_deposit_lines");
    expect(sql).toContain("accounting_post_source");
  });

  it("matches deposits through banking only when it is installed", () => {
    expect(sqlOf()).toContain("needs the banking and accounting blocks");
    expect(sqlOf([...BASE, "accounting", "banking"])).toContain(
      "match_bank_transaction",
    );
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { tills: { mode: "custom" } } };
    expect(sqlOf(BASE, custom).trim()).toBe("");
    // SAFETY: custom mode returns before reading anything else on the context.
    const context = { mode: "custom" } as unknown as BlockSqlContext;
    expect(TILLS.build(context, {})).toBe("");
    const [contract] = customContracts(["tills"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining([
        "create_till",
        "open_till_session",
        "close_till_session",
        "deposit_till_cash",
        "reconcile_till_deposit",
      ]),
    );
  });
});
