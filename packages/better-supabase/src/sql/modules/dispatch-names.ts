import type { DispatchEvents } from "../../blocks/dispatch/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";

import { extraFieldsArg } from "../shared.ts";

const WORK_ORDER_PAYLOAD = ["organizationId", "id"] as const;

const EVENTS: BlockSqlEvents<DispatchEvents> = {
  "work_order.created": {
    subject: "work-orders",
    payload: [
      ...WORK_ORDER_PAYLOAD,
      "status",
      "technicianId",
      "subjectType",
      "subjectId",
    ],
  },
  "work_order.updated": { subject: "work-orders", payload: WORK_ORDER_PAYLOAD },
  "work_order.scheduled": {
    subject: "work-orders",
    payload: [...WORK_ORDER_PAYLOAD, "technicianId", "startsAt", "endsAt"],
  },
  "work_order.unscheduled": {
    subject: "work-orders",
    payload: [...WORK_ORDER_PAYLOAD, "technicianId"],
  },
  "work_order.status_changed": {
    subject: "work-orders",
    payload: [...WORK_ORDER_PAYLOAD, "from", "to", "technicianId"],
  },
  "work_order.part_used": {
    subject: "work-orders",
    payload: [
      ...WORK_ORDER_PAYLOAD,
      "partId",
      "assetId",
      "variantId",
      "quantity",
    ],
  },
  "dispatch_route.planned": {
    subject: "dispatch-routes",
    payload: ["organizationId", "id", "technicianId", "routeDate", "stops"],
  },
};

/** The dispatch module's tables, entities and events. */
export const DISPATCH_NAMES: BlockSqlNames = {
  entities: {
    work_order: {
      table: "workOrders",
      singular: "work_order",
      primary: true,
      subject: {
        title: "title",
        permissions: { read: "read", write: "manage" },
      },
    },
    dispatch_route: { table: "routes", singular: "dispatch_route" },
    work_order_part: { table: "parts", singular: "work_order_part" },
  },
  events: EVENTS,
  options: ["extraColumns", "timeZone", "defaultDuration"],
  tables: {
    workOrders: {
      name: "work_orders",
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        title: "title",
        description: "description",
        priority: "priority",
        status: "status",
        technician: "technician_id",
        startsAt: "starts_at",
        endsAt: "ends_at",
        location: "location_id",
        asset: "asset_id",
        booking: "booking_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        address: "address",
        enRouteAt: "en_route_at",
        arrivedAt: "arrived_at",
        completedAt: "completed_at",
        cancelledAt: "cancelled_at",
        cancelReason: "cancel_reason",
        completionNote: "completion_note",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    routes: {
      name: "dispatch_routes",
      lifecycle: { tenant: "tenant", user: "technician", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        technician: "technician_id",
        routeDate: "route_date",
        plannedBy: "planned_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    stops: {
      name: "dispatch_route_stops",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        route: "route_id",
        workOrder: "work_order_id",
        position: "position",
      },
    },
    parts: {
      name: "work_order_parts",
      lifecycle: { tenant: "tenant", user: "recordedBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        workOrder: "work_order_id",
        name: "name",
        quantity: "quantity",
        unit: "unit",
        asset: "asset_id",
        variant: "variant_id",
        location: "location_id",
        recordedBy: "recorded_by",
        createdAt: "created_at",
      },
    },
  },
};

/** The dispatch module's function signatures. */
export function dispatchContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  const fields = extraFieldsArg(
    ctx.extraColumns("workOrders", ["fields", "day"]),
  );

  return [
    {
      name: "create_work_order",
      args: [
        "{id}",
        "text",
        "text",
        "text",
        "uuid",
        "uuid",
        "uuid",
        "text",
        "text",
        "text",
        "uuid",
        "timestamptz",
        "timestamptz",
        ...fields.contract,
      ],
      returns: "jsonb",
    },
    {
      name: "update_work_order",
      args: [
        "uuid",
        "text",
        "text",
        "text",
        "uuid",
        "uuid",
        "text",
        ...fields.contract,
      ],
      returns: "jsonb",
    },
    {
      name: "schedule_work_order",
      args: ["uuid", "uuid", "timestamptz", "timestamptz"],
      returns: "jsonb",
    },
    { name: "unschedule_work_order", args: ["uuid"], returns: "jsonb" },
    {
      name: "set_work_order_status",
      args: ["uuid", "text", "text"],
      returns: "jsonb",
    },
    { name: "get_work_order", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_work_orders",
      args: [
        "{id}",
        "text",
        "uuid",
        "text",
        "text",
        "timestamptz",
        "timestamptz",
        "timestamptz",
        "integer",
      ],
      returns: "jsonb",
    },
    {
      name: "dispatch_board",
      args: ["{id}", "date", "date", "uuid[]"],
      returns: "jsonb",
    },
    {
      name: "technician_day",
      args: ["{id}", "date", "uuid"],
      returns: "jsonb",
    },
    {
      name: "plan_dispatch_route",
      args: ["{id}", "uuid", "date", "uuid[]"],
      returns: "jsonb",
    },
    {
      name: "record_work_order_part",
      args: ["uuid", "text", "numeric", "text", "uuid", "uuid", "uuid"],
      returns: "jsonb",
    },
    { name: "list_work_order_parts", args: ["uuid"], returns: "jsonb" },
    { name: "remove_work_order_part", args: ["uuid"], returns: "boolean" },
  ];
}
