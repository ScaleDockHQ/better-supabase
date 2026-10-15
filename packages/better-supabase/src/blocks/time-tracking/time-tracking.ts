import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  enumOrThrow,
  instantArg,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export interface TimeTrackingOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /** The module schema, or its API schema: `defineBlocks` passes it from `blocks.generated.ts`. */
  readonly schema?: string;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: BlockHooks<TimeTracking>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

export interface TimeEntry {
  readonly id: string;
  readonly organizationId: string;
  readonly userId: string;
  readonly subjectType?: string;
  readonly subjectId?: string;
  readonly startedAt: Temporal.Instant;
  /** Missing while the timer runs. */
  readonly endedAt?: Temporal.Instant;
  /** Missing while the timer runs. */
  readonly seconds?: number;
  readonly billable: boolean;
  /** The hourly rate, in the organization's currency. */
  readonly rate?: number;
  readonly note?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** The record time is tracked on, and how it bills. */
export interface TimeEntryFields {
  readonly subjectType?: string;
  readonly subjectId?: string;
  readonly billable?: boolean;
  readonly rate?: number;
  readonly note?: string;
}

export interface LogTimeInput extends TimeEntryFields {
  readonly startedAt: Temporal.Instant;
  readonly endedAt: Temporal.Instant;
  /** Another member; needs `time_tracking.manage`. Default: the caller. */
  readonly userId?: string;
}

/** The fields to change. `null` clears the subject, rate or note. */
export interface TimeEntryPatch {
  readonly startedAt?: Temporal.Instant;
  readonly endedAt?: Temporal.Instant;
  readonly subject?: {
    readonly subjectType: string;
    readonly subjectId: string;
  } | null;
  readonly billable?: boolean;
  readonly rate?: number | null;
  readonly note?: string | null;
}

export interface TimeEntryListOptions {
  /** Another member's entries; needs `time_tracking.read`. Default: the caller. */
  readonly userId?: string;
  /** Every member's entries; needs `time_tracking.read`. */
  readonly everyone?: boolean;
  /** Entries that end after this instant. */
  readonly from?: Temporal.Instant;
  /** Entries that start before this instant. */
  readonly to?: Temporal.Instant;
  readonly subjectType?: string;
  readonly subjectId?: string;
  readonly pageSize?: number;
}

export type TimesheetStatus = "open" | "submitted" | "approved" | "rejected";

export interface Timesheet {
  /** Missing for a week that was never submitted. */
  readonly id?: string;
  readonly organizationId: string;
  readonly userId: string;
  /** The Monday the week starts on. */
  readonly week: Temporal.PlainDate;
  readonly status: TimesheetStatus;
  readonly approvalId?: string;
  readonly note?: string;
  readonly submittedAt?: Temporal.Instant;
  readonly approvedAt?: Temporal.Instant;
}

export interface TimesheetTotals {
  /** Every entry, running ones up to now. */
  readonly seconds: number;
  readonly billableSeconds: number;
  /** Billable hours times their rate, rounded to cents. */
  readonly amount: number;
}

export interface TimesheetDetail extends Timesheet {
  /** The entries that start in the week, oldest first. */
  readonly entries: readonly TimeEntry[];
  readonly totals: TimesheetTotals;
}

export interface TimesheetListOptions {
  /** Another member's timesheets; needs `time_tracking.read`. */
  readonly userId?: string;
  readonly status?: TimesheetStatus;
  readonly pageSize?: number;
  /** Weeks before this one, for the next page. */
  readonly before?: Temporal.PlainDate;
}

export interface TimeTracking {
  /** Starts a timer for the caller and stops the one that runs. */
  start(
    organizationId: string,
    fields?: TimeEntryFields,
  ): AsyncResult<TimeEntry>;
  stop(organizationId: string): AsyncResult<TimeEntry>;
  /** The caller's running timer. */
  running(organizationId: string): AsyncResult<TimeEntry | undefined>;
  log(organizationId: string, input: LogTimeInput): AsyncResult<TimeEntry>;
  update(entryId: string, patch: TimeEntryPatch): AsyncResult<TimeEntry>;
  remove(entryId: string): AsyncResult<TimeEntry>;
  /** Newest first. */
  list(
    organizationId: string,
    options?: TimeEntryListOptions,
  ): AsyncResult<readonly TimeEntry[]>;
  /** A member's week (the caller's by default) with its entries and totals. */
  timesheet(
    organizationId: string,
    week: Temporal.PlainDate,
    userId?: string,
  ): AsyncResult<TimesheetDetail>;
  /** Sends the caller's week for approval; it locks until a rejection. */
  submit(
    organizationId: string,
    week: Temporal.PlainDate,
    note?: string,
  ): AsyncResult<Timesheet>;
  /** Unlocks an approved week; needs `time_tracking.manage`. */
  reopen(timesheetId: string): AsyncResult<Timesheet>;
  /** Newest week first. */
  timesheets(
    organizationId: string,
    options?: TimesheetListOptions,
  ): AsyncResult<readonly Timesheet[]>;
}

const STATUSES: readonly TimesheetStatus[] = [
  "open",
  "submitted",
  "approved",
  "rejected",
];

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

const numberOf = (value: unknown): number | undefined =>
  typeof value === "number" ? value : undefined;

function entryOf(value: unknown, fn: string): TimeEntry {
  const row = recordOf(value, fn);
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    userId: textOf(row["userId"]),
    startedAt: requiredInstant(row["startedAt"], "startedAt"),
    billable: row["billable"] === true,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("subjectType", optionalText(row["subjectType"])),
    ...optional("subjectId", optionalText(row["subjectId"])),
    ...optional("endedAt", optionalInstant(row["endedAt"])),
    ...optional("seconds", numberOf(row["seconds"])),
    ...optional("rate", numberOf(row["rate"])),
    ...optional("note", optionalText(row["note"])),
  };
}

function timesheetOf(value: unknown, fn: string): Timesheet {
  const row = recordOf(value, fn);
  return {
    organizationId: textOf(row["organizationId"]),
    userId: textOf(row["userId"]),
    week: temporal().PlainDate.from(textOf(row["week"])),
    status: enumOrThrow(row["status"], STATUSES, "timesheet status"),
    ...optional("id", optionalText(row["id"])),
    ...optional("approvalId", optionalText(row["approvalId"])),
    ...optional("note", optionalText(row["note"])),
    ...optional("submittedAt", optionalInstant(row["submittedAt"])),
    ...optional("approvedAt", optionalInstant(row["approvedAt"])),
  };
}

function totalsOf(value: unknown): TimesheetTotals {
  const row = isRecord(value) ? value : {};
  return {
    seconds: numberOf(row["seconds"]) ?? 0,
    billableSeconds: numberOf(row["billableSeconds"]) ?? 0,
    amount: numberOf(row["amount"]) ?? 0,
  };
}

function patchOf(patch: TimeEntryPatch): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  if (patch.startedAt !== undefined) {
    out["startedAt"] = patch.startedAt.toString();
  }
  if (patch.endedAt !== undefined) out["endedAt"] = patch.endedAt.toString();
  if (patch.subject !== undefined) {
    out["subjectType"] = patch.subject?.subjectType ?? null;
    out["subjectId"] = patch.subject?.subjectId ?? null;
  }
  if (patch.billable !== undefined) out["billable"] = patch.billable;
  if (patch.rate !== undefined) out["rate"] = patch.rate;
  if (patch.note !== undefined) out["note"] = patch.note;
  return out;
}

/** The `time-tracking` SQL module as typed calls. */
export function createTimeTracking(options: TimeTrackingOptions): TimeTracking {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const client: TimeTracking = {
    start: (organizationId, fields = {}) =>
      call(
        "start_timer",
        {
          tenant: organizationId,
          subject_type: fields.subjectType ?? null,
          subject_id: fields.subjectId ?? null,
          billable: fields.billable ?? false,
          rate: fields.rate ?? null,
          note: fields.note ?? null,
        },
        (value) => entryOf(value, "start_timer"),
      ),
    stop: (organizationId) =>
      call("stop_timer", { tenant: organizationId }, (value) =>
        entryOf(value, "stop_timer"),
      ),
    running: (organizationId) =>
      call("running_timer", { tenant: organizationId }, (value) =>
        value === null || value === undefined
          ? undefined
          : entryOf(value, "running_timer"),
      ),
    log: (organizationId, input) =>
      call(
        "log_time",
        {
          tenant: organizationId,
          started_at: instantArg(input.startedAt),
          ended_at: instantArg(input.endedAt),
          subject_type: input.subjectType ?? null,
          subject_id: input.subjectId ?? null,
          billable: input.billable ?? false,
          rate: input.rate ?? null,
          note: input.note ?? null,
          user_id: input.userId ?? null,
        },
        (value) => entryOf(value, "log_time"),
      ),
    update: (entryId, patch) =>
      call(
        "update_time_entry",
        { entry_id: entryId, patch: patchOf(patch) },
        (value) => entryOf(value, "update_time_entry"),
      ),
    remove: (entryId) =>
      call("delete_time_entry", { entry_id: entryId }, (value) =>
        entryOf(value, "delete_time_entry"),
      ),
    list: (organizationId, list = {}) =>
      call(
        "list_time_entries",
        {
          tenant: organizationId,
          user_id: list.userId ?? null,
          starts: instantArg(list.from) ?? null,
          ends: instantArg(list.to) ?? null,
          subject_type: list.subjectType ?? null,
          subject_id: list.subjectId ?? null,
          everyone: list.everyone ?? false,
          page_size: list.pageSize ?? null,
        },
        (value) =>
          recordsOf(value, "list_time_entries").map((row) =>
            entryOf(row, "list_time_entries"),
          ),
      ),
    timesheet: (organizationId, week, userId) =>
      call(
        "get_timesheet",
        {
          tenant: organizationId,
          week: week.toString(),
          user_id: userId ?? null,
        },
        (value) => {
          const row = recordOf(value, "get_timesheet");
          return {
            ...timesheetOf(row, "get_timesheet"),
            entries: recordsOf(row["entries"], "get_timesheet").map((item) =>
              entryOf(item, "get_timesheet"),
            ),
            totals: totalsOf(row["totals"]),
          };
        },
      ),
    submit: (organizationId, week, note) =>
      call(
        "submit_timesheet",
        { tenant: organizationId, week: week.toString(), note: note ?? null },
        (value) => timesheetOf(value, "submit_timesheet"),
      ),
    reopen: (timesheetId) =>
      call("reopen_timesheet", { timesheet_id: timesheetId }, (value) =>
        timesheetOf(value, "reopen_timesheet"),
      ),
    timesheets: (organizationId, list = {}) =>
      call(
        "list_timesheets",
        {
          tenant: organizationId,
          user_id: list.userId ?? null,
          status: list.status ?? null,
          page_size: list.pageSize ?? null,
          before: list.before?.toString() ?? null,
        },
        (value) =>
          recordsOf(value, "list_timesheets").map((row) =>
            timesheetOf(row, "list_timesheets"),
          ),
      ),
  };
  return withBlockHooks(client, options.hooks, {
    block: "time-tracking",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
