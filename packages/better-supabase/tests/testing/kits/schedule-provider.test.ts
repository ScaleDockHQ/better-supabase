import { describe, expect, it } from "vitest";

import type {
  DueSchedule,
  ScheduleProvider,
  StoredSchedule,
} from "../../../src/blocks/queue/backends.ts";

import { temporal } from "../../../src/core/temporal-required.ts";
import { ConformanceError } from "../../../src/testing/conformance.ts";
import { testScheduleProvider } from "../../../src/testing/kits/schedule-provider.ts";

interface Row {
  readonly cron: string;
  readonly queue: string;
  readonly tenant: string | undefined;
  readonly probe: string | undefined;
  nextRun: Temporal.Instant;
  leasedUntil: Temporal.Instant | null;
}

/** A drain-style scheduler kept in a map, with every optional method. */
function memoryScheduler(): ScheduleProvider & {
  readonly rows: Map<string, Row>;
} {
  const rows = new Map<string, Row>();

  const stored = (name: string, row: Row): StoredSchedule => ({
    name,
    cron: row.cron,
    timeZone: "UTC",
    queue: row.queue,
    tenant: row.tenant ?? null,
    nextRun: row.nextRun,
    lastRun: null,
    leasedUntil: row.leasedUntil,
    createdAt: null,
    probe: row.probe ?? null,
  });

  return {
    apiVersion: 1,
    name: "memory",
    rows,
    async schedule(name, cron, queue, _payload, _zone, nextRun, tenant, probe) {
      rows.set(name, {
        cron,
        queue,
        tenant,
        probe,
        nextRun,
        leasedUntil: null,
      });
    },
    async unschedule(name) {
      return rows.delete(name);
    },
    async listSchedules(filter) {
      return [...rows]
        .filter(
          ([name, row]) =>
            name.startsWith(filter.prefix ?? "") &&
            (filter.tenant === undefined || row.tenant === filter.tenant),
        )
        .map(([name, row]) => stored(name, row));
    },
    async unscheduleTenant(tenant) {
      const owned = [...rows].filter(([, row]) => row.tenant === tenant);

      for (const [name] of owned) {
        rows.delete(name);
      }

      return owned.length;
    },
    async dueSchedules(lease) {
      const now = temporal().Now.instant();
      const due: DueSchedule[] = [];

      for (const [name, row] of rows) {
        const free =
          row.leasedUntil === null ||
          temporal().Instant.compare(row.leasedUntil, now) <= 0;

        if (free && temporal().Instant.compare(row.nextRun, now) <= 0) {
          row.leasedUntil = now.add({ seconds: lease });
          due.push({
            name,
            cron: row.cron,
            timeZone: "UTC",
            queue: row.queue,
            payload: {},
            nextRun: row.nextRun,
          });
        }
      }

      return due;
    },
    async advanceSchedule(name, ran, next) {
      const row = rows.get(name);

      if (row === undefined || !row.nextRun.equals(ran)) {
        return false;
      }

      row.nextRun = next;
      row.leasedUntil = null;

      return true;
    },
  };
}

const options = { prefix: "conformance:1:", queue: "emails" };

async function failures(
  scheduler: ScheduleProvider,
  extra: Partial<Parameters<typeof testScheduleProvider>[1]> = {},
): Promise<string[]> {
  const error = await testScheduleProvider(scheduler, {
    ...options,
    ...extra,
  }).then(
    () => undefined,
    (cause: unknown) => cause,
  );

  expect(error).toBeInstanceOf(ConformanceError);

  return (error as ConformanceError).report.checks
    .filter((check) => !check.ok)
    .map((check) => check.name);
}

describe("testScheduleProvider", () => {
  it("passes a scheduler with every optional method and leaves nothing behind", async () => {
    const scheduler = memoryScheduler();

    const report = await testScheduleProvider(scheduler, {
      ...options,
      tenant: "org_1",
      probe: "public.has_work",
    });

    expect(report.subject).toBe('ScheduleProvider "memory"');
    expect(report.checks.map((check) => check.name)).toContain(
      "leases a due schedule once and advances it from the claimed run",
    );
    expect(report.checks.every((check) => check.ok)).toBe(true);
    expect(scheduler.rows.size).toBe(0);
  });

  it("removes a tenant's schedule by name when the scheduler can't remove a tenant", async () => {
    const scheduler = memoryScheduler();

    delete scheduler.unscheduleTenant;

    const report = await testScheduleProvider(scheduler, {
      ...options,
      tenant: "org_1",
    });

    expect(report.checks.every((check) => check.ok)).toBe(true);
    expect(scheduler.rows.size).toBe(0);
  });

  it("passes a scheduler that can only write and remove", async () => {
    const full = memoryScheduler();

    const report = await testScheduleProvider(
      {
        apiVersion: 1,
        name: "minimal",
        schedule: async (...args) => full.schedule(...args),
        unschedule: async (...args) => full.unschedule(...args),
      },
      { ...options, tenant: "org_1" },
    );

    expect(report.checks.every((check) => check.ok)).toBe(true);
  });

  it("fails a scheduler that leases a due schedule twice", async () => {
    const scheduler = memoryScheduler();

    expect(
      await failures({
        ...scheduler,
        dueSchedules: async (lease, batch) => {
          const due = (await scheduler.dueSchedules?.(lease, batch)) ?? [];

          for (const run of due) {
            const row = scheduler.rows.get(run.name);

            if (row) {
              row.leasedUntil = null;
            }
          }

          return due;
        },
      }),
    ).toEqual([
      "leases a due schedule once and advances it from the claimed run",
    ]);
  });

  it("fails a scheduler that accepts a probe it said it rejects, or changes apiVersion", async () => {
    const scheduler = memoryScheduler();

    expect(await failures(scheduler, { rejectsProbes: true })).toEqual([
      "rejects a probe it can't check",
    ]);
    expect(
      await failures({
        ...scheduler,
        // SAFETY: the kit must catch a scheduler built for another contract version.
        apiVersion: 2 as unknown as 1,
      }),
    ).toEqual(["has apiVersion 1"]);
  });
});
