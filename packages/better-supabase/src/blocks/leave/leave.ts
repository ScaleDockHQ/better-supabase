import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export interface LeaveOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /**
   * A Standard Schema for the request's extra columns
   * (`blocks.leave.options.extraColumns`), keyed by database name. It types and
   * parses them on reads, and validates them on `request`.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Leave<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

export type LeaveUnit = "days" | "hours";

export interface LeaveType {
  readonly id: string;
  readonly organizationId: string;
  readonly key: string;
  readonly name: string;
  readonly unit: LeaveUnit;
  readonly paid: boolean;
  /** Whether requests book against a balance. */
  readonly tracked: boolean;
  /** What `accrue` grants per period when it names no amount. */
  readonly allowance?: number;
  /** How much `closePeriod` carries over; missing carries everything. */
  readonly carryoverMax?: number;
  readonly color?: string;
  /** Requests of this type need no approval. */
  readonly autoApprove?: boolean;
  readonly archivedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface LeaveTypeInput {
  readonly key: string;
  readonly name: string;
  /** Default `days`. */
  readonly unit?: LeaveUnit;
  /** Default `true`. */
  readonly paid?: boolean;
  /** Default `true`. */
  readonly tracked?: boolean;
  readonly allowance?: number;
  readonly carryoverMax?: number;
  /** `#rrggbb`. */
  readonly color?: string;
  /**
   * Requests of this type are approved when they are made, also by the
   * requester. Needs the block's types table or a mapped
   * `columns.types.autoApprove`.
   */
  readonly autoApprove?: boolean;
}

export type LeavePartial = "full" | "morning" | "afternoon" | "hours";

export type LeaveStatus = "pending" | "approved" | "rejected" | "cancelled";

/** One approved request in a leave feed. */
export interface LeaveFeedEntry {
  readonly id: string;
  readonly userId?: string;
  readonly employeeId?: string;
  /** The employee's name, with `options.feed.names`. */
  readonly name?: string;
  readonly typeId: string;
  /** The leave type's name; missing for a type in `options.feed.hideTypes`. */
  readonly type?: string;
  readonly startsOn: Temporal.PlainDate;
  /** Inclusive. */
  readonly endsOn: Temporal.PlainDate;
  readonly partial: LeavePartial;
  /** The part of the first day. */
  readonly startPart?: LeavePartial;
  /** The part of the last day. */
  readonly endPart?: LeavePartial;
  readonly amount: number;
  readonly updatedAt: Temporal.Instant;
  /** The request's extra columns, with `options.feed.fields`. */
  readonly fields?: Readonly<Record<string, unknown>>;
}

/**
 * Confidential leave in a feed with `options.feed.confidential: "busy"`: who
 * and when, without the type, amount or fields.
 */
export interface LeaveFeedBusy {
  readonly id: string;
  readonly userId?: string;
  readonly employeeId?: string;
  /** The employee's name, with `options.feed.names`. */
  readonly name?: string;
  readonly startsOn: Temporal.PlainDate;
  /** Inclusive. */
  readonly endsOn: Temporal.PlainDate;
  readonly partial: LeavePartial;
  readonly startPart?: LeavePartial;
  readonly endPart?: LeavePartial;
  readonly updatedAt: Temporal.Instant;
}

/** What a leave feed share link reads. */
export interface LeaveFeed {
  readonly organizationId: string;
  /** With `options.feed.organizationName`. */
  readonly organizationName?: string;
  /** The team of a `leave_team_feed` link. */
  readonly teamId?: string;
  /** The team's name, with `options.feed.teamName`. */
  readonly teamName?: string;
  readonly requests: readonly LeaveFeedEntry[];
  /** With `options.feed.confidential: "busy"`. */
  readonly busy?: readonly LeaveFeedBusy[];
}

/** A leave request. `F` types the extra columns the `fields` schema describes. */
export interface LeaveRequest<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly userId?: string;
  readonly employeeId?: string;
  readonly typeId: string;
  readonly startsOn: Temporal.PlainDate;
  /** Inclusive. */
  readonly endsOn: Temporal.PlainDate;
  readonly partial: LeavePartial;
  readonly startPart?: LeavePartial;
  readonly endPart?: LeavePartial;
  /** Working days, or hours for an hours type. */
  readonly amount: number;
  readonly note?: string;
  readonly status: LeaveStatus;
  readonly approvalId?: string;
  readonly approvedAt?: Temporal.Instant;
  readonly cancelledAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

export interface LeaveRequestInput<F extends object = Record<never, never>> {
  readonly typeId: string;
  readonly startsOn: Temporal.PlainDate;
  /** Inclusive; default `startsOn`. */
  readonly endsOn?: Temporal.PlainDate;
  /** A half day (`morning`, `afternoon`) for a day type. Default `full`. */
  readonly partial?: Exclude<LeavePartial, "hours">;
  readonly startPart?: LeavePartial;
  readonly endPart?: LeavePartial;
  /** Required for an hours type. */
  readonly hours?: number;
  readonly note?: string;
  readonly employeeId?: string;
  /** The extra columns to set. */
  readonly fields?: Partial<F>;
}

/**
 * A change to a pending or approved request. What it leaves out keeps its
 * value; an empty `note` clears it.
 */
export interface LeaveRequestUpdate<F extends object = Record<never, never>> {
  readonly startsOn?: Temporal.PlainDate;
  /** Inclusive. */
  readonly endsOn?: Temporal.PlainDate;
  readonly partial?: Exclude<LeavePartial, "hours">;
  readonly startPart?: LeavePartial;
  readonly endPart?: LeavePartial;
  readonly hours?: number;
  readonly note?: string;
  readonly fields?: Partial<F>;
}

export interface LeaveRequestListOptions {
  /** Another member's requests; needs `leave.read`. Default: the caller. */
  readonly userId?: string;
  readonly employeeId?: string;
  /** Every member's requests; needs `leave.read`. */
  readonly everyone?: boolean;
  readonly status?: LeaveStatus;
  /** Requests that end on or after this date. */
  readonly from?: Temporal.PlainDate;
  /** Requests that start on or before this date. */
  readonly to?: Temporal.PlainDate;
  readonly pageSize?: number;
}

export interface LeaveBalance {
  readonly typeId: string;
  readonly key: string;
  readonly name: string;
  readonly unit: LeaveUnit;
  readonly userId?: string;
  readonly employeeId?: string;
  readonly period: number;
  /** Grants, accruals, adjustments and carryover, less expiry. */
  readonly granted: number;
  /** Approved leave, net of cancellations. */
  readonly taken: number;
  /** Requests waiting for approval. */
  readonly pending: number;
  /** Everything in the ledger, less pending requests. */
  readonly available: number;
}

export type LeaveLedgerKind =
  | "grant"
  | "accrual"
  | "taken"
  | "adjustment"
  | "carryover"
  | "expiry";

export interface LeaveLedgerEntry {
  readonly id: string;
  readonly organizationId: string;
  readonly userId?: string;
  readonly employeeId?: string;
  readonly typeId: string;
  readonly kind: LeaveLedgerKind;
  /** Signed. */
  readonly amount: number;
  readonly period: number;
  readonly expiresOn?: Temporal.PlainDate;
  readonly requestId?: string;
  readonly note?: string;
  readonly createdAt: Temporal.Instant;
}

export interface LeaveAdjustment {
  readonly userId?: string;
  readonly employeeId?: string;
  readonly typeId: string;
  /** Signed. */
  readonly amount: number;
  /** Default: this year. */
  readonly period?: number;
  /** Default `adjustment`. */
  readonly kind?: "grant" | "adjustment";
  readonly note?: string;
  readonly expiresOn?: Temporal.PlainDate;
  /**
   * The day the entry counts from, such as a backdated correction. Default: the
   * first day of the period. Needs `columns.balances.effectiveOn`.
   */
  readonly effectiveOn?: Temporal.PlainDate;
}

export interface LeaveAccrual {
  readonly typeId: string;
  /** Default: the type's allowance. */
  readonly amount?: number;
  /** Default: this year. */
  readonly period?: number;
  /** Default: every member. */
  readonly userIds?: readonly string[];
  readonly employeeIds?: readonly string[];
  /** A member gets an accrual with the same key once. */
  readonly idempotencyKey?: string;
  readonly note?: string;
  /**
   * The day the accrual counts from, such as the first of the month. Default:
   * the first day of the period. Needs `columns.balances.effectiveOn`.
   */
  readonly effectiveOn?: Temporal.PlainDate;
}

export interface Leave<F extends object = Record<never, never>> {
  /** Needs `leave.manage`; updates the type with the same key. */
  saveType(input: {
    organizationId: string;
    input: LeaveTypeInput;
  }): AsyncResult<LeaveType>;
  /** Needs `leave.manage`. */
  archiveType(typeId: string): AsyncResult<LeaveType>;
  types(
    input: { organizationId: string } & { readonly archived?: boolean },
  ): AsyncResult<readonly LeaveType[]>;
  /** Asks for leave and opens its approval. */
  request(input: {
    organizationId: string;
    input: LeaveRequestInput<F>;
  }): AsyncResult<LeaveRequest<F>>;
  /**
   * The requester while it's pending or before approved leave starts, or
   * `leave.manage` any time.
   */
  cancel(requestId: string): AsyncResult<LeaveRequest<F>>;
  /**
   * Changes a request's dates, parts of the day, hours, note or fields. The
   * requester changes a pending request, which goes back to approval;
   * `leave.manage` also changes approved leave, which is booked again.
   */
  update(input: {
    requestId: string;
    update: LeaveRequestUpdate<F>;
  }): AsyncResult<LeaveRequest<F>>;
  /**
   * Takes a gap out of approved leave: the request ends before `gapStarts`, and
   * a new approved request (`split`) takes the days after `gapEnds`. Needs
   * `leave.manage`.
   */
  split(input: {
    requestId: string;
    gap: {
      readonly gapStarts: Temporal.PlainDate;
      readonly gapEnds: Temporal.PlainDate;
    };
  }): AsyncResult<{
    readonly request: LeaveRequest<F>;
    readonly split: LeaveRequest<F>;
  }>;
  /**
   * Approves or rejects a pending request when leave runs without the approvals
   * block (`options.approvals: false`). Needs `leave.approve`, and the
   * requester can't decide their own.
   */
  decide(input: {
    requestId: string;
    decision: {
      readonly approved: boolean;
      readonly note?: string;
      /** The user the service role decides for, kept as `decidedBy`. */
      readonly decidedBy?: string;
    };
  }): AsyncResult<LeaveRequest<F>>;
  /**
   * The approved leave behind a `leave_feed` share link (subject id: the
   * organization's id), a year back and everything ahead, for an iCal feed.
   * `null` for an unknown or revoked token, or when the link's creator can no
   * longer read everyone's leave.
   */
  feed(token: string): AsyncResult<LeaveFeed | null>;
  /** Earliest first. */
  list(
    input: { organizationId: string } & LeaveRequestListOptions,
  ): AsyncResult<readonly LeaveRequest<F>[]>;
  /**
   * A member's balance of each tracked type (the caller's, this year by
   * default).
   */
  balances(
    input: { organizationId: string } & {
      readonly userId?: string;
      readonly employeeId?: string;
      readonly period?: number;
    },
  ): AsyncResult<readonly LeaveBalance[]>;
  /** A member's ledger entries, newest first. */
  ledger(
    input: { organizationId: string } & {
      readonly userId?: string;
      readonly employeeId?: string;
      readonly period?: number;
      readonly typeId?: string;
    },
  ): AsyncResult<readonly LeaveLedgerEntry[]>;
  /** Needs `leave.manage`. */
  adjust(input: {
    organizationId: string;
    adjustment: LeaveAdjustment;
  }): AsyncResult<LeaveLedgerEntry>;
  /**
   * Grants an accrual to every member, or `userIds`; returns the entries
   * written. Needs `leave.manage`.
   */
  accrue(input: {
    organizationId: string;
    accrual: LeaveAccrual;
  }): AsyncResult<number>;
  /**
   * Carries balances into the next period and expires the rest; returns the
   * entries written. Needs `leave.manage`.
   */
  closePeriod(input: {
    organizationId: string;
    period: number;
  }): AsyncResult<number>;
  /** `decide` with `approved: true`. */
  approve(input: {
    requestId: string;
    note?: string | undefined;
    decidedBy?: string | undefined;
  }): AsyncResult<LeaveRequest<F>>;
  /** `decide` with `approved: false`. */
  reject(input: {
    requestId: string;
    note?: string | undefined;
    decidedBy?: string | undefined;
  }): AsyncResult<LeaveRequest<F>>;
  /** The requests waiting for a decision, from every member when `everyone`. */
  pending(
    input: { organizationId: string } & Omit<LeaveRequestListOptions, "status">,
  ): AsyncResult<readonly LeaveRequest<F>[]>;
}

const UNITS: readonly LeaveUnit[] = ["days", "hours"];

const PARTIALS: readonly LeavePartial[] = [
  "full",
  "morning",
  "afternoon",
  "hours",
];

const STATUSES: readonly LeaveStatus[] = [
  "pending",
  "approved",
  "rejected",
  "cancelled",
];

const KINDS: readonly LeaveLedgerKind[] = [
  "grant",
  "accrual",
  "taken",
  "adjustment",
  "carryover",
  "expiry",
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

const decimal = (value: unknown): number => Number(value ?? 0);

const optionalDecimal = (value: unknown): number | undefined =>
  value === null || value === undefined ? undefined : Number(value);

const dateOf = (value: unknown): Temporal.PlainDate =>
  temporal().PlainDate.from(textOf(value));

const numberOf = (value: unknown): number =>
  typeof value === "number" ? value : Number(value);

const optionalPart = (value: unknown): LeavePartial | undefined =>
  value === null || value === undefined
    ? undefined
    : enumOrThrow(value, PARTIALS, "leave part");

const owners = (
  row: Readonly<Record<string, unknown>>,
): { readonly userId?: string; readonly employeeId?: string } => ({
  ...optional("userId", optionalText(row["userId"])),
  ...optional("employeeId", optionalText(row["employeeId"])),
});

function typeOf(value: unknown, fn: string): LeaveType {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    key: textOf(row["key"]),
    name: textOf(row["name"]),
    unit: enumOrThrow(row["unit"], UNITS, "leave unit"),
    paid: row["paid"] === true,
    tracked: row["tracked"] === true,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("allowance", optionalDecimal(row["allowance"])),
    ...optional("carryoverMax", optionalDecimal(row["carryoverMax"])),
    ...optional("color", optionalText(row["color"])),
    ...optional(
      "autoApprove",
      typeof row["autoApprove"] === "boolean" ? row["autoApprove"] : undefined,
    ),
    ...optional("archivedAt", optionalInstant(row["archivedAt"])),
  };
}

function requestOf(value: unknown, fn: string): LeaveRequest {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    ...owners(row),
    typeId: textOf(row["typeId"]),
    startsOn: dateOf(row["startsOn"]),
    endsOn: dateOf(row["endsOn"]),
    partial: enumOrThrow(row["partial"], PARTIALS, "leave partial"),
    amount: decimal(row["amount"]),
    status: enumOrThrow(row["status"], STATUSES, "leave status"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("note", optionalText(row["note"])),
    ...optional("startPart", optionalPart(row["startPart"])),
    ...optional("endPart", optionalPart(row["endPart"])),
    ...optional("approvalId", optionalText(row["approvalId"])),
    ...optional("approvedAt", optionalInstant(row["approvedAt"])),
    ...optional("cancelledAt", optionalInstant(row["cancelledAt"])),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
  };
}

function balanceOf(value: unknown, fn: string): LeaveBalance {
  const row = recordOf(value, fn);

  return {
    typeId: textOf(row["typeId"]),
    key: textOf(row["key"]),
    name: textOf(row["name"]),
    unit: enumOrThrow(row["unit"], UNITS, "leave unit"),
    ...owners(row),
    period: numberOf(row["period"]),
    granted: decimal(row["granted"]),
    taken: decimal(row["taken"]),
    pending: decimal(row["pending"]),
    available: decimal(row["available"]),
  };
}

function entryOf(value: unknown, fn: string): LeaveLedgerEntry {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    ...owners(row),
    typeId: textOf(row["typeId"]),
    kind: enumOrThrow(row["kind"], KINDS, "leave ledger kind"),
    amount: decimal(row["amount"]),
    period: numberOf(row["period"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...optional(
      "expiresOn",
      row["expiresOn"] === null || row["expiresOn"] === undefined
        ? undefined
        : dateOf(row["expiresOn"]),
    ),
    ...optional("requestId", optionalText(row["requestId"])),
    ...optional("note", optionalText(row["note"])),
  };
}

/** The `leave` SQL module as typed calls. */
export function createLeave<S extends StandardSchemaV1 | undefined = undefined>(
  options: LeaveOptions<S>,
): Leave<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const fields: BlockFields<F> = blockFields(
    options.fields,
    "leave request fields",
  );

  const client: Leave<F> = {
    saveType: ({ organizationId, input }) =>
      call(
        "save_leave_type",
        {
          tenant: organizationId,
          key: input.key,
          name: input.name,
          unit: input.unit ?? "days",
          paid: input.paid ?? true,
          tracked: input.tracked ?? true,
          allowance: input.allowance ?? null,
          carryover_max: input.carryoverMax ?? null,
          color: input.color ?? null,
          ...optional("auto_approve", input.autoApprove),
        },
        (value) => typeOf(value, "save_leave_type"),
      ),
    archiveType: (typeId) =>
      call("archive_leave_type", { type_id: typeId }, (value) =>
        typeOf(value, "archive_leave_type"),
      ),
    types: ({ organizationId, ...list }) =>
      call(
        "list_leave_types",
        { tenant: organizationId, archived: list.archived ?? false },
        (value) =>
          recordsOf(value, "list_leave_types").map((row) =>
            typeOf(row, "list_leave_types"),
          ),
      ),
    request: ({ organizationId, input }) =>
      fields
        .args(input.fields)
        .andThen((checked) =>
          call(
            "request_leave",
            {
              tenant: organizationId,
              type_id: input.typeId,
              starts_on: input.startsOn.toString(),
              ends_on: (input.endsOn ?? input.startsOn).toString(),
              partial: input.partial ?? "full",
              hours: input.hours ?? null,
              note: input.note ?? null,
              ...optional("start_part", input.startPart),
              ...optional("end_part", input.endPart),
              ...optional("employee_id", input.employeeId),
              ...(checked === undefined ? {} : { fields: checked }),
            },
            (value) => requestOf(value, "request_leave"),
          ).andThen(fields.row),
        ),
    cancel: (requestId) =>
      call("cancel_leave_request", { request_id: requestId }, (value) =>
        requestOf(value, "cancel_leave_request"),
      ).andThen(fields.row),
    update: ({ requestId, update }) =>
      fields
        .args(update.fields)
        .andThen((checked) =>
          call(
            "update_leave_request",
            {
              request_id: requestId,
              starts_on: update.startsOn?.toString() ?? null,
              ends_on: update.endsOn?.toString() ?? null,
              partial: update.partial ?? null,
              hours: update.hours ?? null,
              note: update.note ?? null,
              ...optional("start_part", update.startPart),
              ...optional("end_part", update.endPart),
              ...(checked === undefined ? {} : { fields: checked }),
            },
            (value) => requestOf(value, "update_leave_request"),
          ).andThen(fields.row),
        ),
    split: ({ requestId, gap }) =>
      call(
        "split_leave_request",
        {
          request_id: requestId,
          gap_starts: gap.gapStarts.toString(),
          gap_ends: gap.gapEnds.toString(),
        },
        (value) => {
          const row = recordOf(value, "split_leave_request");

          return {
            request: requestOf(row["request"], "split_leave_request"),
            split: requestOf(row["split"], "split_leave_request"),
          };
        },
      ).andThen(({ request, split }) =>
        fields
          .row(request)
          .andThen((first) =>
            fields
              .row(split)
              .map((second) => ({ request: first, split: second })),
          ),
      ),
    decide: ({ requestId, decision }) =>
      call(
        "decide_leave_request",
        {
          request_id: requestId,
          approved: decision.approved,
          note: decision.note ?? null,
          ...(decision.decidedBy === undefined
            ? {}
            : { decided_by: decision.decidedBy }),
        },
        (value) => requestOf(value, "decide_leave_request"),
      ).andThen(fields.row),
    feed: (token) =>
      call("leave_feed", { token }, (value) => {
        if (value === null || value === undefined) {
          return null;
        }

        const row = recordOf(value, "leave_feed");

        return {
          organizationId: textOf(row["organizationId"]),
          ...optional(
            "organizationName",
            optionalText(row["organizationName"]),
          ),
          ...optional("teamId", optionalText(row["teamId"])),
          ...optional("teamName", optionalText(row["teamName"])),
          ...(row["busy"] === undefined
            ? {}
            : {
                busy: recordsOf(row["busy"], "leave_feed").map((entry) => ({
                  id: textOf(entry["id"]),
                  ...owners(entry),
                  ...optional("name", optionalText(entry["name"])),
                  startsOn: dateOf(entry["startsOn"]),
                  endsOn: dateOf(entry["endsOn"]),
                  partial: enumOrThrow(
                    entry["partial"],
                    PARTIALS,
                    "leave partial",
                  ),
                  ...optional("startPart", optionalPart(entry["startPart"])),
                  ...optional("endPart", optionalPart(entry["endPart"])),
                  updatedAt: requiredInstant(entry["updatedAt"], "updatedAt"),
                })),
              }),
          requests: recordsOf(row["requests"], "leave_feed").map((entry) => ({
            id: textOf(entry["id"]),
            ...owners(entry),
            ...optional("name", optionalText(entry["name"])),
            typeId: textOf(entry["typeId"]),
            ...optional("type", optionalText(entry["type"])),
            startsOn: dateOf(entry["startsOn"]),
            endsOn: dateOf(entry["endsOn"]),
            partial: enumOrThrow(entry["partial"], PARTIALS, "leave partial"),
            ...optional("startPart", optionalPart(entry["startPart"])),
            ...optional("endPart", optionalPart(entry["endPart"])),
            amount: decimal(entry["amount"]),
            updatedAt: requiredInstant(entry["updatedAt"], "updatedAt"),
            ...optional(
              "fields",
              isRecord(entry["fields"]) ? entry["fields"] : undefined,
            ),
          })),
        };
      }),
    list: ({ organizationId, ...list }) =>
      call(
        "list_leave_requests",
        {
          tenant: organizationId,
          user_id: list.userId ?? null,
          status: list.status ?? null,
          starts: list.from?.toString() ?? null,
          ends: list.to?.toString() ?? null,
          everyone: list.everyone ?? false,
          page_size: list.pageSize ?? null,
          ...optional("employee_id", list.employeeId),
        },
        (value) =>
          recordsOf(value, "list_leave_requests").map((row) =>
            requestOf(row, "list_leave_requests"),
          ),
      ).andThen(fields.rows),
    balances: ({ organizationId, ...list }) =>
      call(
        "leave_balances",
        {
          tenant: organizationId,
          user_id: list.userId ?? null,
          period: list.period ?? null,
          ...optional("employee_id", list.employeeId),
        },
        (value) =>
          recordsOf(value, "leave_balances").map((row) =>
            balanceOf(row, "leave_balances"),
          ),
      ),
    ledger: ({ organizationId, ...list }) =>
      call(
        "leave_ledger_entries",
        {
          tenant: organizationId,
          user_id: list.userId ?? null,
          period: list.period ?? null,
          type_id: list.typeId ?? null,
          ...optional("employee_id", list.employeeId),
        },
        (value) =>
          recordsOf(value, "leave_ledger_entries").map((row) =>
            entryOf(row, "leave_ledger_entries"),
          ),
      ),
    adjust: ({ organizationId, adjustment }) =>
      call(
        "adjust_leave_balance",
        {
          tenant: organizationId,
          user_id: adjustment.userId ?? null,
          type_id: adjustment.typeId,
          amount: adjustment.amount,
          period: adjustment.period ?? null,
          kind: adjustment.kind ?? "adjustment",
          note: adjustment.note ?? null,
          ...optional("employee_id", adjustment.employeeId),
          ...optional("expires_on", adjustment.expiresOn?.toString()),
          ...optional("effective_on", adjustment.effectiveOn?.toString()),
        },
        (value) => entryOf(value, "adjust_leave_balance"),
      ),
    accrue: ({ organizationId, accrual }) =>
      call(
        "accrue_leave",
        {
          tenant: organizationId,
          type_id: accrual.typeId,
          amount: accrual.amount ?? null,
          period: accrual.period ?? null,
          user_ids: accrual.userIds ?? null,
          idempotency_key: accrual.idempotencyKey ?? null,
          note: accrual.note ?? null,
          ...optional("employee_ids", accrual.employeeIds),
          ...optional("effective_on", accrual.effectiveOn?.toString()),
        },
        numberOf,
      ),
    closePeriod: ({ organizationId, period }) =>
      call("close_leave_year", { tenant: organizationId, period }, numberOf),
    approve: ({ requestId, note, decidedBy }) =>
      hooked.decide({
        requestId,
        decision: {
          approved: true,
          ...(note === undefined ? {} : { note }),
          ...(decidedBy === undefined ? {} : { decidedBy }),
        },
      }),
    reject: ({ requestId, note, decidedBy }) =>
      hooked.decide({
        requestId,
        decision: {
          approved: false,
          ...(note === undefined ? {} : { note }),
          ...(decidedBy === undefined ? {} : { decidedBy }),
        },
      }),
    pending: (input) => hooked.list({ ...input, status: "pending" }),
  };

  // Helpers call the hooked client, so app hooks see each step.
  const hooked: Leave<F> = withBlockHooks(client, options.hooks, {
    block: "leave",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}
