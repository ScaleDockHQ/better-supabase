import type { ScheduleProvider } from "../../blocks/queue/backends.ts";
import type { ConformanceReport } from "../conformance.ts";

import { temporal } from "../../core/temporal-required.ts";
import { conform, expect } from "../conformance.ts";
import { hasName } from "./executor.ts";

export interface TestScheduleProviderOptions {
  /**
   * A name prefix the kit may write and remove schedules under; use a fresh one
   * per run, such as `conformance:<timestamp>:`.
   */
  readonly prefix: string;
  /** The queue each schedule targets. */
  readonly queue: string;
  /** A tenant the kit may write and remove schedules for. */
  readonly tenant?: string;
  /**
   * A SQL function without arguments that returns boolean, to check that a
   * schedule keeps its probe. Leave it out for a scheduler without a database.
   */
  readonly probe?: string;
  /**
   * The scheduler rejects a probe (`vercelScheduler` without a bridge): check
   * that `schedule` with one throws instead.
   */
  readonly rejectsProbes?: boolean;
}

/**
 * Proves a `ScheduleProvider` writes, rewrites and removes schedules by name,
 * keeps a tenant's schedules apart (with `unscheduleTenant`), keeps or refuses
 * a probe, and (with `dueSchedules` and `advanceSchedule`) leases a due
 * schedule once and advances it only from the run it claimed. It writes under
 * `options.prefix` in the scheduler's real store.
 */
export function testScheduleProvider(
  scheduler: ScheduleProvider,
  options: TestScheduleProviderOptions,
): Promise<ConformanceReport> {
  const { prefix, queue } = options;
  const now = temporal().Now.instant();
  const later = now.add({ hours: 1 });
  const name = (suffix: string): string => `${prefix}${suffix}`;

  const listed = async (
    filter: { readonly tenant?: string } = {},
  ): Promise<readonly string[] | undefined> =>
    scheduler.listSchedules === undefined
      ? undefined
      : (await scheduler.listSchedules({ prefix, ...filter })).map(
          (schedule) => schedule.name,
        );

  return conform(`ScheduleProvider "${scheduler.name}"`, [
    hasName(scheduler),
    [
      "has apiVersion 1",
      () => {
        const version: unknown = scheduler.apiVersion;
        expect(version === 1, "apiVersion must be 1");
      },
    ],
    [
      "writes a schedule once per name and removes it",
      async () => {
        const one = name("one");

        await scheduler.schedule(
          one,
          "0 3 * * *",
          queue,
          { n: 1 },
          "UTC",
          later,
        );
        await scheduler.schedule(
          one,
          "0 4 * * *",
          queue,
          { n: 2 },
          "UTC",
          later,
        );

        const names = await listed();

        expect(
          names === undefined || names.filter((n) => n === one).length === 1,
          "writing a name twice must keep one schedule",
        );

        if (scheduler.listSchedules) {
          const [stored] = await scheduler.listSchedules({ prefix: one });
          expect(stored?.cron === "0 4 * * *", "the rewrite must win");
        }

        expect(await scheduler.unschedule(one), "unschedule must return true");
        expect(
          !(await scheduler.unschedule(one)),
          "unschedule of a missing name must return false",
        );

        const after = await listed();

        expect(
          after === undefined || !after.includes(one),
          "an unscheduled name must not be listed",
        );
      },
    ],
    options.tenant !== undefined && [
      "keeps a tenant's schedules apart and removes them together",
      async () => {
        const tenant = options.tenant ?? "";
        const owned = name("tenant");

        await scheduler.schedule(
          owned,
          "0 5 * * *",
          queue,
          {},
          "UTC",
          later,
          tenant,
        );

        const mine = await listed({ tenant });

        expect(
          mine === undefined || mine.includes(owned),
          "listSchedules({ tenant }) must list the tenant's schedule",
        );

        if (scheduler.unscheduleTenant) {
          expect(
            (await scheduler.unscheduleTenant(tenant)) >= 1,
            "unscheduleTenant must count the removed schedule",
          );

          const left = await listed({ tenant });

          expect(
            left === undefined || !left.includes(owned),
            "unscheduleTenant must remove the tenant's schedules",
          );
        } else {
          expect(
            await scheduler.unschedule(owned, tenant),
            "unschedule with the tenant must remove it",
          );
        }
      },
    ],
    options.probe !== undefined && [
      "keeps the probe a schedule names",
      async () => {
        const probed = name("probe");

        await scheduler.schedule(
          probed,
          "0 6 * * *",
          queue,
          {},
          "UTC",
          later,
          undefined,
          options.probe,
        );

        if (scheduler.listSchedules) {
          const [stored] = await scheduler.listSchedules({ prefix: probed });
          expect(
            (stored?.probe ?? options.probe) === options.probe,
            "a listed probe must be the one written",
          );
        }

        await scheduler.unschedule(probed);
      },
    ],
    options.rejectsProbes === true && [
      "rejects a probe it can't check",
      async () => {
        let threw = false;

        try {
          await scheduler.schedule(
            name("probe"),
            "0 6 * * *",
            queue,
            {},
            "UTC",
            later,
            undefined,
            "public.has_work",
          );
        } catch {
          threw = true;
        }

        expect(threw, "schedule with a probe must throw");
      },
    ],
    scheduler.dueSchedules !== undefined &&
      scheduler.advanceSchedule !== undefined && [
        "leases a due schedule once and advances it from the claimed run",
        async () => {
          const due = name("due");

          const past = now
            .subtract({ minutes: 5 })
            .round({ smallestUnit: "millisecond", roundingMode: "floor" });

          await scheduler.schedule(due, "* * * * *", queue, {}, "UTC", past);

          const claimed = (await scheduler.dueSchedules?.(60, 100)) ?? [];
          const run = claimed.find((schedule) => schedule.name === due);

          expect(run, "dueSchedules must return the due schedule");
          expect(
            !((await scheduler.dueSchedules?.(60, 100)) ?? []).some(
              (schedule) => schedule.name === due,
            ),
            "a leased schedule must not be claimed again",
          );
          expect(
            await scheduler.advanceSchedule?.(due, run.nextRun, later),
            "advanceSchedule from the claimed run must return true",
          );
          expect(
            !(await scheduler.advanceSchedule?.(due, run.nextRun, later)),
            "advanceSchedule from a run it moved past must return false",
          );

          await scheduler.unschedule(due);
        },
      ],
  ]);
}
