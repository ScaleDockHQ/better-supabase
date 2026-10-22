import { describe, expect, it } from "vitest";

import { renderModules } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderModules>[1];

const sqlOf = (modules: readonly string[], layout: Layout = {}): string =>
  renderModules(modules, layout)
    .filter((file) => file.module === "leases")
    .map((file) => file.contents)
    .join("\n");

describe("leases module", () => {
  it("posts rent on the ledger once per period, never in a balance of its own", () => {
    const sql = sqlOf(["leases"]);

    expect(sql).toContain(`unique ("lease_id", "period_start")`);
    expect(sql).toContain(
      `'lease:' || v_row."id"::text || ':rent:' || v_start::text`,
    );
    expect(sql).toContain("for update skip locked");
    expect(sql).not.toMatch(/\bbalance\s+bigint/);
  });

  it("holds the deposit through the ledger's hold core", () => {
    const sql = sqlOf(["leases"]);

    expect(sql).toContain('"ledger_hold"(');
    expect(sql).toContain('"ledger_capture"(');
    expect(sql).toContain('"ledger_release"(');
    expect(sql).toContain("'lease.deposit_refund'");
  });

  it("refuses overlapping active leases of one unit", () => {
    const sql = sqlOf(["leases"]);

    expect(sql).toContain("LEASE_OVERLAP");
    expect(sql).toContain("pg_advisory_xact_lock");
    expect(sql).toContain("daterange(");
  });

  it("needs the managed assets and ledger tables", () => {
    expect(() =>
      renderModules(["leases"], { modules: { ledger: { mode: "custom" } } }),
    ).toThrow(/ledger can't be in custom mode/);
    expect(() =>
      renderModules(["leases"], { modules: { assets: { mode: "custom" } } }),
    ).toThrow(/assets can't be in custom mode/);
  });

  it("indexes every foreign key", () => {
    const sql = sqlOf(["leases"]);

    expect(sql).toContain("leases_unit_idx");
    expect(sql).toContain("lease_charges_transaction_idx");
    expect(sql).toContain("maintenance_requests_lease_idx");
  });
});
