import type { Money } from "../../commerce/money.ts";
import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTenantOptions } from "../../core/block-tenant.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { DbError, ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { RecordRef } from "../../schema/types.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { isCurrency } from "../../commerce/money.ts";
import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { optionalRecordRefOf } from "../../core/block-subjects.ts";
import { requireTenant } from "../../core/block-tenant.ts";
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
>
  extends BlockTemporalOptions, BlockTenantOptions {
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
  readonly employeeId?: string;
  /** The record the time is tracked on; `undefined` for an unattached entry. */
  readonly subject: RecordRef | undefined;
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
  /** The record the time is on. Default: none. */
  readonly subject?: RecordRef;
  readonly billable?: boolean;
  /** The hourly rate, in minor units of its currency. */
  readonly rate?: Money;
  /**
   * The currency to store without a rate, such as the organization's default
   * when the app's currency column can't be empty. A rate's currency wins.
   */
  readonly currency?: string;
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
  readonly employeeId?: string;
}

/** The fields to change. `null` clears the subject, rate or note. */
export interface TimeEntryPatch<F extends object = Record<never, never>> {
  readonly startedAt?: Temporal.Instant;
  readonly endedAt?: Temporal.Instant;
  readonly subject?: RecordRef | null;
  readonly billable?: boolean;
  readonly rate?: Money | null;
  readonly note?: string | null;
  /** The extra columns to set. */
  readonly fields?: Partial<F>;
}

export interface TimeEntryListOptions {
  /** Another member's entries; needs `time_tracking.read`. Default: the caller. */
  readonly userId?: string;
  readonly employeeId?: string;
  /** Every member's entries; needs `time_tracking.read`. */
  readonly everyone?: boolean;
  /** Entries that end after this instant. */
  readonly from?: Temporal.Instant;
  /** Entries that start before this instant. */
  readonly to?: Temporal.Instant;
  /** Entries on this record only. */
  readonly subject?: RecordRef;
  readonly pageSize?: number;
}

export type TimesheetStatus = "open" | "submitted" | "approved" | "rejected";

export interface Timesheet {
  /** Missing for a week that was never submitted. */
  readonly id?: string;
  readonly organizationId: string;
  readonly userId: string;
  readonly employeeId?: string;
  /** The Monday the week starts on. */
  readonly week: Temporal.PlainDate;
  readonly status: TimesheetStatus;
  readonly approvalId?: string;
  readonly note?: string;
  readonly submittedAt?: Temporal.Instant;
  readonly approvedAt?: Temporal.Instant;
  /** With `options.approvals: false`: who decided the week. */
  readonly decidedBy?: string;
  /** With `options.approvals: false`: when the week was decided. */
  readonly decidedAt?: Temporal.Instant;
  /** With `options.approvals: false`: the note of a rejection. */
  readonly decisionNote?: string;
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

/** `approve` and `reject` options. */
export interface TimesheetDecisionOptions {
  /** The user who decided, for a service role client. */
  readonly decidedBy?: string;
}

export interface TimesheetListOptions {
  /** Another member's timesheets; needs `time_tracking.read`. */
  readonly userId?: string;
  readonly employeeId?: string;
  readonly status?: TimesheetStatus;
  readonly pageSize?: number;
  /** Weeks before this one, for the next page. */
  readonly before?: Temporal.PlainDate;
}

/**
 * `F` is the extra fields `options.fields` describes. The methods that don't
 * take an entry or timesheet id act in the block's `tenant`.
 */
export interface TimeTracking<F extends object = Record<never, never>> {
  /**
   * Starts a timer for the caller, on `fields.subject` when set, and stops the
   * one that runs.
   */
  start(fields?: TimeEntryFields<F>): AsyncResult<TimeEntry<F>>;
  /**
   * Stops the caller's timer: `entryId`'s with `options.timers: "many"`, else
   * the newest running one.
   */
  stop(entryId?: string): AsyncResult<TimeEntry<F>>;
  /** The caller's running timer, the newest when several run. */
  running(): AsyncResult<TimeEntry<F> | undefined>;
  /** Every timer the caller has running, newest first. */
  runningAll(): AsyncResult<readonly TimeEntry<F>[]>;
  /**
   * Runs a stopped entry again from now, over a table with a duration column:
   * it keeps its start and time, and the next stop adds the new segment.
   */
  resume(entryId: string): AsyncResult<TimeEntry<F>>;
  /** Records a finished entry, on `input.subject` when set. */
  log(input: LogTimeInput<F>): AsyncResult<TimeEntry<F>>;
  update(entryId: string, patch: TimeEntryPatch<F>): AsyncResult<TimeEntry<F>>;
  remove(entryId: string): AsyncResult<TimeEntry<F>>;
  /** Newest first. */
  list(options?: TimeEntryListOptions): AsyncResult<readonly TimeEntry<F>[]>;
  /** A member's week (the caller's by default) with its entries and totals. */
  timesheet(
    week: Temporal.PlainDate,
    userId?: string,
    employeeId?: string,
  ): AsyncResult<TimesheetDetail<F>>;
  /** Sends the caller's week for approval; it locks until a rejection. */
  submit(
    week: Temporal.PlainDate,
    note?: string,
    employeeId?: string,
  ): AsyncResult<Timesheet>;
  /** Unlocks an approved week; needs `time_tracking.manage`. */
  reopen(timesheetId: string): AsyncResult<Timesheet>;
  /**
   * With `options.approvals: false`: approves a submitted week; needs
   * `time_tracking.approve`, and nobody approves their own. A service role
   * client may pass `decidedBy` to record the user who decided, never the
   * week's owner.
   */
  approve(
    timesheetId: string,
    options?: TimesheetDecisionOptions,
  ): AsyncResult<Timesheet>;
  /**
   * With `options.approvals: false`: sends a submitted week back with a note,
   * which unlocks it. `decidedBy` works as in `approve`.
   */
  reject(
    timesheetId: string,
    note?: string,
    options?: TimesheetDecisionOptions,
  ): AsyncResult<Timesheet>;
  /** Newest week first. */
  timesheets(options?: TimesheetListOptions): AsyncResult<readonly Timesheet[]>;
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
    userId: optionalText(row["userId"]) ?? "",
    ...optional("employeeId", optionalText(row["employeeId"])),
    subject: optionalRecordRefOf(row["subjectType"], row["subjectId"]),
    startedAt: requiredInstant(row["startedAt"], "startedAt"),
    billable: row["billable"] === true,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
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
    userId: optionalText(row["userId"]) ?? "",
    ...optional("employeeId", optionalText(row["employeeId"])),
    week: temporal().PlainDate.from(textOf(row["week"])),
    status: enumOrThrow(row["status"], STATUSES, "timesheet status"),
    ...optional("id", optionalText(row["id"])),
    ...optional("approvalId", optionalText(row["approvalId"])),
    ...optional("note", optionalText(row["note"])),
    ...optional("submittedAt", optionalInstant(row["submittedAt"])),
    ...optional("approvedAt", optionalInstant(row["approvedAt"])),
    ...optional("decidedBy", optionalText(row["decidedBy"])),
    ...optional("decidedAt", optionalInstant(row["decidedAt"])),
    ...optional("decisionNote", optionalText(row["decisionNote"])),
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
    out["subjectType"] = patch.subject?.type ?? null;
    out["subjectId"] = patch.subject?.id ?? null;
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

  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const client: TimeTracking<F> = {
    start: (entry = {}) => {
      const invalid = rateError(entry.rate);

      if (invalid !== undefined) {
        return AsyncResult.err(invalid);
      }

      return tenant().andThen((organizationId) =>
        fields
          .args(entry.fields)
          .andThen((checked) =>
            call(
              "start_timer",
              {
                tenant: organizationId,
                subject_type: entry.subject?.type ?? null,
                subject_id: entry.subject?.id ?? null,
                billable: entry.billable ?? false,
                rate: entry.rate === undefined ? null : amountText(entry.rate),
                rate_currency: entry.rate?.currency ?? entry.currency ?? null,
                note: entry.note ?? null,
                fields: checked,
              },
              (value) => entryOf(value, "start_timer"),
            ).andThen(fields.row),
          ),
      );
    },
    stop: (entryId) =>
      tenant().andThen((organizationId) =>
        call(
          "stop_timer",
          { tenant: organizationId, entry: entryId ?? null },
          (value) => entryOf(value, "stop_timer"),
        ).andThen(fields.row),
      ),
    runningAll: () =>
      tenant().andThen((organizationId) =>
        call("running_timers", { tenant: organizationId }, (value) =>
          recordsOf(value, "running_timers").map((row) =>
            entryOf(row, "running_timers"),
          ),
        ).andThen(fields.rows),
      ),
    resume: (entryId) =>
      call("resume_timer", { entry: entryId }, (value) =>
        entryOf(value, "resume_timer"),
      ).andThen(fields.row),
    running: () =>
      tenant().andThen((organizationId) =>
        call("running_timer", { tenant: organizationId }, (value) =>
          value === null || value === undefined
            ? undefined
            : entryOf(value, "running_timer"),
        ).andThen((entry) =>
          entry === undefined ? AsyncResult.ok(undefined) : fields.row(entry),
        ),
      ),
    log: (input) => {
      const invalid = rateError(input.rate);

      if (invalid !== undefined) {
        return AsyncResult.err(invalid);
      }

      return tenant().andThen((organizationId) =>
        fields
          .args(input.fields)
          .andThen((checked) =>
            call(
              "log_time",
              {
                tenant: organizationId,
                started_at: instantArg(input.startedAt),
                ended_at: instantArg(input.endedAt),
                subject_type: input.subject?.type ?? null,
                subject_id: input.subject?.id ?? null,
                billable: input.billable ?? false,
                rate: input.rate === undefined ? null : amountText(input.rate),
                rate_currency: input.rate?.currency ?? input.currency ?? null,
                note: input.note ?? null,
                user_id: input.userId ?? null,
                ...optional("employee_id", input.employeeId),
                fields: checked,
              },
              (value) => entryOf(value, "log_time"),
            ).andThen(fields.row),
          ),
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
    list: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_time_entries",
          {
            tenant: organizationId,
            user_id: list.userId ?? null,
            starts: instantArg(list.from) ?? null,
            ends: instantArg(list.to) ?? null,
            subject_type: list.subject?.type ?? null,
            subject_id: list.subject?.id ?? null,
            everyone: list.everyone ?? false,
            page_size: list.pageSize ?? null,
            ...optional("employee_id", list.employeeId),
          },
          (value) =>
            recordsOf(value, "list_time_entries").map((row) =>
              entryOf(row, "list_time_entries"),
            ),
        ).andThen(fields.rows),
      ),
    timesheet: (week, userId, employeeId) =>
      tenant().andThen((organizationId) =>
        call(
          "get_timesheet",
          {
            tenant: organizationId,
            week: week.toString(),
            user_id: userId ?? null,
            ...optional("employee_id", employeeId),
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
          fields
            .rows(detail.entries)
            .map((entries) => ({ ...detail, entries })),
        ),
      ),
    submit: (week, note, employeeId) =>
      tenant().andThen((organizationId) =>
        call(
          "submit_timesheet",
          {
            tenant: organizationId,
            week: week.toString(),
            note: note ?? null,
            ...optional("employee_id", employeeId),
          },
          (value) => timesheetOf(value, "submit_timesheet"),
        ),
      ),
    approve: (timesheetId, decision = {}) =>
      call(
        "approve_timesheet",
        {
          timesheet_id: timesheetId,
          ...optional("decided_by", decision.decidedBy),
        },
        (value) => timesheetOf(value, "approve_timesheet"),
      ),
    reject: (timesheetId, note, decision = {}) =>
      call(
        "reject_timesheet",
        {
          timesheet_id: timesheetId,
          note: note ?? null,
          ...optional("decided_by", decision.decidedBy),
        },
        (value) => timesheetOf(value, "reject_timesheet"),
      ),
    reopen: (timesheetId) =>
      call("reopen_timesheet", { timesheet_id: timesheetId }, (value) =>
        timesheetOf(value, "reopen_timesheet"),
      ),
    timesheets: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_timesheets",
          {
            tenant: organizationId,
            user_id: list.userId ?? null,
            status: list.status ?? null,
            page_size: list.pageSize ?? null,
            before: list.before?.toString() ?? null,
            ...optional("employee_id", list.employeeId),
          },
          (value) =>
            recordsOf(value, "list_timesheets").map((row) =>
              timesheetOf(row, "list_timesheets"),
            ),
        ),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "time-tracking",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
