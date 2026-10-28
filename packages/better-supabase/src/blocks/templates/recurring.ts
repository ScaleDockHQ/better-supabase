import type { DbError } from "../../core/errors.ts";
import type {
  EnqueueOnceOptions,
  EnqueueOnceResult,
  JobHandler,
} from "../queue/types.ts";
import type { BlockCall } from "../shared.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import { isInstant } from "../../core/temporal.ts";
import { expandRule } from "../reminders/rrule.ts";
import {
  instantOf,
  isRecord,
  optionalText,
  recordOf,
  recordOrEmpty,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

/** The queue `recurring.job` handles. */
export const TEMPLATE_RECUR_QUEUE = "templates.recur";

/** The payload `recurring.schedule` enqueues on `templates.recur`. */
export interface TemplateRecurPayload {
  readonly schedule: string;
  /** ISO text. */
  readonly occurrenceAt: string;
  readonly organizationId: string;
}

/**
 * The jobs queue `recurring.schedule` enqueues on: the `queue` block's client,
 * typed by shape so this block doesn't need it.
 */
export interface TemplateJobs {
  enqueueOnce(
    queue: typeof TEMPLATE_RECUR_QUEUE,
    payload: TemplateRecurPayload,
    options: EnqueueOnceOptions,
  ): AsyncResult<EnqueueOnceResult>;
}

/** A schedule that applies a template at each occurrence of an RRULE. */
export interface TemplateSchedule {
  readonly id: string;
  readonly template: string;
  readonly organizationId: string;
  /** The `values` each apply gets. */
  readonly input: Readonly<Record<string, unknown>>;
  readonly enabled: boolean;
  readonly dtstart: Temporal.Instant;
  /** The IANA time zone the rule expands in. */
  readonly tzid: string;
  readonly rrule: string;
  readonly createdBy: string | undefined;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface TemplateScheduleInput {
  /** Leave it out to create a schedule. */
  readonly id?: string;
  readonly template: string;
  readonly organizationId: string;
  readonly dtstart: Temporal.Instant;
  /** Default `UTC`. */
  readonly tzid?: string;
  /** An RFC 5545 RRULE, such as `FREQ=MONTHLY;BYMONTHDAY=1`. */
  readonly rrule: string;
  readonly input?: Readonly<Record<string, unknown>>;
  /** Default `true`. */
  readonly enabled?: boolean;
}

/** What `recurring.schedule` plans and when. */
export interface TemplateScheduleOptions {
  /** Default: now. */
  readonly now?: Temporal.Instant;
  /** How far ahead to enqueue occurrences, in minutes. Default 1440 (a day). */
  readonly horizonMinutes?: number;
  /** How far back a missed occurrence still runs, in minutes. Default 15. */
  readonly lookbackMinutes?: number;
}

/** What one `recurring.schedule` run did. */
export interface TemplateScheduleResult {
  readonly planned: number;
  readonly enqueued: number;
  readonly duplicates: number;
  /** Schedules whose time zone or rule couldn't be expanded. */
  readonly skipped: number;
}

/** What `recurring.run` did for one occurrence. */
export type TemplateOccurrence =
  | { readonly status: "applied"; readonly application: string }
  | { readonly status: "skipped" };

/**
 * Recurring records: schedules that apply a template at each occurrence of a
 * recurrence rule kept in the reminders module. Needs the reminders module.
 */
export interface TemplateRecurring {
  /** Creates or changes a schedule. `templates.manage` in its organization. */
  upsert(input: TemplateScheduleInput): AsyncResult<TemplateSchedule>;
  /** The organization's schedules, of one template when given. */
  list(
    organizationId: string,
    template?: string,
  ): AsyncResult<readonly TemplateSchedule[]>;
  remove(id: string): AsyncResult<boolean>;
  /**
   * Service role. Expands every enabled schedule and enqueues one
   * `templates.recur` job per occurrence due in the window on `jobs`, once per
   * schedule and occurrence.
   */
  schedule(
    options?: TemplateScheduleOptions,
  ): AsyncResult<TemplateScheduleResult>;
  /**
   * Service role. Claims the occurrence, applies the template with the
   * schedule's input under the key `template-schedule:<id>:<occurrence>`, and
   * records the application. An occurrence that already made one is skipped.
   */
  run(
    schedule: string,
    occurrenceAt: Temporal.Instant,
  ): AsyncResult<TemplateOccurrence>;
  /** The handler for the `templates.recur` queue. */
  readonly job: JobHandler<unknown>;
}

/** The part of `apply` recurring records call. */
export type TemplateApplyFn = (
  template: string,
  options: {
    readonly into: string;
    readonly values: Readonly<Record<string, unknown>>;
    readonly key: string;
  },
) => AsyncResult<{ readonly application: { readonly id: string } }>;

export interface TemplateRecurringDeps {
  readonly call: BlockCall;
  readonly apply: TemplateApplyFn;
  readonly jobs?: TemplateJobs;
}

function scheduleOf(row: Record<string, unknown>): TemplateSchedule {
  return {
    id: textOf(row["id"]),
    template: textOf(row["template"]),
    organizationId: textOf(row["tenant"]),
    input: recordOrEmpty(row["input"]),
    enabled: row["enabled"] !== false,
    dtstart: requiredInstant(row["dtstart"], "dtstart"),
    tzid: optionalText(row["tzid"]) ?? "UTC",
    rrule: textOf(row["rrule"]),
    createdBy: optionalText(row["createdBy"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
  };
}

interface PlannedOccurrence {
  readonly schedule: TemplateSchedule;
  readonly occurrenceAt: Temporal.Instant;
}

/** Each schedule's occurrences in the window, and how many couldn't expand. */
export function planOccurrences(
  schedules: readonly TemplateSchedule[],
  window: { readonly from: Temporal.Instant; readonly until: Temporal.Instant },
): {
  readonly planned: readonly PlannedOccurrence[];
  readonly skipped: number;
} {
  const planned: PlannedOccurrence[] = [];
  let skipped = 0;

  for (const schedule of schedules) {
    try {
      const occurrences = expandRule({
        dtstart: schedule.dtstart.toZonedDateTimeISO(schedule.tzid),
        rrule: schedule.rrule,
        window: { from: window.from, until: window.until },
      });

      for (const occurrence of occurrences) {
        planned.push({ schedule, occurrenceAt: occurrence.toInstant() });
      }
    } catch {
      skipped += 1;
    }
  }

  return { planned, skipped };
}

function payloadOf(value: unknown): {
  readonly schedule: string;
  readonly occurrenceAt: Temporal.Instant;
} {
  if (!isRecord(value)) {
    throw new TypeError(`${TEMPLATE_RECUR_QUEUE} needs an object payload`);
  }

  const at = value["occurrenceAt"];

  return {
    schedule: textOf(value["schedule"]),
    occurrenceAt: isInstant(at) ? at : instantOf(at),
  };
}

const jobsMissing = (): DbError =>
  dbError(
    "unexpected",
    "templates.recurring.schedule needs the jobs queue: pass `jobs` to createTemplates",
    { hint: "TEMPLATE_JOBS_MISSING" },
  );

export function createTemplateRecurring(
  deps: TemplateRecurringDeps,
): TemplateRecurring {
  const { call } = deps;

  const run: TemplateRecurring["run"] = (schedule, occurrenceAt) =>
    call(
      "claim_template_occurrence",
      { schedule_id: schedule, occurrence_at: occurrenceAt.toString() },
      (value) => (isRecord(value) ? scheduleOf(value) : undefined),
    ).andThen((claimed) => {
      if (claimed === undefined) {
        return AsyncResult.ok<TemplateOccurrence>({ status: "skipped" });
      }

      return deps
        .apply(claimed.template, {
          into: claimed.organizationId,
          values: claimed.input,
          key: `template-schedule:${claimed.id}:${occurrenceAt.toString()}`,
        })
        .andThen(({ application }) =>
          call(
            "finish_template_occurrence",
            {
              schedule_id: claimed.id,
              occurrence_at: occurrenceAt.toString(),
              application_id: application.id,
            },
            (): TemplateOccurrence => ({
              status: "applied",
              application: application.id,
            }),
          ),
        );
    });

  return {
    upsert: (input) =>
      call(
        "save_template_schedule",
        {
          schedule_id: input.id ?? null,
          template_id: input.template,
          tenant: input.organizationId,
          dtstart: input.dtstart.toString(),
          tzid: input.tzid ?? "UTC",
          rrule: input.rrule,
          input: input.input ?? {},
          enabled: input.enabled ?? true,
        },
        (value) => scheduleOf(recordOf(value, "save_template_schedule")),
      ),
    list: (organizationId, template) =>
      call(
        "template_schedules_list",
        { tenant: organizationId, template_id: template ?? null },
        (value) => recordsOf(value, "template_schedules_list").map(scheduleOf),
      ),
    remove: (id) =>
      call(
        "remove_template_schedule",
        { schedule_id: id },
        (value) => value === true,
      ),
    schedule: (options = {}) =>
      AsyncResult.from(async () => {
        const jobs = deps.jobs;

        if (jobs === undefined) {
          return err(jobsMissing());
        }

        const now = options.now ?? temporal().Now.instant();

        const window = {
          from: now.subtract({ minutes: options.lookbackMinutes ?? 15 }),
          until: now.add({ minutes: options.horizonMinutes ?? 1440 }),
        };

        const rows = await call("list_template_schedule", {}, (value) =>
          recordsOf(value, "list_template_schedule").map(scheduleOf),
        );

        if (!rows.ok) {
          return rows;
        }

        const { planned, skipped } = planOccurrences(rows.data, window);
        let enqueued = 0;

        for (const { schedule, occurrenceAt } of planned) {
          const iso = occurrenceAt.toString();

          const job = await jobs.enqueueOnce(
            TEMPLATE_RECUR_QUEUE,
            {
              schedule: schedule.id,
              occurrenceAt: iso,
              organizationId: schedule.organizationId,
            },
            {
              dedupeKey: `${schedule.id}:${iso}`,
              runAt:
                temporal().Instant.compare(occurrenceAt, now) < 0
                  ? now
                  : occurrenceAt,
              context: { tenant: schedule.organizationId },
            },
          );

          if (!job.ok) {
            return job;
          }

          enqueued += job.data.duplicate ? 0 : 1;
        }

        return ok({
          planned: planned.length,
          enqueued,
          duplicates: planned.length - enqueued,
          skipped,
        });
      }),
    run,
    job: async (payload) => {
      const { schedule, occurrenceAt } = payloadOf(payload);

      await run(schedule, occurrenceAt).orThrow();
    },
  };
}
