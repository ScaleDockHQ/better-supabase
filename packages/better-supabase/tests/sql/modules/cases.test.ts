import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import {
  caseKindProblem,
  DEFAULT_CASE_KINDS,
} from "../../../src/sql/modules/cases-sql.ts";
import { CASES } from "../../../src/sql/modules/cases.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = ["memberships", "permissions", "subjects", "pipelines", "cases"];

const sqlOf = (
  layout: Layout = {},
  modules: readonly string[] = BASE,
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "cases")
    .map((file) => file.contents)
    .join("\n");

const withOptions = (options: Record<string, unknown>): Layout => ({
  modules: { cases: { options } },
});

describe("cases module", () => {
  it("creates actions as work items only with tasks installed", () => {
    expect(sqlOf()).toContain("CASE_TASKS_NOT_INSTALLED");
    expect(sqlOf({}, [...BASE, "tasks"])).not.toContain(
      "CASE_TASKS_NOT_INSTALLED",
    );
  });

  it("opens cases from submissions only with forms installed", () => {
    expect(sqlOf()).toContain("CASE_FORMS_NOT_INSTALLED");
    expect(sqlOf({}, [...BASE, "forms"])).not.toContain(
      "CASE_FORMS_NOT_INSTALLED",
    );
  });

  it("notifies the owner of a due effectiveness check only with notifications installed", () => {
    expect(sqlOf()).not.toContain("'case.effectiveness_date_reached:' ||");
    expect(sqlOf({}, [...BASE, "notifications"])).toContain(
      "'case.effectiveness_date_reached:' ||",
    );
  });

  it("seeds the kinds, severities and sources from the options", () => {
    const sql = sqlOf(
      withOptions({
        severities: ["minor", "major"],
        sources: ["audit"],
        kinds: [{ key: "audit_nc", name: "Audit finding", prefix: "ANC" }],
        intakeKind: "audit_nc",
      }),
    );

    expect(sql).toContain("array['minor', 'major']::text[]");
    expect(sql).toContain("array['audit']::text[]");
    expect(sql).toContain("'Audit finding'");
    expect(sql).not.toContain("'Nonconformity'");
  });

  it("leaves out the optional columns a layout turns off", () => {
    const sql = sqlOf(
      {
        modules: {
          cases: {
            columns: {
              cases: {
                description: null,
                reporterContact: null,
                createdBy: null,
              },
            },
          },
        },
      },
      [...BASE, "forms"],
    );

    expect(sql).not.toContain('"reporter_contact"');
    expect(sql).toContain(" - 'reporterContact'");
    expect(sql).toContain("the cases table has no reporter_contact column");
  });

  it("seeds a kind's effectiveness delay and falls back to its first kind for intake", () => {
    const sql = sqlOf(
      withOptions({
        kinds: [
          {
            key: "audit_nc",
            name: "Audit finding",
            prefix: "ANC",
            effectivenessAfterDays: 30,
            requiresEffectiveness: true,
          },
        ],
      }),
      [...BASE, "forms"],
    );

    expect(sql).toContain("'ANC', 30, true, true, true, false)");
    expect(sql).toContain("'audit_nc'");
  });

  it("checks the kinds and the intake kind", () => {
    expect(DEFAULT_CASE_KINDS).toHaveLength(8);
    expect(
      DEFAULT_CASE_KINDS.map((kind) => caseKindProblem(kind)).filter(Boolean),
    ).toEqual([]);
    expect(caseKindProblem("kind")).toMatch(/object/);
    expect(caseKindProblem({ key: "x", name: "X", prefix: "x1" })).toMatch(
      /prefix/,
    );
    expect(
      caseKindProblem({
        key: "x",
        name: "X",
        prefix: "X",
        effectivenessAfterDays: 0,
      }),
    ).toMatch(/effectivenessAfterDays/);
    expect(
      caseKindProblem({ key: "x", name: "X", prefix: "X", requiresActions: 1 }),
    ).toMatch(/requiresActions/);

    expect(caseKindProblem({ key: "X", name: "X", prefix: "X" })).toMatch(
      /key/,
    );
    expect(caseKindProblem({ key: "x", name: " ", prefix: "X" })).toMatch(
      /name/,
    );
    expect(
      caseKindProblem({
        key: "x",
        name: "X",
        prefix: "X",
        effectivenessAfterDays: 400,
      }),
    ).toMatch(/effectivenessAfterDays/);

    expect(() => sqlOf(withOptions({ kinds: [] }))).toThrow("at least one");
    expect(() => sqlOf(withOptions({ kinds: "complaint" }))).toThrow(
      "at least one",
    );
    expect(() => sqlOf(withOptions({ kinds: [{ key: "x" }] }))).toThrow(
      "kinds[0]",
    );
    expect(() => sqlOf(withOptions({ severities: ["low", "low"] }))).toThrow(
      "twice",
    );
    expect(() =>
      sqlOf(
        withOptions({
          kinds: [
            { key: "a", name: "A", prefix: "A" },
            { key: "a", name: "B", prefix: "B" },
          ],
        }),
      ),
    ).toThrow("twice");
    expect(() => sqlOf(withOptions({ intakeKind: "spill" }))).toThrow(
      "intakeKind",
    );
    expect(() => sqlOf(withOptions({ severities: ["High"] }))).toThrow(
      "lowercase",
    );
    expect(() => sqlOf(withOptions({ sources: [] }))).toThrow("at least one");
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { cases: { mode: "custom" } } };
    expect(sqlOf(custom).trim()).toBe("");
    // SAFETY: custom mode returns before reading anything else on the context.
    const context = { mode: "custom" } as unknown as BlockSqlContext;
    expect(CASES.build(context, {})).toBe("");
    const [contract] = customContracts(["cases"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining([
        "open_case",
        "update_case",
        "close_case",
        "case_close_blockers",
        "notify_due_case_effectiveness",
      ]),
    );
  });
});
