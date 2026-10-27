import { describe, expect, it } from "vitest";

import { customContracts, renderBlocks } from "../../../src/sql/render.ts";
import { upgradePlan } from "../../../src/sql/upgrade.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const sqlOf = (
  modules: readonly string[],
  layout: Layout = {},
  module = "time-tracking",
): string =>
  renderBlocks(modules, layout)
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
          options: { policy: { steps: [{ approvers: { role: "manager" } }] } },
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
    expect(approvals).toContain(`= 'timesheet'`);
    const alone = sqlOf(["approvals"], {}, "approvals");
    expect(alone).not.toContain("approve_timesheet");
  });

  it("stores the rate as minor units per hour with its currency", () => {
    const sql = sqlOf(BASE);
    expect(sql).toContain(
      `"rate" bigint check ("rate" is null or "rate" >= 0),\n  "rate_currency" text,`,
    );
    expect(sql).not.toContain("numeric(12, 2)");
    expect(sql).toContain(
      `add constraint "time_entries_rate_currency_check"\n      check ("rate_currency" is null or "rate_currency" ~ '^[A-Z]{3}$') not valid;`,
    );
    expect(sql).toContain(
      `add constraint "time_entries_rate_needs_currency_check"\n      check ("rate" is null or "rate_currency" is not null) not valid;`,
    );
    expect(sql).toContain(
      `'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency"`,
    );
  });

  it("takes the rate as an amount and a currency", () => {
    const sql = sqlOf(BASE);
    expect(sql).toContain(
      "rate bigint default null, rate_currency text default null, note text default null",
    );
    expect(sql).toContain(
      `drop function if exists "better_supabase"."start_timer"(uuid, text, text, boolean, numeric, text);`,
    );
    expect(sql).toContain(
      `drop function if exists "better_supabase"."log_time"(uuid, timestamptz, timestamptz, text, text, boolean, numeric, text, uuid, jsonb);`,
    );
    expect(sql).toContain("TIME_RATE_INVALID");
    expect(sql).toContain(`v_row."rate" := (v_patch ->> 'rate')::bigint;`);
    expect(sql).not.toContain("::numeric");

    const [contract] = customContracts(["time-tracking"], {
      modules: { "time-tracking": { mode: "custom" } },
    });

    expect(contract?.functions[0]?.args).toEqual([
      "{id}",
      "text",
      "text",
      "boolean",
      "bigint",
      "text",
      "text",
    ]);
  });

  it("totals billable amounts per currency in minor units", () => {
    const sql = sqlOf(BASE);
    expect(sql).toContain(
      `jsonb_build_object('amount', q.amount::text, 'currency', q.currency) order by q.currency`,
    );
    expect(sql).toContain(
      `round(sum(extract(epoch from coalesce(y."ended_at", now()) - y."started_at") * y."rate" / 3600))::bigint as amount`,
    );
    expect(sql).toContain(`group by y."rate_currency"`);
  });

  it("upgrades a numeric rate to minor units", () => {
    const plan = upgradePlan([
      { module: "approvals", version: 99 },
      { module: "time-tracking", version: 1 },
    ]).find((entry) => entry.module === "time-tracking");

    expect(plan?.to).toBe(3);
    const sql = plan?.steps[0]?.sql ?? "";
    expect(sql).toContain(
      `alter table "better_supabase"."time_entries" add column if not exists "rate_currency" text;`,
    );
    expect(sql).toContain(
      `alter column "rate" type bigint using round("rate" * 100)::bigint;`,
    );
    expect(sql).toContain("data_type = 'numeric'");
    expect(sql).toContain("time_entries_rate_needs_currency_check");
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
      "running_timers",
      "log_time",
      "submit_timesheet",
      "get_timesheet",
    ]);
  });

  it("works on the app's tables without creating them", () => {
    const sql = sqlOf(BASE, {
      modules: {
        "time-tracking": {
          tables: { entries: "app.hours", timesheets: "app.weeks" },
        },
      },
      ownTables: { "app.hours": "app.sql", "app.weeks": "app.sql" },
    });

    expect(sql).not.toMatch(/create table if not exists "app"/);
    expect(sql).not.toContain("exclude using gist");
    expect(sql).toContain(`"app"."hours"`);
    expect(sql).toContain(`"app"."weeks"`);
  });
});
