import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { PAYROLL_EXPORT } from "../../../src/sql/modules/payroll-export.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = ["memberships", "permissions", "payroll-export"];

const sqlOf = (
  layout: Layout = {},
  modules: readonly string[] = BASE,
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "payroll-export")
    .map((file) => file.contents)
    .join("\n");

const withOptions = (options: Record<string, unknown>): Layout => ({
  modules: { "payroll-export": { options } },
});

describe("payroll-export module", () => {
  it("renders the tables, the lock on exported runs and the period guard", () => {
    const sql = sqlOf();

    expect(sql).toContain("payroll_runs");
    expect(sql).toContain("payroll_lines");
    expect(sql).toContain("PAYROLL_PERIOD_EXPORTED");
    expect(sql).toContain("PAYROLL_RUN_EXPORTED");
  });

  it("collects from the sources that are installed", () => {
    const none = sqlOf();

    const sql = sqlOf({}, [
      "memberships",
      "permissions",
      "time-tracking",
      "leave",
      "payroll-export",
    ]);

    expect(none).not.toContain("time_entries");
    expect(sql).toContain("time_entries");
    expect(sql).not.toContain("shift_assignments");
  });

  it("collects only the entries of weeks with an approved timesheet", () => {
    const sql = sqlOf({}, [
      "memberships",
      "permissions",
      "time-tracking",
      "payroll-export",
    ]);

    expect(sql).toContain(`"time_week_approved"(x."tenant_id", x."user_id"`);
  });

  it("collects scheduled shifts only when asked to", () => {
    const modules = [
      "memberships",
      "permissions",
      "time-tracking",
      "shifts",
      "payroll-export",
    ];

    expect(sqlOf({}, modules)).not.toContain("shift_assignments");
    expect(
      sqlOf(withOptions({ sources: ["time-tracking", "shifts"] }), modules),
    ).toContain("shift_assignments");
  });

  it("refuses a source that is not installed", () => {
    expect(() => sqlOf(withOptions({ sources: ["leave"] }))).toThrow(
      "isn't installed",
    );
    expect(() =>
      sqlOf(withOptions({ sources: ["payroll"] }), [...BASE, "time-tracking"]),
    ).toThrow("sources");
  });

  it("checks the time zone and the shape of the sources", () => {
    expect(() => sqlOf(withOptions({ timeZone: "" }))).toThrow("time zone");
    expect(() => sqlOf(withOptions({ timeZone: "Mars/Base" }))).toThrow(
      "not a time zone",
    );
    expect(() => sqlOf(withOptions({ sources: "leave" }))).toThrow(
      "list of strings",
    );
    expect(sqlOf(withOptions({ timeZone: "Europe/Amsterdam" }))).toContain(
      "payroll_runs",
    );
  });

  it("collects every source with the employees block installed", () => {
    const modules = [
      "memberships",
      "permissions",
      "employees",
      "time-tracking",
      "leave",
      "shifts",
      "payroll-export",
    ];

    const sql = sqlOf(
      withOptions({
        sources: ["time-tracking", "leave", "shifts"],
        timeZone: "Europe/Amsterdam",
      }),
      modules,
    );

    expect(sql).toContain("time_entries");
    expect(sql).toContain("shift_assignments");
    expect(sql).toContain("Europe/Amsterdam");

    const custom = sqlOf(
      {
        modules: {
          "time-tracking": { mode: "custom" },
          "payroll-export": { options: { sources: ["leave"] } },
        },
      },
      modules,
    );

    expect(custom).not.toContain("time_entries");
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = {
      modules: { "payroll-export": { mode: "custom" } },
    };

    expect(sqlOf(custom).trim()).toBe("");
    // SAFETY: custom mode returns before reading anything else on the context.
    const context = { mode: "custom" } as unknown as BlockSqlContext;
    expect(PAYROLL_EXPORT.build(context, {})).toBe("");
    const [contract] = customContracts(["payroll-export"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining([
        "create_payroll_run",
        "refresh_payroll_run",
        "mark_payroll_run_exported",
        "list_payroll_runs",
      ]),
    );
  });
});
