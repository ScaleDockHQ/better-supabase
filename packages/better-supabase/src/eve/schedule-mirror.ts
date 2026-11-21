import type { AiSchedules } from "../blocks/ai-schedules/ai-schedules.ts";
import type { EveScheduleRun } from "./dynamic-schedules.ts";

/**
 * Writes each schedule and its occurrences to the `ai-schedules` tables, so the
 * app lists eve schedules next to the tasks its users create themselves. The
 * rows carry `source` (default `eve`), which `ai-schedules` skips when it
 * claims due tasks, so it never runs them a second time.
 */
export interface EveScheduleMirror {
  /**
   * The `ai-schedules` block from `createBlocks`, with a service transport.
   * Only `mirror`, `unmirror` and `recordRun` are used.
   */
  readonly schedules: Pick<AiSchedules, "mirror" | "recordRun" | "unmirror">;
  /** The task's `source`. Default: `eve`. */
  readonly source?: string;
  /**
   * The user the task belongs to. Defaults to the creator's principal id when
   * it is a uuid; a schedule without a user is not mirrored.
   */
  readonly userOf?: (run: EveScheduleRun) => string | undefined;
  /** The task's prompt. Defaults to the schedule's display name. */
  readonly promptOf?: (run: EveScheduleRun) => string;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

interface Timing {
  readonly cron: string;
  readonly timeZone: string;
  readonly nextRun: Temporal.Instant;
}

interface ScheduleMirrorHelpers {
  /** The stored name of a schedule, which is the task's `externalId`. */
  readonly name: (run: EveScheduleRun) => string;
  /** The principal that created the schedule, from its payload. */
  readonly principalOf: (run: EveScheduleRun) => string | undefined;
}

/** What `queueScheduleProvider` calls to keep the `ai-schedules` tables current. */
export interface ScheduleMirror {
  /** Creates or updates the task. A failed write throws. */
  save(run: EveScheduleRun, timing: Timing): Promise<void>;
  /** Deletes the task. A failed write throws. */
  remove(run: EveScheduleRun): Promise<void>;
  /** Records an occurrence. Never throws. */
  record(
    run: EveScheduleRun,
    scheduledAt: Temporal.Instant,
    status: "completed" | "failed" | "running",
    error?: string,
  ): Promise<void>;
}

export function scheduleMirror(
  mirror: EveScheduleMirror | undefined,
  helpers: ScheduleMirrorHelpers,
): ScheduleMirror {
  const source = mirror?.source ?? "eve";

  const userOf = (run: EveScheduleRun): string | undefined => {
    const user = mirror?.userOf?.(run) ?? helpers.principalOf(run);

    return user !== undefined && UUID.test(user) ? user : undefined;
  };

  return {
    async save(run, timing) {
      const user = userOf(run);

      if (
        mirror === undefined ||
        run.tenant === undefined ||
        user === undefined
      ) {
        return;
      }

      await mirror.schedules
        .mirror({
          organizationId: run.tenant,
          userId: user,
          source,
          externalId: helpers.name(run),
          task: {
            title: run.displayName.slice(0, 200),
            prompt: (mirror.promptOf?.(run) ?? run.displayName).slice(
              0,
              20_000,
            ),
            cron: timing.cron,
            timezone: timing.timeZone,
            enabled: run.state === "active",
          },
          ...(run.state === "active" ? { nextRunAt: timing.nextRun } : {}),
        })
        .orThrow();
    },

    async remove(run) {
      if (mirror === undefined || run.tenant === undefined) {
        return;
      }

      await mirror.schedules
        .unmirror({
          organizationId: run.tenant,
          source,
          externalId: helpers.name(run),
        })
        .orThrow();
    },

    async record(run, scheduledAt, status, error) {
      if (
        mirror === undefined ||
        run.tenant === undefined ||
        userOf(run) === undefined
      ) {
        return;
      }

      try {
        await mirror.schedules
          .recordRun({
            organizationId: run.tenant,
            source,
            externalId: helpers.name(run),
            scheduledFor: scheduledAt,
            status,
            ...(error === undefined ? {} : { error }),
          })
          .orThrow();
      } catch {
        // The mirror is a record of the run; a failed write must not change it.
      }
    },
  };
}
