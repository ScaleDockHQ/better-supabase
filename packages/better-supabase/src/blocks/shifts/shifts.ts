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
  instantArg,
  instantOf,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  stringsOf,
  textOf,
} from "../shared.ts";

export interface ShiftsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /**
   * A Standard Schema for the shift's extra columns
   * (`blocks.shifts.options.extraColumns`), keyed by database name. It types
   * and parses them on reads, and validates them on `upsert`.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Shifts<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

/** `draft`: planners see it. `published`: members see it. */
export type ShiftStatus = "draft" | "published" | "canceled";

/**
 * `assigned`: on the shift. `requested`: asked for an open shift. `released`:
 * taken off, swapped away or turned down.
 */
export type ShiftAssignmentStatus = "assigned" | "requested" | "released";

/** `canceled`: withdrawn by the member who asked. */
export type ShiftSwapStatus = "pending" | "approved" | "rejected" | "canceled";

export type ShiftAvailabilityKind = "available" | "unavailable" | "preferred";

/** A shift pattern `generateShifts` repeats on weekdays. */
export interface ShiftTemplate {
  readonly id: string;
  readonly organizationId: string;
  readonly name: string;
  readonly teamId?: string;
  /** An asset (assets block). */
  readonly locationId?: string;
  /** `HH:MM` in the block's time zone. */
  readonly startsTime: string;
  /** `HH:MM`; at or before `startsTime` it is on the next day. */
  readonly endsTime: string;
  readonly breakMinutes: number;
  readonly headcount: number;
  /** Qualification type keys (qualifications block). */
  readonly requiredQualifications: readonly string[];
  /** ISO weekdays, 1 (Monday) to 7 (Sunday). */
  readonly weekdays: readonly number[];
  readonly archivedAt?: Temporal.Instant;
  readonly createdAt?: Temporal.Instant;
  readonly updatedAt?: Temporal.Instant;
}

export interface ShiftTemplateInput {
  readonly name: string;
  /** `HH:MM`. */
  readonly startsTime: string;
  /** `HH:MM`. */
  readonly endsTime: string;
  /** Default Monday to Friday. */
  readonly weekdays?: readonly number[];
  readonly teamId?: string;
  readonly locationId?: string;
  /** Default 0. */
  readonly breakMinutes?: number;
  /** Default 1. */
  readonly headcount?: number;
  readonly requiredQualifications?: readonly string[];
  /** Changes this template and restores it if archived. */
  readonly templateId?: string;
}

/** One shift. `F` types the extra columns. */
export interface Shift<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly templateId?: string;
  readonly teamId?: string;
  readonly locationId?: string;
  readonly startsAt: Temporal.Instant;
  readonly endsAt: Temporal.Instant;
  readonly breakMinutes: number;
  readonly headcount: number;
  readonly requiredQualifications: readonly string[];
  readonly status: ShiftStatus;
  readonly note?: string;
  readonly publishedAt?: Temporal.Instant;
  readonly canceledAt?: Temporal.Instant;
  readonly createdBy?: string;
  readonly createdAt?: Temporal.Instant;
  readonly updatedAt?: Temporal.Instant;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

export interface ShiftInput<F extends object = Record<never, never>> {
  readonly startsAt: Temporal.Instant;
  /** At most 24 hours after `startsAt`. */
  readonly endsAt: Temporal.Instant;
  readonly teamId?: string;
  readonly locationId?: string;
  readonly breakMinutes?: number;
  readonly headcount?: number;
  readonly requiredQualifications?: readonly string[];
  readonly note?: string;
  /** Changes this shift; its assignments move with it. */
  readonly shiftId?: string;
  /** The extra columns to set. */
  readonly fields?: Partial<F>;
}

/** Why an assignment went through with `qualificationCheck: "warn"`. */
export interface ShiftAssignmentWarning {
  readonly code: string;
  /** The qualification type key the member lacks. */
  readonly qualification?: string;
}

export interface ShiftAssignment {
  readonly id: string;
  readonly organizationId: string;
  readonly shiftId: string;
  readonly userId: string;
  readonly status: ShiftAssignmentStatus;
  readonly startsAt: Temporal.Instant;
  readonly endsAt: Temporal.Instant;
  readonly assignedBy?: string;
  readonly createdAt?: Temporal.Instant;
  readonly updatedAt?: Temporal.Instant;
  /** Set by `assign` and `decideRequest`. */
  readonly warnings?: readonly ShiftAssignmentWarning[];
}

export interface ShiftSwap {
  readonly id: string;
  readonly organizationId: string;
  readonly assignmentId: string;
  readonly fromUserId: string;
  readonly toUserId: string;
  readonly status: ShiftSwapStatus;
  /** An approvals request linked when the swap was decided. */
  readonly approvalId?: string;
  readonly note?: string;
  readonly decidedBy?: string;
  readonly decidedAt?: Temporal.Instant;
  readonly createdAt?: Temporal.Instant;
}

export interface ShiftAvailability {
  readonly id: string;
  readonly organizationId: string;
  readonly userId: string;
  readonly onDate: Temporal.PlainDate;
  /** `HH:MM`; missing for the whole day. */
  readonly fromTime?: string;
  readonly untilTime?: string;
  readonly kind: ShiftAvailabilityKind;
  readonly note?: string;
  readonly createdAt?: Temporal.Instant;
}

export interface ShiftAvailabilityInput {
  readonly onDate: Temporal.PlainDate;
  readonly kind: ShiftAvailabilityKind;
  /** `HH:MM`; leave both out for the whole day. */
  readonly fromTime?: string;
  readonly untilTime?: string;
  readonly note?: string;
  /** Another member; needs `shifts.write`. Default: the caller. */
  readonly userId?: string;
}

/** A shift on the roster, with its assigned and requested members. */
export interface RosterShift<
  F extends object = Record<never, never>,
> extends Shift<F> {
  readonly assignments: readonly ShiftAssignment[];
}

/** One of the caller's shifts, with their assignment on it. */
export interface MyShift<
  F extends object = Record<never, never>,
> extends Shift<F> {
  readonly assignment: ShiftAssignment;
}

/** A member's planned hours in a week, next to their contract hours. */
export interface ShiftHours {
  readonly userId: string;
  readonly shifts: number;
  readonly plannedHours: number;
  /** From the employee's contract (employees block); missing without one. */
  readonly contractHours?: number;
  readonly differenceHours?: number;
}

export interface Shifts<F extends object = Record<never, never>> {
  /** Needs `shifts.write`. */
  saveTemplate(input: {
    organizationId: string;
    input: ShiftTemplateInput;
  }): AsyncResult<ShiftTemplate>;
  /** Needs `shifts.write`. Its shifts stay. */
  archiveTemplate(templateId: string): AsyncResult<ShiftTemplate>;
  /** By name. */
  templates(
    input: { organizationId: string } & { readonly includeArchived?: boolean },
  ): AsyncResult<readonly ShiftTemplate[]>;
  /**
   * Draft shifts from a template on its weekdays, `from` to `until` (at most 92
   * days). Days that already have the template's shift are skipped. Needs
   * `shifts.write`.
   */
  generate(input: {
    organizationId: string;
    templateId: string;
    from: Temporal.PlainDate;
    until: Temporal.PlainDate;
  }): AsyncResult<readonly Shift<F>[]>;
  /** A draft shift, or a change to one. Needs `shifts.write`. */
  upsert(input: {
    organizationId: string;
    input: ShiftInput<F>;
  }): AsyncResult<Shift<F>>;
  /** Releases its assignments. Needs `shifts.manage`. */
  cancel(input: {
    shiftId: string;
    reason?: string | undefined;
  }): AsyncResult<Shift<F>>;
  /**
   * Publishes the drafts starting `from` to `until`, for one team or all;
   * returns how many. Needs `shifts.manage`.
   */
  publish(
    input: {
      organizationId: string;
      from: Temporal.PlainDate;
      until: Temporal.PlainDate;
    } & { readonly teamId?: string },
  ): AsyncResult<number>;
  /**
   * Checks overlap, approved leave, qualifications and rest first. Needs
   * `shifts.write`.
   */
  assign(input: {
    shiftId: string;
    userId: string;
  }): AsyncResult<ShiftAssignment>;
  /** Needs `shifts.write`. */
  unassign(input: {
    assignmentId: string;
    reason?: string | undefined;
  }): AsyncResult<ShiftAssignment>;
  /** Asks for a place on a published open shift. Needs `shifts.request`. */
  requestOpenShift(shiftId: string): AsyncResult<ShiftAssignment>;
  /** Needs `shifts.manage`. */
  decideRequest(input: {
    assignmentId: string;
    approve: boolean;
  }): AsyncResult<ShiftAssignment>;
  /** Offers the caller's shift to another member. */
  requestSwap(input: {
    assignmentId: string;
    toUserId: string;
    note?: string | undefined;
  }): AsyncResult<ShiftSwap>;
  /**
   * Needs `shifts.manage`, except that the member who asked may withdraw
   * (`approve: false`).
   */
  decideSwap(
    input: { swapId: string; approve: boolean } & {
      readonly approvalId?: string;
    },
  ): AsyncResult<ShiftSwap>;
  setAvailability(input: {
    organizationId: string;
    input: ShiftAvailabilityInput;
  }): AsyncResult<ShiftAvailability>;
  clearAvailability(
    input: { organizationId: string; onDate: Temporal.PlainDate } & {
      readonly userId?: string;
    },
  ): AsyncResult<void>;
  /** The caller's own, or everyone's with `shifts.write`. */
  availability(
    input: {
      organizationId: string;
      from: Temporal.PlainDate;
      until: Temporal.PlainDate;
    } & { readonly userId?: string },
  ): AsyncResult<readonly ShiftAvailability[]>;
  /** Members see published shifts; planners also drafts. */
  roster(
    input: {
      organizationId: string;
      from: Temporal.PlainDate;
      until: Temporal.PlainDate;
    } & { readonly teamId?: string },
  ): AsyncResult<readonly RosterShift<F>[]>;
  /** Default: the next 30 days. */
  myShifts(options?: {
    readonly since?: Temporal.Instant;
    readonly until?: Temporal.Instant;
  }): AsyncResult<readonly MyShift<F>[]>;
  /** The week from `weekStart`. Needs `shifts.manage`. */
  hours(input: {
    organizationId: string;
    weekStart: Temporal.PlainDate;
  }): AsyncResult<readonly ShiftHours[]>;
  /**
   * Time entries for assigned shifts that ended (time-tracking block); returns
   * how many. Service role only.
   */
  toTimeEntries(
    input: { organizationId: string } & { readonly until?: Temporal.Instant },
  ): AsyncResult<number>;
}

const SHIFT_STATUSES: readonly ShiftStatus[] = [
  "draft",
  "published",
  "canceled",
];

const ASSIGNMENT_STATUSES: readonly ShiftAssignmentStatus[] = [
  "assigned",
  "requested",
  "released",
];

const SWAP_STATUSES: readonly ShiftSwapStatus[] = [
  "pending",
  "approved",
  "rejected",
  "canceled",
];

const AVAILABILITY_KINDS: readonly ShiftAvailabilityKind[] = [
  "available",
  "unavailable",
  "preferred",
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

const numberOf = (value: unknown): number =>
  typeof value === "number" ? value : Number(value ?? 0);

const optionalNumber = (value: unknown): number | undefined =>
  value === null || value === undefined ? undefined : numberOf(value);

const dateOf = (value: unknown): Temporal.PlainDate =>
  temporal().PlainDate.from(textOf(value));

function templateOf(value: unknown, fn: string): ShiftTemplate {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    name: textOf(row["name"]),
    startsTime: textOf(row["startsTime"]),
    endsTime: textOf(row["endsTime"]),
    breakMinutes: numberOf(row["breakMinutes"]),
    headcount: numberOf(row["headcount"]),
    requiredQualifications: stringsOf(row["requiredQualifications"]),
    weekdays: Array.isArray(row["weekdays"])
      ? row["weekdays"].map(numberOf)
      : [],
    ...optional("teamId", optionalText(row["teamId"])),
    ...optional("locationId", optionalText(row["locationId"])),
    ...optional("archivedAt", optionalInstant(row["archivedAt"])),
    ...optional("createdAt", optionalInstant(row["createdAt"])),
    ...optional("updatedAt", optionalInstant(row["updatedAt"])),
  };
}

function shiftOf(value: unknown, fn: string): Shift {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    startsAt: instantOf(row["startsAt"]),
    endsAt: instantOf(row["endsAt"]),
    breakMinutes: numberOf(row["breakMinutes"]),
    headcount: numberOf(row["headcount"]),
    requiredQualifications: stringsOf(row["requiredQualifications"]),
    status: enumOrThrow(row["status"], SHIFT_STATUSES, "shift status"),
    ...optional("templateId", optionalText(row["templateId"])),
    ...optional("teamId", optionalText(row["teamId"])),
    ...optional("locationId", optionalText(row["locationId"])),
    ...optional("note", optionalText(row["note"])),
    ...optional("publishedAt", optionalInstant(row["publishedAt"])),
    ...optional("canceledAt", optionalInstant(row["canceledAt"])),
    ...optional("createdBy", optionalText(row["createdBy"])),
    ...optional("createdAt", optionalInstant(row["createdAt"])),
    ...optional("updatedAt", optionalInstant(row["updatedAt"])),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
  };
}

function warningsOf(value: unknown): readonly ShiftAssignmentWarning[] {
  return Array.isArray(value)
    ? value
        .filter(isRecord)
        .map((row) => ({
          code: textOf(row["code"]),
          ...optional("qualification", optionalText(row["qualification"])),
        }))
    : [];
}

function assignmentOf(value: unknown, fn: string): ShiftAssignment {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    shiftId: textOf(row["shiftId"]),
    userId: textOf(row["userId"]),
    status: enumOrThrow(
      row["status"],
      ASSIGNMENT_STATUSES,
      "shift assignment status",
    ),
    startsAt: instantOf(row["startsAt"]),
    endsAt: instantOf(row["endsAt"]),
    ...optional("assignedBy", optionalText(row["assignedBy"])),
    ...optional("createdAt", optionalInstant(row["createdAt"])),
    ...optional("updatedAt", optionalInstant(row["updatedAt"])),
    ...optional(
      "warnings",
      row["warnings"] === undefined ? undefined : warningsOf(row["warnings"]),
    ),
  };
}

function swapOf(value: unknown, fn: string): ShiftSwap {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    assignmentId: textOf(row["assignmentId"]),
    fromUserId: textOf(row["fromUserId"]),
    toUserId: textOf(row["toUserId"]),
    status: enumOrThrow(row["status"], SWAP_STATUSES, "shift swap status"),
    ...optional("approvalId", optionalText(row["approvalId"])),
    ...optional("note", optionalText(row["note"])),
    ...optional("decidedBy", optionalText(row["decidedBy"])),
    ...optional("decidedAt", optionalInstant(row["decidedAt"])),
    ...optional("createdAt", optionalInstant(row["createdAt"])),
  };
}

function availabilityOf(value: unknown, fn: string): ShiftAvailability {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    userId: textOf(row["userId"]),
    onDate: dateOf(row["onDate"]),
    kind: enumOrThrow(row["kind"], AVAILABILITY_KINDS, "availability kind"),
    ...optional("fromTime", optionalText(row["fromTime"])),
    ...optional("untilTime", optionalText(row["untilTime"])),
    ...optional("note", optionalText(row["note"])),
    ...optional("createdAt", optionalInstant(row["createdAt"])),
  };
}

function rosterShiftOf(value: unknown, fn: string): RosterShift {
  const row = recordOf(value, fn);

  return {
    ...shiftOf(row, fn),
    assignments: recordsOf(row["assignments"] ?? [], fn).map((item) =>
      assignmentOf(item, fn),
    ),
  };
}

function myShiftOf(value: unknown, fn: string): MyShift {
  const row = recordOf(value, fn);

  return {
    ...shiftOf(row, fn),
    assignment: assignmentOf(row["assignment"], fn),
  };
}

function hoursOf(value: unknown, fn: string): ShiftHours {
  const row = recordOf(value, fn);

  return {
    userId: textOf(row["userId"]),
    shifts: numberOf(row["shifts"]),
    plannedHours: numberOf(row["plannedHours"]),
    ...optional("contractHours", optionalNumber(row["contractHours"])),
    ...optional("differenceHours", optionalNumber(row["differenceHours"])),
  };
}

const many =
  <T>(fn: string, of: (value: unknown, fn: string) => T) =>
  (value: unknown): readonly T[] =>
    recordsOf(value, fn).map((row) => of(row, fn));

const one =
  <T>(fn: string, of: (value: unknown, fn: string) => T) =>
  (value: unknown): T =>
    of(value, fn);

/** The `shifts` SQL module as typed calls. */
export function createShifts<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: ShiftsOptions<S>): Shifts<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(options.fields, "shift fields");

  const client: Shifts<F> = {
    saveTemplate: ({ organizationId, input }) =>
      call(
        "save_shift_template",
        {
          tenant: organizationId,
          name: input.name,
          starts_time: input.startsTime,
          ends_time: input.endsTime,
          ...optional("weekdays", input.weekdays),
          team_id: input.teamId ?? null,
          location_id: input.locationId ?? null,
          break_minutes: input.breakMinutes ?? 0,
          headcount: input.headcount ?? 1,
          required_qualifications: input.requiredQualifications ?? [],
          template_id: input.templateId ?? null,
        },
        one("save_shift_template", templateOf),
      ),
    archiveTemplate: (templateId) =>
      call(
        "archive_shift_template",
        { template_id: templateId },
        one("archive_shift_template", templateOf),
      ),
    templates: ({ organizationId, ...list }) =>
      call(
        "list_shift_templates",
        {
          tenant: organizationId,
          include_archived: list.includeArchived ?? false,
        },
        many("list_shift_templates", templateOf),
      ),
    generate: ({ organizationId, templateId, from, until }) =>
      call(
        "generate_shifts",
        {
          tenant: organizationId,
          template_id: templateId,
          from_date: from.toString(),
          until_date: until.toString(),
        },
        many("generate_shifts", shiftOf),
      ).andThen(fields.rows),
    upsert: ({ organizationId, input }) =>
      fields
        .args(input.fields)
        .andThen((checked) =>
          call(
            "save_shift",
            {
              tenant: organizationId,
              starts_at: instantArg(input.startsAt),
              ends_at: instantArg(input.endsAt),
              team_id: input.teamId ?? null,
              location_id: input.locationId ?? null,
              break_minutes: input.breakMinutes ?? 0,
              headcount: input.headcount ?? 1,
              required_qualifications: input.requiredQualifications ?? [],
              note: input.note ?? null,
              shift_id: input.shiftId ?? null,
              ...(checked === undefined ? {} : { fields: checked }),
            },
            one("save_shift", shiftOf),
          ).andThen(fields.row),
        ),
    cancel: ({ shiftId, reason }) =>
      call(
        "cancel_shift",
        { shift_id: shiftId, reason: reason ?? null },
        one("cancel_shift", shiftOf),
      ).andThen(fields.row),
    publish: ({ organizationId, from, until, ...list }) =>
      call(
        "publish_shifts",
        {
          tenant: organizationId,
          from_date: from.toString(),
          until_date: until.toString(),
          team_id: list.teamId ?? null,
        },
        numberOf,
      ),
    assign: ({ shiftId, userId }) =>
      call(
        "assign_shift",
        { shift_id: shiftId, user_id: userId },
        one("assign_shift", assignmentOf),
      ),
    unassign: ({ assignmentId, reason }) =>
      call(
        "unassign_shift",
        { assignment_id: assignmentId, reason: reason ?? null },
        one("unassign_shift", assignmentOf),
      ),
    requestOpenShift: (shiftId) =>
      call(
        "request_open_shift",
        { shift_id: shiftId },
        one("request_open_shift", assignmentOf),
      ),
    decideRequest: ({ assignmentId, approve }) =>
      call(
        "decide_shift_request",
        { assignment_id: assignmentId, approve },
        one("decide_shift_request", assignmentOf),
      ),
    requestSwap: ({ assignmentId, toUserId, note }) =>
      call(
        "request_shift_swap",
        {
          assignment_id: assignmentId,
          to_user_id: toUserId,
          note: note ?? null,
        },
        one("request_shift_swap", swapOf),
      ),
    decideSwap: ({ swapId, approve, ...decide }) =>
      call(
        "decide_shift_swap",
        { swap_id: swapId, approve, approval_id: decide.approvalId ?? null },
        one("decide_shift_swap", swapOf),
      ),
    setAvailability: ({ organizationId, input }) =>
      call(
        "set_shift_availability",
        {
          tenant: organizationId,
          on_date: input.onDate.toString(),
          kind: input.kind,
          from_time: input.fromTime ?? null,
          until_time: input.untilTime ?? null,
          note: input.note ?? null,
          user_id: input.userId ?? null,
        },
        one("set_shift_availability", availabilityOf),
      ),
    clearAvailability: ({ organizationId, onDate, ...clear }) =>
      call(
        "set_shift_availability",
        {
          tenant: organizationId,
          on_date: onDate.toString(),
          kind: null,
          user_id: clear.userId ?? null,
        },
        () => undefined,
      ),
    availability: ({ organizationId, from, until, ...list }) =>
      call(
        "list_shift_availability",
        {
          tenant: organizationId,
          from_date: from.toString(),
          until_date: until.toString(),
          user_id: list.userId ?? null,
        },
        many("list_shift_availability", availabilityOf),
      ),
    roster: ({ organizationId, from, until, ...list }) =>
      call(
        "roster",
        {
          tenant: organizationId,
          from_date: from.toString(),
          until_date: until.toString(),
          team_id: list.teamId ?? null,
        },
        many("roster", rosterShiftOf),
      ).andThen(fields.rows),
    myShifts: (list = {}) =>
      call(
        "my_shifts",
        {
          ...optional("since", instantArg(list.since)),
          ...optional("until", instantArg(list.until)),
        },
        many("my_shifts", myShiftOf),
      ).andThen(fields.rows),
    hours: ({ organizationId, weekStart }) =>
      call(
        "shift_hours",
        { tenant: organizationId, week_start: weekStart.toString() },
        many("shift_hours", hoursOf),
      ),
    toTimeEntries: ({ organizationId, ...list }) =>
      call(
        "shifts_to_time_entries",
        {
          tenant: organizationId,
          ...optional("until", instantArg(list.until)),
        },
        numberOf,
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "shifts",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
