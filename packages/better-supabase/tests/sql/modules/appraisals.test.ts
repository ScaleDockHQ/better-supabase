import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { APPRAISALS } from "../../../src/sql/modules/appraisals.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = ["memberships", "permissions", "subjects", "appraisals"];

const sqlOf = (blocks: readonly string[] = BASE, layout: Layout = {}): string =>
  renderBlocks(blocks, layout)
    .filter((file) => file.module === "appraisals")
    .map((file) => file.contents)
    .join("\n");

describe("appraisals module", () => {
  it("renders the tables and the review kinds", () => {
    const sql = sqlOf();

    expect(sql).toContain("appraisal_cycles");
    expect(sql).toContain("appraisal_reviews");
    expect(sql).toContain("appraisal_calibrations");
    expect(sql).toContain("appraisal_goals");
    expect(sql).toContain("'self', 'peer', 'manager'");
  });

  it("signs off directly without approvals and enrollments", () => {
    const sql = sqlOf();

    expect(sql).not.toContain("open_approval");
    expect(sql).not.toContain("appraisal_step");
    expect(sql).toContain("sign_off_appraisal");
  });

  it("files the sign-off with approvals and follows a program with enrollments", () => {
    const sql = sqlOf([
      "memberships",
      "permissions",
      "subjects",
      "approvals",
      "enrollments",
      "appraisals",
    ]);

    expect(sql).toContain("open_approval");
    expect(sql).toContain("appraisal_approved");
    expect(sql).toContain("appraisal_rejected");
    expect(sql).toContain("enrollment_ensure");
    expect(sql).toContain("enrollment_mark");
  });

  it("keeps a calibration's reason", () => {
    expect(sqlOf()).toContain("a calibration needs a reason");
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { appraisals: { mode: "custom" } } };
    expect(sqlOf(BASE, custom).trim()).toBe("");
    // SAFETY: custom mode returns before reading anything else on the context.
    const context = { mode: "custom" } as unknown as BlockSqlContext;
    expect(APPRAISALS.build(context, {})).toBe("");
    const [contract] = customContracts(["appraisals"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining([
        "create_appraisal_cycle",
        "submit_appraisal_review",
        "calibrate_appraisal",
        "sign_off_appraisal",
      ]),
    );
  });
});
