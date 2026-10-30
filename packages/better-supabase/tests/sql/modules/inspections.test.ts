import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { INSPECTIONS } from "../../../src/sql/modules/inspections.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = ["memberships", "permissions", "subjects", "forms", "inspections"];

const WITH_CASES = [...BASE.slice(0, -1), "pipelines", "cases", "inspections"];

const sqlOf = (
  layout: Layout = {},
  modules: readonly string[] = BASE,
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "inspections")
    .map((file) => file.contents)
    .join("\n");

const withOptions = (options: Record<string, unknown>): Layout => ({
  modules: { inspections: { options } },
});

describe("inspections module", () => {
  it("raises cases only with the cases block installed", () => {
    expect(sqlOf()).toContain("INSPECTION_CASES_NOT_INSTALLED");
    const sql = sqlOf({}, WITH_CASES);
    expect(sql).not.toContain("INSPECTION_CASES_NOT_INSTALLED");
    expect(sql).toContain("open_case_as");
    expect(sql).toContain("'source', 'inspection'");
    expect(sql).toMatch(/"case_id" uuid references .*"cases"/);
  });

  it("falls back to the internal source when the cases block doesn't take inspection", () => {
    const sql = sqlOf(
      {
        modules: { cases: { options: { sources: ["internal", "customer"] } } },
      },
      WITH_CASES,
    );

    expect(sql).toContain("'source', 'internal'");
    expect(
      sqlOf(
        { modules: { cases: { options: { sources: ["customer"] } } } },
        WITH_CASES,
      ),
    ).toContain("'source', 'customer'");
  });

  it("links controls through relations and checks them with compliance installed", () => {
    expect(sqlOf()).toContain("controlId needs the compliance block");
    expect(sqlOf()).not.toContain("'assesses'");

    const sql = sqlOf({}, [
      ...BASE.slice(0, -1),
      "relations",
      "compliance",
      "inspections",
    ]);

    expect(sql).toContain("'assesses'");
    expect(sql).toContain("the control is not a control of this organization");
  });

  it("checks the kinds and finding types from the options", () => {
    const sql = sqlOf(
      withOptions({
        kinds: ["site_walk"],
        findingTypes: ["defect", "remark"],
        caseFindingTypes: ["defect"],
      }),
    );

    expect(sql).toContain("array['site_walk']::text[]");
    expect(sql).toContain("array['defect', 'remark']::text[]");
    expect(sql).not.toContain("'internal_audit'");

    expect(() => sqlOf(withOptions({ kinds: [] }))).toThrow("at least one");
    expect(() => sqlOf(withOptions({ kinds: ["Audit"] }))).toThrow("lowercase");
    expect(() => sqlOf(withOptions({ findingTypes: ["a", "a"] }))).toThrow(
      "twice",
    );
    expect(() =>
      sqlOf(withOptions({ caseFindingTypes: ["major_finding"] })),
    ).toThrow("caseFindingTypes");
  });

  it("leaves out the optional columns a layout turns off", () => {
    const sql = sqlOf({
      modules: {
        inspections: {
          columns: {
            inspections: { scope: null, summary: null, createdBy: null },
            findings: { clause: null, evidence: null },
            programs: { notes: null },
          },
        },
      },
    });

    expect(sql).not.toContain('"scope" text');
    expect(sql).toContain("the inspections table has no scope column");
    expect(sql).toContain("the inspections table has no summary column");
    expect(sql).toContain("the findings table has no clause column");
    expect(sql).not.toContain('"notes" text');
  });

  it("refuses forms in custom mode", () => {
    expect(() => sqlOf({ modules: { forms: { mode: "custom" } } })).toThrow(
      "forms can't be in custom mode",
    );
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { inspections: { mode: "custom" } } };
    expect(sqlOf(custom).trim()).toBe("");
    // SAFETY: custom mode returns before reading anything else on the context.
    const context = { mode: "custom" } as unknown as BlockSqlContext;
    expect(INSPECTIONS.build(context, {})).toBe("");
    const [contract] = customContracts(["inspections"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining([
        "schedule_inspection",
        "start_inspection",
        "close_inspection",
        "add_inspection_finding",
        "raise_inspection_finding_case",
      ]),
    );
  });
});
