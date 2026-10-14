import { describe, expect, it } from "vitest";

import { customContracts, renderModules } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderModules>[1];

const sqlOf = (
  modules: readonly string[],
  layout: Layout = {},
  module = "time-tracking",
): string =>
  renderModules(modules, layout)
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

const BASE = ["approvals", "time-tracking"];

describe("time-tracking module", () => {
  it("keeps one running timer and no overlaps per member", () => {
    const sql = sqlOf(BASE);
    expect(sql).toContain(
      "create extension if not exists btree_gist with schema extensions;",
    );
    expect(sql).toContain(`exclude using gist (`);
    expect(sql).toContain(
      `tstzrange("started_at", coalesce("ended_at", 'infinity'::timestamptz)) with &&`,
    );
    expect(sql).toContain(`where "ended_at" is null;`);
    expect(sql).toContain("TIME_ENTRY_OVERLAP");
  });

  it("locks submitted and approved weeks with a trigger", () => {
    const sql = sqlOf(BASE);
    expect(sql).toContain("before insert or update or delete on");
    expect(sql).toContain("TIME_PERIOD_LOCKED");
    expect(sql).toContain(`"better_supabase"."open_approval"(`);
    expect(sql).toContain(
      `revoke execute on function "better_supabase"."approve_timesheet"(uuid) from public, anon, authenticated;`,
    );
  });

  it("starts weeks in options.timeZone", () => {
    expect(sqlOf(BASE)).toContain(`at time zone 'UTC'`);
    expect(
      sqlOf(BASE, {
        modules: {
          "time-tracking": { options: { timeZone: "Europe/Amsterdam" } },
        },
      }),
    ).toContain(`at time zone 'Europe/Amsterdam'`);
    for (const timeZone of ["", "Mars/Olympus", 3]) {
      expect(() =>
        sqlOf(BASE, {
          modules: { "time-tracking": { options: { timeZone } } },
        }),
      ).toThrow(/timeZone/);
    }
  });

  it("files timesheets under options.policy", () => {
    expect(sqlOf(BASE)).toContain(`"permission":"time_tracking.approve"`);
    const custom = sqlOf(BASE, {
      modules: {
        "time-tracking": {
          options: {
            policy: { steps: [{ approvers: { role: "manager" } }] },
          },
        },
      },
    });
    expect(custom).toContain(`"role":"manager"`);
    expect(() =>
      sqlOf(BASE, {
        modules: {
          "time-tracking": {
            options: {
              policy: {
                steps: [{ approvers: { role: "manager" } }],
                run: { kind: "queue", queue: "x" },
              },
            },
          },
        },
      }),
    ).toThrow(/policy\.run is not allowed/);
  });

  it("lets approvals lock the week and read timesheet requests", () => {
    const approvals = sqlOf(BASE, {}, "approvals");
    expect(approvals).toContain(`"better_supabase"."approve_timesheet"(`);
    expect(approvals).toContain(`in ('access_request', 'timesheet')`);
    const alone = sqlOf(["approvals"], {}, "approvals");
    expect(alone).not.toContain("approve_timesheet");
  });

  it("needs the approvals tables", () => {
    expect(() =>
      sqlOf(BASE, { modules: { approvals: { mode: "custom" } } }),
    ).toThrow(/approvals can't be in custom mode/);
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { "time-tracking": { mode: "custom" } } };
    expect(sqlOf(BASE, custom).trim()).toBe("");
    const [contract] = customContracts(["time-tracking"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual([
      "start_timer",
      "stop_timer",
      "log_time",
      "submit_timesheet",
      "get_timesheet",
    ]);
  });

  it("works on adopted tables without creating them", () => {
    const sql = sqlOf(BASE, {
      modules: {
        "time-tracking": {
          mode: "adopt",
          tables: { entries: "app.hours", timesheets: "app.weeks" },
        },
      },
    });
    expect(sql).not.toMatch(/create table if not exists "app"/);
    expect(sql).not.toContain("btree_gist");
    expect(sql).toContain(`"app"."hours"`);
    expect(sql).toContain(`"app"."weeks"`);
  });
});
