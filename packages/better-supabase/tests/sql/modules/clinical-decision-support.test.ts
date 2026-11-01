import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { CLINICAL_DECISION_SUPPORT } from "../../../src/sql/modules/clinical-decision-support.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = [
  "memberships",
  "permissions",
  "subjects",
  "medications",
  "clinical-decision-support",
];

const sqlOf = (
  modules: readonly string[] = BASE,
  layout: Layout = {},
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "clinical-decision-support")
    .map((file) => file.contents)
    .join("\n");

describe("clinical-decision-support module", () => {
  it("renders the tables and the checks", () => {
    const sql = sqlOf();

    expect(sql).toContain("care_rules");
    expect(sql).toContain("care_alerts");
    expect(sql).toContain("'dose_range', 'duplicate_therapy', 'interaction'");
    expect(sql).toContain("'info', 'warning', 'critical'");
    expect(sql).toContain("'open', 'acknowledged', 'overridden', 'resolved'");
  });

  it("deduplicates live alerts by fingerprint", () => {
    expect(sqlOf()).toMatch(/fingerprint/);
  });

  it("keeps the sync function away from every role", () => {
    expect(sqlOf()).toMatch(/revoke execute on function .*sync_care_alerts/i);
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = {
      modules: { "clinical-decision-support": { mode: "custom" } },
    };

    expect(sqlOf(BASE, custom).trim()).toBe("");
    // SAFETY: custom mode returns before reading anything else on the context.
    const context = { mode: "custom" } as unknown as BlockSqlContext;
    expect(CLINICAL_DECISION_SUPPORT.build(context, {})).toBe("");
    const [contract] = customContracts(["clinical-decision-support"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining([
        "save_care_rule",
        "evaluate_care_rules",
        "decide_care_alert",
      ]),
    );
  });
});
