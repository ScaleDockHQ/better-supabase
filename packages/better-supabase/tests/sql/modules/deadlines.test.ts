import { describe, expect, it } from "vitest";

import { DEADLINES } from "../../../src/sql/modules/deadlines.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";
import { upgradePlan } from "../../../src/sql/upgrade.ts";

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
    expect(sql).toContain(
      "'due', 'unknown', 'pending', 'undated', 'not_covered', 'not_applicable', 'not_required', 'barred'",
    );
    expect(sql).toContain('"bsb_deadlines_subject_group_period_key"');
    expect(sql).not.toContain('"deadlines_subject_rule_key"');
  });

  it("keeps the version 1 functions as deprecated wrappers", () => {
    const sql = sqlOf();

    expect(sql).toContain("Deprecated since 0.56.0");
    expect(sql).toContain("'deprecated: use evaluate_deadlines'");
    expect(sql).toContain("'deprecated: use compute_deadlines'");
  });

  it("upgrades version 1 in one step that converts the rules and drops the renamed functions", () => {
    const [plan] = upgradePlan([{ module: "deadlines", version: 1 }]);

    expect(plan?.to).toBe(2);
    expect(plan?.steps.map((step) => step.from)).toEqual([1]);
    expect(plan?.steps[0]?.sql).toContain(
      "disable trigger bsb_deadlines_version_frozen",
    );
    expect(plan?.steps[0]?.sql).toContain("previous_content_hash");
    expect(plan?.steps[0]?.sql).toContain(
      'drop function if exists "better_supabase"."save_rule_version"(text, text, jsonb, date, text)',
    );
    expect(
      upgradePlan([{ module: "deadlines", version: 1 }], {
        modules: { deadlines: { mode: "custom" } },
      })[0]?.steps[0]?.sql ?? "",
    ).toBe("");
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
      expect.arrayContaining(["compute_deadlines", "approve_rule_version"]),
    );
    expect(DEADLINES.name).toBe("deadlines");
  });
});
