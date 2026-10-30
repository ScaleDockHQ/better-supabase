import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { CARE_PLANS } from "../../../src/sql/modules/care-plans.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = ["memberships", "permissions", "subjects", "care-plans"];

const sqlOf = (
  layout: Layout = {},
  modules: readonly string[] = BASE,
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "care-plans")
    .map((file) => file.contents)
    .join("\n");

describe("care-plans module", () => {
  it("snapshots published plans only with versions installed", () => {
    expect(sqlOf()).not.toContain("version_insert");
    expect(sqlOf({}, [...BASE, "versions"])).toContain("version_insert");
  });

  it("asks agreement through signatures only when it is installed", () => {
    expect(sqlOf()).toContain("agreement needs the signatures block");
    const signed = sqlOf({}, [...BASE, "versions", "signatures"]);
    expect(signed).toContain("meaning => 'agreed'");
    expect(signed).toContain("care_plans_signature_settled");
  });

  it("gates measures on approvals, or on the manage permission without it", () => {
    expect(sqlOf()).toContain("only a holder of the manage permission");
    const approved = sqlOf({}, [...BASE, "approvals"]);
    expect(approved).toContain("care_plan_action_request_approval");
    expect(approved).toContain("approval_effective_policy");
  });

  it("creates work items and notifies owners only with those blocks installed", () => {
    expect(sqlOf()).not.toContain("create_work_item");
    expect(sqlOf()).not.toContain("'care_plan.review_due:' ||");
    const full = sqlOf({}, [...BASE, "tasks", "notifications"]);
    expect(full).toContain("create_work_item");
    expect(full).toContain("'care_plan.review_due:' ||");
  });

  it("lets guests read published plans when guestRead is on", () => {
    const modules = [...BASE, "guests"];
    const drafts = (sql: string): number => sql.split("<> 'draft' and").length;
    const off = sqlOf({}, modules);

    const on = sqlOf(
      { modules: { "care-plans": { options: { guestRead: true } } } },
      modules,
    );

    expect(drafts(on)).toBeGreaterThan(drafts(off));
  });

  it("checks the code systems and measure kinds", () => {
    const sql = sqlOf({
      modules: {
        "care-plans": {
          options: {
            codeSystems: ["icd-10", "snomed"],
            measureKinds: ["sensor"],
          },
        },
      },
    });

    expect(sql).toContain("array['icd-10', 'snomed']::text[]");
    expect(sql).toContain("array['sensor']::text[]");

    expect(() =>
      sqlOf({ modules: { "care-plans": { options: { codeSystems: [] } } } }),
    ).toThrow(TypeError);
    expect(() =>
      sqlOf({
        modules: {
          "care-plans": { options: { measureKinds: ["Not A Name"] } },
        },
      }),
    ).toThrow(TypeError);
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { "care-plans": { mode: "custom" } } };
    expect(sqlOf(custom).trim()).toBe("");
    // SAFETY: custom mode returns before reading anything else on the context.
    const context = { mode: "custom" } as unknown as BlockSqlContext;
    expect(CARE_PLANS.build(context, {})).toBe("");
    const [contract] = customContracts(["care-plans"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining([
        "create_care_plan",
        "publish_care_plan",
        "record_care_plan_evaluation",
        "start_care_plan_action",
        "due_care_plan_reviews",
      ]),
    );
  });
});
