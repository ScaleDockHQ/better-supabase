import { describe, expect, it } from "vitest";

import { DEADLINES } from "../../../src/sql/modules/deadlines.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = ["memberships", "permissions", "deadlines"];

const sqlOf = (
  modules: readonly string[] = BASE,
  layout: Layout = {},
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "deadlines")
    .map((file) => file.contents)
    .join("\n");

describe("deadlines module", () => {
  it("renders the rule set, version and deadline tables and the frozen trigger", () => {
    const sql = sqlOf();

    expect(sql).toContain('"deadline_rule_sets"');
    expect(sql).toContain('"deadline_rule_versions"');
    expect(sql).toContain("DEADLINE_RULE_VERSION_FROZEN");
    expect(sql).toContain("'draft', 'approved'");
    expect(sql).toContain("'due', 'unknown'");
  });

  it("keeps the rule sets platform-wide and readable only when approved", () => {
    const sql = sqlOf();

    expect(sql).toMatch(/for select to authenticated\s+using \(true\)/);
    expect(sql).toContain(`"status" = 'approved'`);
  });

  it("asks for an approved request only when approvals is installed", () => {
    expect(sqlOf()).not.toContain("DEADLINE_APPROVAL_REQUIRED");
    expect(sqlOf([...BASE, "approvals"])).toContain(
      "DEADLINE_APPROVAL_REQUIRED",
    );
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { deadlines: { mode: "custom" } } };
    expect(sqlOf(BASE, custom).trim()).toBe("");
    const [contract] = customContracts(["deadlines"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining(["compute_deadline", "approve_rule_version"]),
    );
    expect(DEADLINES.name).toBe("deadlines");
  });
});
