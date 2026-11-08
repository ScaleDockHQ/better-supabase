import { describe, expect, it } from "vitest";

import { customContracts, renderBlocks } from "../../../src/sql/render.ts";
import { upgradePlan } from "../../../src/sql/upgrade.ts";
import { unnamedChecks } from "../unnamed-checks.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const sqlOf = (
  modules: readonly string[],
  layout: Layout = {},
  module = "time-entries",
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

const BASE = ["approvals", "time-entries"];

describe("time-entries module", () => {
  it("restricts the record types of an entry to options.on", () => {
    expect(sqlOf(BASE)).not.toContain("time is tracked on");

    const sql = sqlOf(BASE, {
      modules: { "time-entries": { options: { on: ["company", "project"] } } },
    });

    expect(unnamedChecks(sql)).toContain(
      `<> all (array['company', 'project']::text[])`,
    );
    expect(unnamedChecks(sql)).toContain(
      "time is tracked on company, project records",
    );
    expect(() =>
      sqlOf(BASE, {
        modules: { "time-entries": { options: { on: ["Company"] } } },
      }),
    ).toThrow(/must list lowercase record types/);
  });

  it("keeps one running timer and no overlaps per member", () => {
    const sql = sqlOf(BASE);
    expect(unnamedChecks(sql)).toContain(
      "create extension if not exists btree_gist with schema extensions;",
    );
    expect(unnamedChecks(sql)).toContain(`exclude using gist (`);
    expect(unnamedChecks(sql)).toContain(
      `tstzrange("started_at", coalesce("ended_at", 'infinity'::timestamptz)) with &&`,
    );
    expect(unnamedChecks(sql)).toContain(`where "ended_at" is null;`);
    expect(unnamedChecks(sql)).toContain("TIME_ENTRY_OVERLAP");
  });

  it("locks submitted and approved weeks with a trigger", () => {
    const sql = sqlOf(BASE);
    expect(unnamedChecks(sql)).toContain(
      "before insert or update or delete on",
    );
    expect(unnamedChecks(sql)).toContain("TIME_PERIOD_LOCKED");
    expect(unnamedChecks(sql)).toContain(`"better_supabase"."open_approval"(`);
    expect(unnamedChecks(sql)).toContain(
      `revoke execute on function "better_supabase"."approve_timesheet"(uuid) from public, anon, authenticated;`,
    );
  });

  it("locks only the columns that change logged time, or options.lockedColumns", () => {
    expect(sqlOf(BASE)).toContain(
      `if tg_op = 'UPDATE' and (new."started_at", new."ended_at", new."subject_type", new."subject_id", new."user_id", new."rate", new."rate_currency") is not distinct from (old."started_at", old."ended_at", old."subject_type", old."subject_id", old."user_id", old."rate", old."rate_currency") then`,
    );

    const options = (lockedColumns: unknown): Layout => ({
      modules: { "time-entries": { options: { lockedColumns } } },
    });

    expect(
      sqlOf(BASE, options(["startedAt", "billable", "invoice_line_id"])),
    ).toContain(
      `(new."started_at", new."billable", new."invoice_line_id") is not distinct from (old."started_at", old."billable", old."invoice_line_id")`,
    );
    expect(sqlOf(BASE, options([]))).toContain(
      "if tg_op = 'UPDATE' and true then",
    );

    for (const bad of ["startedAt", ["Bad Name"], [1]]) {
      expect(() => sqlOf(BASE, options(bad))).toThrow(/lockedColumns/);
    }
  });

  it("starts weeks in options.timeZone", () => {
    expect(sqlOf(BASE)).toContain(`at time zone 'UTC'`);
    expect(
      sqlOf(BASE, {
        modules: {
          "time-entries": { options: { timeZone: "Europe/Amsterdam" } },
        },
      }),
    ).toContain(`at time zone 'Europe/Amsterdam'`);

    for (const timeZone of ["", "Mars/Olympus", 3]) {
      expect(() =>
        sqlOf(BASE, { modules: { "time-entries": { options: { timeZone } } } }),
      ).toThrow(/timeZone/);
    }
  });

  it("files timesheets under options.policy", () => {
    expect(sqlOf(BASE)).toContain(`"permission":"time_entries.approve"`);

    const custom = sqlOf(BASE, {
      modules: {
        "time-entries": {
          options: { policy: { steps: [{ approvers: { role: "manager" } }] } },
        },
      },
    });

    expect(custom).toContain(`"role":"manager"`);
    expect(() =>
      sqlOf(BASE, {
        modules: {
          "time-entries": {
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
    expect(unnamedChecks(sql)).toContain(
      `"rate" bigint check ("rate" is null or "rate" >= 0),\n  "rate_currency" text,`,
    );
    expect(unnamedChecks(sql)).not.toContain("numeric(12, 2)");
    expect(sql).toContain(
      `add constraint bsb_time_entries_rate_currency_check\n  check ("rate_currency" is null or "rate_currency" ~ '^[A-Z]{3}$');`,
    );
    expect(sql).toContain(
      `add constraint bsb_time_entries_rate_needs_currency_check\n  check ("rate" is null or "rate_currency" is not null);`,
    );
    expect(unnamedChecks(sql)).toContain(
      `'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency"`,
    );
  });

  it("takes the rate as an amount and a currency", () => {
    const sql = sqlOf(BASE);
    expect(unnamedChecks(sql)).toContain(
      "rate bigint default null, rate_currency text default null, note text default null",
    );
    expect(unnamedChecks(sql)).toContain("TIME_RATE_INVALID");
    expect(unnamedChecks(sql)).toContain(
      `v_row."rate" := (v_patch ->> 'rate')::bigint;`,
    );
    expect(unnamedChecks(sql)).not.toContain("::numeric");

    const [contract] = customContracts(["time-entries"], {
      modules: { "time-entries": { mode: "custom" } },
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
    expect(unnamedChecks(sql)).toContain(
      `jsonb_build_object('amount', q.amount::text, 'currency', q.currency) order by q.currency`,
    );
    expect(unnamedChecks(sql)).toContain(
      `round(sum(extract(epoch from coalesce(y."ended_at", now()) - y."started_at") * y."rate" / 3600))::bigint as amount`,
    );
    expect(unnamedChecks(sql)).toContain(`group by y."rate_currency"`);
  });

  it("upgrades a numeric rate to minor units", () => {
    const plan = upgradePlan([
      { module: "approvals", version: 99 },
      { module: "time-entries", version: 1 },
    ]).find((entry) => entry.module === "time-entries");

    expect(plan?.to).toBe(3);
    const sql = plan?.steps[0]?.sql ?? "";
    expect(unnamedChecks(sql)).toContain(
      `alter table "better_supabase"."time_entries" add column if not exists "rate_currency" text;`,
    );
    expect(unnamedChecks(sql)).toContain(
      `alter column "rate" type bigint using round("rate" * 100)::bigint;`,
    );
    expect(unnamedChecks(sql)).toContain("data_type = 'numeric'");
    expect(unnamedChecks(sql)).toContain(
      "time_entries_rate_needs_currency_check",
    );
  });

  it("needs the approvals tables", () => {
    expect(() =>
      sqlOf(BASE, { modules: { approvals: { mode: "custom" } } }),
    ).toThrow(/approvals can't be in custom mode/);
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { "time-entries": { mode: "custom" } } };
    expect(sqlOf(BASE, custom).trim()).toBe("");
    const [contract] = customContracts(["time-entries"], custom);
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
        "time-entries": {
          tables: { entries: "app.hours", timesheets: "app.weeks" },
        },
      },
      ownTables: { "app.hours": "app.sql", "app.weeks": "app.sql" },
    });

    expect(unnamedChecks(sql)).not.toMatch(/create table if not exists "app"/);
    expect(unnamedChecks(sql)).not.toContain("exclude using gist");
    expect(unnamedChecks(sql)).toContain(`"app"."hours"`);
    expect(unnamedChecks(sql)).toContain(`"app"."weeks"`);
  });
});
