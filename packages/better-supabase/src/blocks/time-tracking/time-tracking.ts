import type { Money } from "../../commerce/money.ts";
import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { DbError, ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { isCurrency } from "../../commerce/money.ts";
import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  amountText,
  moneyOf,
  optionalMoneyOf,
  unknownCurrency,
} from "../money-codec.ts";
import {
  applyTemporal,
  blockCall,
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

export interface TimeTrackingOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /**
   * A Standard Schema for the entry's extra columns
   * (`blocks.time-tracking.options.extraColumns`), keyed by database name. It
   * types and parses them on reads, and validates them on `start`, `log` and
   * `update`.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<TimeTracking<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

/** A time entry. `F` types the extra columns the `fields` schema describes. */
export interface TimeEntry<F extends object = Record<never, never>> {
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
  /** The hourly rate, in minor units of its currency. */
  readonly rate?: Money;
  readonly note?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

/** The record time is tracked on, how it bills, and the extra columns. */
export interface TimeEntryFields<F extends object = Record<never, never>> {
  readonly subjectType?: string;
  readonly subjectId?: string;
  readonly billable?: boolean;
  /** The hourly rate, in minor units of its currency. */
  readonly rate?: Money;
  readonly note?: string;
  /** The extra columns to set. */
  readonly fields?: Partial<F>;
}

export interface LogTimeInput<
  F extends object = Record<never, never>,
> extends TimeEntryFields<F> {
  readonly startedAt: Temporal.Instant;
  readonly endedAt: Temporal.Instant;
  /** Another member; needs `time_tracking.manage`. Default: the caller. */
  readonly userId?: string;
}

/** The fields to change. `null` clears the subject, rate or note. */
export interface TimeEntryPatch<F extends object = Record<never, never>> {
  readonly startedAt?: Temporal.Instant;
  readonly endedAt?: Temporal.Instant;
  readonly subject?: {
    readonly subjectType: string;
    readonly subjectId: string;
  } | null;
  readonly billable?: boolean;
  readonly rate?: Money | null;
  readonly note?: string | null;
  /** The extra columns to set. */
  readonly fields?: Partial<F>;
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
  /**
   * Billable hours times their rate, rounded to minor units: one amount per
   * currency, ordered by currency code.
   */
  readonly amounts: readonly Money[];
}

export interface TimesheetDetail<
  F extends object = Record<never, never>,
> extends Timesheet {
  /** The entries that start in the week, oldest first. */
  readonly entries: readonly TimeEntry<F>[];
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

export interface TimeTracking<F extends object = Record<never, never>> {
  /** Starts a timer for the caller and stops the one that runs. */
  start(
    organizationId: string,
    fields?: TimeEntryFields<F>,
  ): AsyncResult<TimeEntry<F>>;
  stop(organizationId: string): AsyncResult<TimeEntry<F>>;
  /** The caller's running timer. */
  running(organizationId: string): AsyncResult<TimeEntry<F> | undefined>;
  log(
    organizationId: string,
    input: LogTimeInput<F>,
  ): AsyncResult<TimeEntry<F>>;
  update(entryId: string, patch: TimeEntryPatch<F>): AsyncResult<TimeEntry<F>>;
  remove(entryId: string): AsyncResult<TimeEntry<F>>;
  /** Newest first. */
  list(
    organizationId: string,
    options?: TimeEntryListOptions,
  ): AsyncResult<readonly TimeEntry<F>[]>;
  /** A member's week (the caller's by default) with its entries and totals. */
  timesheet(
    organizationId: string,
    week: Temporal.PlainDate,
    userId?: string,
  ): AsyncResult<TimesheetDetail<F>>;
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
    ...optional(
      "rate",
      optionalMoneyOf(row["rate"], row["rateCurrency"], "rate"),
    ),
    ...optional("note", optionalText(row["note"])),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
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
    amounts: (Array.isArray(row["amounts"]) ? row["amounts"] : []).map(
      (item: unknown) => {
        const entry = isRecord(item) ? item : {};

        return moneyOf(entry["amount"], entry["currency"], "totals.amounts");
      },
    ),
  };
}

/** Why a rate can't be sent, or `undefined` when it can. */
const rateError = (rate: Money | null | undefined): DbError | undefined =>
  rate === undefined || rate === null || isCurrency(rate.currency)
    ? undefined
    : unknownCurrency(rate.currency);

function patchOf(patch: TimeEntryPatch<object>): Record<string, unknown> {
  const out: Record<string, unknown> = {};

  if (patch.startedAt !== undefined) {
    out["startedAt"] = patch.startedAt.toString();
  }

  if (patch.endedAt !== undefined) {
    out["endedAt"] = patch.endedAt.toString();
  }

  if (patch.subject !== undefined) {
    out["subjectType"] = patch.subject?.subjectType ?? null;
    out["subjectId"] = patch.subject?.subjectId ?? null;
  }

  if (patch.billable !== undefined) {
    out["billable"] = patch.billable;
  }

  if (patch.rate !== undefined) {
    out["rate"] = patch.rate === null ? null : amountText(patch.rate);
    out["rateCurrency"] = patch.rate?.currency ?? null;
  }

  if (patch.note !== undefined) {
    out["note"] = patch.note;
  }

  return out;
}

/** The `time-tracking` SQL module as typed calls. */
export function createTimeTracking<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: TimeTrackingOptions<S>): TimeTracking<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const fields: BlockFields<F> = blockFields(
    options.fields,
    "time entry fields",
  );

  const client: TimeTracking<F> = {
    start: (organizationId, entry = {}) => {
      const invalid = rateError(entry.rate);

      if (invalid !== undefined) {
        return AsyncResult.err(invalid);
      }

      return fields
        .args(entry.fields)
        .andThen((checked) =>
          call(
            "start_timer",
            {
              tenant: organizationId,
              subject_type: entry.subjectType ?? null,
              subject_id: entry.subjectId ?? null,
              billable: entry.billable ?? false,
              rate: entry.rate === undefined ? null : amountText(entry.rate),
              rate_currency: entry.rate?.currency ?? null,
              note: entry.note ?? null,
              fields: checked,
            },
            (value) => entryOf(value, "start_timer"),
          ).andThen(fields.row),
        );
    },
    stop: (organizationId) =>
      call("stop_timer", { tenant: organizationId }, (value) =>
        entryOf(value, "stop_timer"),
      ).andThen(fields.row),
    running: (organizationId) =>
      call("running_timer", { tenant: organizationId }, (value) =>
        value === null || value === undefined
          ? undefined
          : entryOf(value, "running_timer"),
      ).andThen((entry) =>
        entry === undefined ? AsyncResult.ok(undefined) : fields.row(entry),
      ),
    log: (organizationId, input) => {
      const invalid = rateError(input.rate);

      if (invalid !== undefined) {
        return AsyncResult.err(invalid);
      }

      return fields
        .args(input.fields)
        .andThen((checked) =>
          call(
            "log_time",
            {
              tenant: organizationId,
              started_at: instantArg(input.startedAt),
              ended_at: instantArg(input.endedAt),
              subject_type: input.subjectType ?? null,
              subject_id: input.subjectId ?? null,
              billable: input.billable ?? false,
              rate: input.rate === undefined ? null : amountText(input.rate),
              rate_currency: input.rate?.currency ?? null,
              note: input.note ?? null,
              user_id: input.userId ?? null,
              fields: checked,
            },
            (value) => entryOf(value, "log_time"),
          ).andThen(fields.row),
        );
    },
    update: (entryId, patch) => {
      const invalid = rateError(patch.rate);

      if (invalid !== undefined) {
        return AsyncResult.err(invalid);
      }

      return fields
        .args(patch.fields)
        .andThen((checked) =>
          call(
            "update_time_entry",
            {
              entry_id: entryId,
              patch: {
                ...patchOf(patch),
                ...(checked === undefined ? {} : { fields: checked }),
              },
            },
            (value) => entryOf(value, "update_time_entry"),
          ).andThen(fields.row),
        );
    },
    remove: (entryId) =>
      call("delete_time_entry", { entry_id: entryId }, (value) =>
        entryOf(value, "delete_time_entry"),
      ).andThen(fields.row),
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
      ).andThen(fields.rows),
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
      ).andThen((detail) =>
        fields.rows(detail.entries).map((entries) => ({ ...detail, entries })),
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
