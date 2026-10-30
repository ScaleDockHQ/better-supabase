import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { SHIFTS } from "../../../src/sql/modules/shifts.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = ["shifts"];

const ALL = [
  "attachments",
  "notifications",
  "employees",
  "leave",
  "assets",
  "approvals",
  "time-tracking",
  "qualifications",
  "shifts",
];

const sqlOf = (
  modules: readonly string[] = BASE,
  layout: Layout = {},
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "shifts")
    .map((file) => file.contents)
    .join("\n");

describe("shifts module", () => {
  it("refuses overlap with an exclusion constraint and in the assignment check", () => {
    const sql = sqlOf();
    expect(sql).toContain("create extension if not exists btree_gist");
    expect(sql).toContain('"shift_assignments_no_overlap" exclude using gist');
    expect(sql).toContain("SHIFT_ASSIGNMENT_OVERLAP");
    expect(sql).toContain("interval '11 hours'");
  });

  it("checks leave and qualifications only with those blocks installed", () => {
    const sql = sqlOf(ALL);
    expect(sql).toContain("SHIFT_ASSIGNMENT_ON_LEAVE");
    expect(sql).toContain("SHIFT_ASSIGNMENT_UNQUALIFIED");
    expect(sql).toContain("qualified_holders");

    const bare = sqlOf();
    expect(bare).not.toContain("SHIFT_ASSIGNMENT_ON_LEAVE");
    expect(bare).not.toContain("SHIFT_ASSIGNMENT_UNQUALIFIED");
  });

  it("links locations, approvals and time entries only with their blocks", () => {
    const sql = sqlOf(ALL);
    expect(sql).toMatch(
      /"location_id" uuid references "better_supabase"\."assets"/,
    );
    expect(sql).toMatch(
      /"approval_id" uuid references "better_supabase"\."approval_requests"/,
    );
    expect(sql).toContain("shifts_to_time_entries");

    const bare = sqlOf();
    expect(bare).not.toMatch(/"location_id" uuid references/);
    expect(bare).not.toMatch(/"approval_id" uuid references/);
    expect(bare).not.toContain("shifts_to_time_entries");

    const [contract] = customContracts(["shifts"], {
      modules: { shifts: { mode: "custom" } },
    });

    expect(contract?.functions.map((fn) => fn.name)).not.toContain(
      "shifts_to_time_entries",
    );
  });

  it("takes the rest time, qualification check and time zone from the options", () => {
    const sql = sqlOf(ALL, {
      modules: {
        shifts: {
          options: {
            minRestHours: 8,
            qualificationCheck: "warn",
            timeZone: "Europe/Amsterdam",
          },
        },
      },
    });

    expect(sql).toContain("interval '8 hours'");
    expect(sql).toContain("'Europe/Amsterdam'");

    expect(() =>
      sqlOf(BASE, { modules: { shifts: { options: { minRestHours: 72 } } } }),
    ).toThrow("blocks.shifts.options.minRestHours takes 0 to 48 hours");
    expect(() =>
      sqlOf(BASE, {
        modules: { shifts: { options: { qualificationCheck: "ignore" } } },
      }),
    ).toThrow("qualificationCheck takes block or warn");
    expect(() =>
      sqlOf(BASE, {
        modules: { shifts: { options: { timeZone: "Mars/Base" } } },
      }),
    ).toThrow('"Mars/Base" is not a time zone');
  });

  it("writes extra columns on shifts through save_shift", () => {
    const sql = sqlOf(BASE, {
      modules: { shifts: { options: { extraColumns: { site_code: "text" } } } },
    });

    expect(sql).toContain(
      `alter table "better_supabase"."shifts" add column if not exists "site_code" text;`,
    );
    expect(sql).toContain("shift_id uuid default null, fields jsonb");
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { shifts: { mode: "custom" } } };
    expect(sqlOf(BASE, custom).trim()).toBe("");
    // SAFETY: custom mode returns before reading anything else on the context.
    const context = { mode: "custom" } as unknown as BlockSqlContext;
    expect(SHIFTS.build(context, {})).toBe("");
    const [contract] = customContracts(["shifts"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining(["save_shift", "assign_shift", "roster"]),
    );
  });
});
