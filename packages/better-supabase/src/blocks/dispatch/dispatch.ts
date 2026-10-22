import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { SubjectRef } from "../../schema/types.ts";
import type { BlockOptions } from "../shared.ts";
import type { WorkOrderPriority, WorkOrderStatus } from "./statuses.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { optionalSubjectRefOf } from "../../core/block-subjects.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { AsyncResult } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
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
  stringsOf,
  textOf,
} from "../shared.ts";
import { WORK_ORDER_PRIORITIES, WORK_ORDER_STATUSES } from "./statuses.ts";

export interface DispatchOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockOptions {
  /**
   * A Standard Schema for the work orders' extra columns
   * (`blocks.dispatch.options.extraColumns`), keyed by database name. It types
   * and parses them on reads and validates them on writes.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Dispatch<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

/** A job at a place, for an asset or a record, in a technician's slot. */
export interface WorkOrder<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly title: string;
  readonly description?: string;
  readonly priority: WorkOrderPriority;
  readonly status: WorkOrderStatus;
  readonly technicianId?: string;
  readonly startsAt?: Temporal.Instant;
  readonly endsAt?: Temporal.Instant;
  /** The day it starts, in the block's `timeZone`. */
  readonly day?: Temporal.PlainDate;
  /** An assets location. */
  readonly locationId?: string;
  readonly assetId?: string;
  /** The booking its slot came from. */
  readonly bookingId?: string;
  readonly subject?: SubjectRef;
  /** A free-text address, for a place that isn't an assets location. */
  readonly address?: string;
  readonly enRouteAt?: Temporal.Instant;
  readonly arrivedAt?: Temporal.Instant;
  readonly completedAt?: Temporal.Instant;
  readonly cancelledAt?: Temporal.Instant;
  readonly cancelReason?: string;
  readonly completionNote?: string;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

export interface WorkOrderInput<F extends object = Record<never, never>> {
  readonly title: string;
  readonly description?: string;
  /** Default `normal`. */
  readonly priority?: WorkOrderPriority;
  readonly locationId?: string;
  readonly assetId?: string;
  /** Takes the slot from the booking when `startsAt` is unset. */
  readonly bookingId?: string;
  /** The record the job is for, registered in `config.subjects`. */
  readonly subject?: SubjectRef;
  readonly address?: string;
  /** With `startsAt` (or a booking), the work order is scheduled at once. */
  readonly technicianId?: string;
  readonly startsAt?: Temporal.Instant;
  /** Defaults to `startsAt` plus the block's `defaultDuration`. */
  readonly endsAt?: Temporal.Instant;
  /** The extra columns. */
  readonly fields?: Partial<F>;
}

/** What to change; unset keeps a value. */
export interface WorkOrderPatch<F extends object = Record<never, never>> {
  readonly title?: string;
  readonly description?: string;
  readonly priority?: WorkOrderPriority;
  readonly locationId?: string;
  readonly assetId?: string;
  readonly address?: string;
  readonly fields?: Partial<F>;
}

export interface WorkOrderSlot {
  readonly technicianId: string;
  readonly startsAt: Temporal.Instant;
  /** Defaults to `startsAt` plus the block's `defaultDuration`. */
  readonly endsAt?: Temporal.Instant;
}

/** The statuses `setStatus` moves a work order to. */
export type WorkOrderTransition = Extract<
  WorkOrderStatus,
  "en_route" | "on_site" | "done" | "cancelled"
>;

export interface WorkOrderListOptions {
  readonly status?: WorkOrderStatus;
  readonly technicianId?: string;
  readonly subject?: SubjectRef;
  /** Work orders whose slot ends after this. */
  readonly from?: Temporal.Instant;
  /** Work orders whose slot starts before this. */
  readonly until?: Temporal.Instant;
  /** Work orders created before this, for the next page. */
  readonly before?: Temporal.Instant;
  /** Default 50, at most 500. */
  readonly limit?: number;
}

export interface DispatchBoardOptions {
  readonly from: Temporal.PlainDate;
  /** Inclusive; at most 31 days after `from`. */
  readonly to: Temporal.PlainDate;
  /**
   * The board's rows, such as the members holding `dispatch.work`. Unset: the
   * technicians with work orders in the range.
   */
  readonly technicianIds?: readonly string[];
}

/** The schedule board: technicians by day, and the unscheduled backlog. */
export interface DispatchBoard<F extends object = Record<never, never>> {
  readonly from: Temporal.PlainDate;
  readonly to: Temporal.PlainDate;
  /** The zone `day` is computed in. */
  readonly timeZone: string;
  readonly technicianIds: readonly string[];
  /** The scheduled and worked orders in the range, by start. */
  readonly scheduled: readonly WorkOrder<F>[];
  /** Unscheduled work orders, most urgent first. */
  readonly backlog: readonly WorkOrder<F>[];
}

export interface TechnicianStop<F extends object = Record<never, never>> {
  /** From 1. */
  readonly position: number;
  readonly workOrder: WorkOrder<F>;
}

/** A technician's day: the route's stops in order, then the rest by start. */
export interface TechnicianDay<F extends object = Record<never, never>> {
  readonly technicianId: string;
  readonly date: Temporal.PlainDate;
  /** Set once the day has a planned route. */
  readonly routeId?: string;
  readonly stops: readonly TechnicianStop<F>[];
}

export interface DispatchRoute {
  readonly id: string;
  readonly organizationId: string;
  readonly technicianId: string;
  readonly routeDate: Temporal.PlainDate;
  /** In driving order. */
  readonly workOrderIds: readonly string[];
}

/** A part a job used. */
export interface WorkOrderPart {
  readonly id: string;
  readonly organizationId: string;
  readonly workOrderId: string;
  readonly name: string;
  /** A decimal string, such as `"2"` or `"1.5"`. */
  readonly quantity: string;
  readonly unit?: string;
  readonly assetId?: string;
  /** A catalog variant. */
  readonly variantId?: string;
  /** The inventory location it was taken from. */
  readonly locationId?: string;
  readonly recordedBy?: string;
  readonly createdAt: Temporal.Instant;
}

export interface WorkOrderPartInput {
  readonly name: string;
  /** A decimal above zero with at most three places. */
  readonly quantity: string | number;
  readonly unit?: string;
  /** Needs the assets block. */
  readonly assetId?: string;
  /** Needs the catalog block. */
  readonly variantId?: string;
  /** Needs the inventory block. */
  readonly locationId?: string;
}

/**
 * Field service dispatch. `F` is the extra fields `options.fields` describes.
 * Methods that take no work order id act in the block's `tenant`.
 */
export interface Dispatch<F extends object = Record<never, never>> {
  create(input: WorkOrderInput<F>): AsyncResult<WorkOrder<F>>;
  update(id: string, patch: WorkOrderPatch<F>): AsyncResult<WorkOrder<F>>;
  /**
   * Puts the work order in a technician's slot: `DISPATCH_SLOT_TAKEN` when the
   * technician already has work then.
   */
  schedule(id: string, slot: WorkOrderSlot): AsyncResult<WorkOrder<F>>;
  /** Sends a scheduled work order back to the backlog. */
  unschedule(id: string): AsyncResult<WorkOrder<F>>;
  /**
   * Moves the work order on: `en_route`, `on_site`, `done` (with an optional
   * completion note) or `cancelled` (with an optional reason). The assigned
   * technician moves their own work orders with `dispatch.work`; cancelling
   * needs `dispatch.manage`.
   */
  setStatus(
    id: string,
    status: WorkOrderTransition,
    note?: string,
  ): AsyncResult<WorkOrder<F>>;
  /** `null` when it doesn't exist or the caller can't read it. */
  get(id: string): AsyncResult<WorkOrder<F> | null>;
  list(options?: WorkOrderListOptions): AsyncResult<readonly WorkOrder<F>[]>;
  board(options: DispatchBoardOptions): AsyncResult<DispatchBoard<F>>;
  /** The technician's day plan; `technicianId` defaults to the caller. */
  technicianDay(
    day: Temporal.PlainDate,
    technicianId?: string,
  ): AsyncResult<TechnicianDay<F>>;
  /** Replaces the technician's route for the day with these stops, in order. */
  planRoute(
    technicianId: string,
    day: Temporal.PlainDate,
    workOrderIds: readonly string[],
  ): AsyncResult<DispatchRoute>;
  recordPart(
    workOrderId: string,
    input: WorkOrderPartInput,
  ): AsyncResult<WorkOrderPart>;
  parts(workOrderId: string): AsyncResult<readonly WorkOrderPart[]>;
  /** `false` when the part was already gone. */
  removePart(partId: string): AsyncResult<boolean>;
}

const dateOf = (value: unknown): Temporal.PlainDate =>
  temporal().PlainDate.from(textOf(value));

type Defined<T> = { [K in keyof T]?: Exclude<T[K], undefined> };

/** Copies the defined values only, so absent fields stay absent. */
function defined<T extends object>(values: T): Defined<T> {
  // SAFETY: the entries come from `values`, minus the undefined ones.
  return Object.fromEntries(
    Object.entries(values).filter(([, value]) => value !== undefined),
  ) as Defined<T>;
}

function workOrderOf(value: unknown, fn: string): WorkOrder {
  const row = recordOf(value, fn);
  const subject = optionalSubjectRefOf(row["subjectType"], row["subjectId"]);
  const day = optionalText(row["day"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    title: textOf(row["title"]),
    priority: enumOrThrow(row["priority"], WORK_ORDER_PRIORITIES, "priority"),
    status: enumOrThrow(row["status"], WORK_ORDER_STATUSES, "status"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
    ...defined({
      description: optionalText(row["description"]),
      technicianId: optionalText(row["technicianId"]),
      startsAt: optionalInstant(row["startsAt"]),
      endsAt: optionalInstant(row["endsAt"]),
      day: day === undefined ? undefined : dateOf(day),
      locationId: optionalText(row["locationId"]),
      assetId: optionalText(row["assetId"]),
      bookingId: optionalText(row["bookingId"]),
      subject,
      address: optionalText(row["address"]),
      enRouteAt: optionalInstant(row["enRouteAt"]),
      arrivedAt: optionalInstant(row["arrivedAt"]),
      completedAt: optionalInstant(row["completedAt"]),
      cancelledAt: optionalInstant(row["cancelledAt"]),
      cancelReason: optionalText(row["cancelReason"]),
      completionNote: optionalText(row["completionNote"]),
      createdBy: optionalText(row["createdBy"]),
    }),
  };
}

function partOf(value: unknown, fn: string): WorkOrderPart {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    workOrderId: textOf(row["workOrderId"]),
    name: textOf(row["name"]),
    quantity: textOf(row["quantity"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...defined({
      unit: optionalText(row["unit"]),
      assetId: optionalText(row["assetId"]),
      variantId: optionalText(row["variantId"]),
      locationId: optionalText(row["locationId"]),
      recordedBy: optionalText(row["recordedBy"]),
    }),
  };
}

const workOrdersOf = (value: unknown, fn: string): WorkOrder[] =>
  recordsOf(value, fn).map((row) => workOrderOf(row, fn));

/** The `dispatch` SQL module as typed calls. */
export function createDispatch<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: DispatchOptions<S>): Dispatch<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const fields: BlockFields<F> = blockFields(
    options.fields,
    "work order fields",
  );

  const one =
    (fn: string) =>
    (value: unknown): WorkOrder =>
      workOrderOf(value, fn);

  const client: Dispatch<F> = {
    create: (input) =>
      tenant().andThen((organizationId) =>
        fields
          .args(input.fields)
          .andThen((checked) =>
            call(
              "create_work_order",
              {
                tenant: organizationId,
                title: input.title,
                description: input.description ?? null,
                priority: input.priority ?? "normal",
                location_id: input.locationId ?? null,
                asset_id: input.assetId ?? null,
                booking_id: input.bookingId ?? null,
                subject_type: input.subject?.type ?? null,
                subject_id: input.subject?.id ?? null,
                address: input.address ?? null,
                technician: input.technicianId ?? null,
                starts_at: instantArg(input.startsAt) ?? null,
                ends_at: instantArg(input.endsAt) ?? null,
                fields: checked,
              },
              one("create_work_order"),
            ).andThen(fields.row),
          ),
      ),
    update: (id, patch) =>
      fields
        .args(patch.fields)
        .andThen((checked) =>
          call(
            "update_work_order",
            {
              work_order_id: id,
              title: patch.title ?? null,
              description: patch.description ?? null,
              priority: patch.priority ?? null,
              location_id: patch.locationId ?? null,
              asset_id: patch.assetId ?? null,
              address: patch.address ?? null,
              fields: checked,
            },
            one("update_work_order"),
          ).andThen(fields.row),
        ),
    schedule: (id, slot) =>
      call(
        "schedule_work_order",
        {
          work_order_id: id,
          technician: slot.technicianId,
          starts_at: instantArg(slot.startsAt),
          ends_at: instantArg(slot.endsAt) ?? null,
        },
        one("schedule_work_order"),
      ).andThen(fields.row),
    unschedule: (id) =>
      call(
        "unschedule_work_order",
        { work_order_id: id },
        one("unschedule_work_order"),
      ).andThen(fields.row),
    setStatus: (id, status, note) =>
      call(
        "set_work_order_status",
        { work_order_id: id, status, note: note ?? null },
        one("set_work_order_status"),
      ).andThen(fields.row),
    get: (id) =>
      call("get_work_order", { work_order_id: id }, (value) =>
        value === null || value === undefined
          ? null
          : workOrderOf(value, "get_work_order"),
      ).andThen((found) =>
        found === null ? AsyncResult.ok(null) : fields.row(found),
      ),
    list: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_work_orders",
          {
            tenant: organizationId,
            status: list.status ?? null,
            technician: list.technicianId ?? null,
            subject_type: list.subject?.type ?? null,
            subject_id: list.subject?.id ?? null,
            from_at: instantArg(list.from) ?? null,
            until_at: instantArg(list.until) ?? null,
            before: instantArg(list.before) ?? null,
            page_size: list.limit ?? 50,
          },
          (value) => workOrdersOf(value, "list_work_orders"),
        ).andThen(fields.rows),
      ),
    board: (board) =>
      tenant().andThen((organizationId) =>
        call(
          "dispatch_board",
          {
            tenant: organizationId,
            from_date: board.from.toString(),
            to_date: board.to.toString(),
            technicians:
              board.technicianIds === undefined
                ? null
                : [...board.technicianIds],
          },
          (value) => {
            const row = recordOf(value, "dispatch_board");

            return {
              from: dateOf(row["from"]),
              to: dateOf(row["to"]),
              timeZone: textOf(row["timeZone"]),
              technicianIds: stringsOf(row["technicianIds"]),
              scheduled: workOrdersOf(row["scheduled"], "dispatch_board"),
              backlog: workOrdersOf(row["backlog"], "dispatch_board"),
            };
          },
        ).andThen((found) =>
          fields
            .rows(found.scheduled)
            .andThen((scheduled) =>
              fields
                .rows(found.backlog)
                .map((backlog) => ({ ...found, scheduled, backlog })),
            ),
        ),
      ),
    technicianDay: (day, technicianId) =>
      tenant().andThen((organizationId) =>
        call(
          "technician_day",
          {
            tenant: organizationId,
            day: day.toString(),
            technician: technicianId ?? null,
          },
          (value) => {
            const row = recordOf(value, "technician_day");
            const routeId = optionalText(row["routeId"]);

            return {
              technicianId: textOf(row["technicianId"]),
              date: dateOf(row["date"]),
              ...(routeId === undefined ? {} : { routeId }),
              stops: recordsOf(row["stops"], "technician_day").map((stop) => ({
                position: Number(stop["position"]),
                workOrder: workOrderOf(stop["workOrder"], "technician_day"),
              })),
            };
          },
        ).andThen((found) =>
          fields
            .rows(found.stops.map((stop) => stop.workOrder))
            .map((orders) => ({
              ...found,
              stops: found.stops.map((stop, index) => ({
                position: stop.position,
                // SAFETY: `rows` keeps one parsed row per input row, in order.
                workOrder: orders[index] as WorkOrder<F>,
              })),
            })),
        ),
      ),
    planRoute: (technicianId, day, workOrderIds) =>
      tenant().andThen((organizationId) =>
        call(
          "plan_dispatch_route",
          {
            tenant: organizationId,
            technician: technicianId,
            route_date: day.toString(),
            work_orders: [...workOrderIds],
          },
          (value) => {
            const row = recordOf(value, "plan_dispatch_route");

            return {
              id: textOf(row["id"]),
              organizationId: textOf(row["organizationId"]),
              technicianId: textOf(row["technicianId"]),
              routeDate: dateOf(row["routeDate"]),
              workOrderIds: stringsOf(row["stops"]),
            };
          },
        ),
      ),
    recordPart: (workOrderId, input) =>
      call(
        "record_work_order_part",
        {
          work_order_id: workOrderId,
          name: input.name,
          quantity: String(input.quantity),
          unit: input.unit ?? null,
          asset_id: input.assetId ?? null,
          variant_id: input.variantId ?? null,
          location_id: input.locationId ?? null,
        },
        (value) => partOf(value, "record_work_order_part"),
      ),
    parts: (workOrderId) =>
      call("list_work_order_parts", { work_order_id: workOrderId }, (value) =>
        recordsOf(value, "list_work_order_parts").map((row) =>
          partOf(row, "list_work_order_parts"),
        ),
      ),
    removePart: (partId) =>
      call(
        "remove_work_order_part",
        { part_id: partId },
        (value) => value === true,
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "dispatch",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
