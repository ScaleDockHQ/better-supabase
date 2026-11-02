import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { TestUser } from "./block-session.ts";

import {
  createPayrollExport,
  csvPayrollFormat,
} from "../../src/blocks/payroll-export/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { temporal } from "../../src/core/temporal-required.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = [
  "organizations",
  "outbox",
  "audit",
  "time-tracking",
  "payroll-export",
];

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

const day = (value: string): Temporal.PlainDate =>
  temporal().PlainDate.from(value);

describe.skipIf(!live)("payroll-export module in Postgres", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  let s: BlockSession;
  let owner: TestUser;
  let member: TestUser;
  let tenant: string;

  const payroll = () =>
    createPayrollExport({ transport: sqlTransport(s.sql), tenant });

  beforeAll(async () => {
    s = await BlockSession.open(pool);
    owner = await s.user("payroll-owner");
    member = await s.user("payroll-member");
    await s.install(MODULES);
    tenant = await s.organization(owner, { member });
    await s.service();
    await s.rows(
      `insert into better_supabase.time_entries (tenant_id, user_id, started_at, ended_at)
       values ($1, $2, '2027-03-02T08:00:00Z', '2027-03-02T10:00:00Z'),
              ($1, $2, '2027-03-03T08:00:00Z', '2027-03-03T09:30:00Z'),
              ($1, $2, '2027-03-10T08:00:00Z', '2027-03-10T12:00:00Z')`,
      [tenant, member.id],
    );
    // Only the week of 2027-03-01 is approved, so the entry of 2027-03-10 stays out.
    await s.rows(
      `insert into better_supabase.timesheets (tenant_id, user_id, week, submitted_at, approved_at)
       values ($1, $2, '2027-03-01', now(), now())`,
      [tenant, member.id],
    );
    await s.as(owner);
  });

  afterAll(async () => {
    await s.close();
    await pool.end();
  });

  it("collects the hours, exports once and locks the period", async () => {
    const run = await payroll()
      .create({ from: day("2027-03-01"), to: day("2027-03-31") })
      .orThrow();

    expect(run.lines).toMatchObject([
      { userId: member.id, kind: "worked", unit: "hours", quantity: 3.5 },
    ]);

    const exported = await payroll()
      .exportRun({ runId: run.id, format: csvPayrollFormat() })
      .orThrow();

    expect(exported.run).toMatchObject({ status: "exported", format: "csv" });
    expect(exported.run.checksum).toMatch(/^[0-9a-f]{64}$/);

    const again = await payroll()
      .exportRun({ runId: run.id, format: csvPayrollFormat() })
      .orThrow();

    expect(again.run.exportedAt).toEqual(exported.run.exportedAt);

    expect(
      hint(
        await payroll().exportRun({
          runId: run.id,
          format: csvPayrollFormat({ delimiter: "," }),
        }),
      ),
    ).toBe("PAYROLL_RUN_EXPORTED");
    expect(hint(await payroll().refresh(run.id))).toBe("PAYROLL_RUN_EXPORTED");
    expect(hint(await payroll().delete(run.id))).toBe("PAYROLL_RUN_EXPORTED");
    expect(
      hint(
        await payroll().create({
          from: day("2027-03-20"),
          to: day("2027-04-10"),
        }),
      ),
    ).toBe("PAYROLL_PERIOD_EXPORTED");

    const events = await s.rows<{ type: string }>(
      "select type from better_supabase.outbox_events where organization_id = $1 and type like 'payroll_run.%' order by position",
      [tenant],
    );

    expect(events.map((row) => row.type)).toEqual([
      "payroll_run.created",
      "payroll_run.exported",
    ]);
  });

  it("deletes a draft and refuses a bad period and a member", async () => {
    const draft = await payroll()
      .create({ from: day("2027-05-01"), to: day("2027-05-31") })
      .orThrow();

    await payroll().delete(draft.id).orThrow();
    expect(await payroll().get(draft.id).orThrow()).toBeUndefined();

    expect(
      hint(
        await payroll().create({
          from: day("2027-05-31"),
          to: day("2027-05-01"),
        }),
      ),
    ).toBe("PAYROLL_RUN_INVALID");

    await s.as(member);
    expect(
      hint(
        await payroll().create({
          from: day("2027-06-01"),
          to: day("2027-06-30"),
        }),
      ),
    ).toBe("PAYROLL_FORBIDDEN");
    expect(hint(await payroll().list())).toBe("PAYROLL_FORBIDDEN");
  });
});
