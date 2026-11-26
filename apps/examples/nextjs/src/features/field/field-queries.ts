import "server-only";
import type {
  WorkOrderPriority,
  WorkOrderStatus,
} from "better-supabase/blocks/dispatch";
import type {
  ShipmentStatus,
  TrackingStatus,
} from "better-supabase/blocks/shipments";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";
import { Temporal } from "temporal-polyfill";

import { readMembers } from "@/features/organization/organization-queries";
import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

/** One work order as the board and the day plan show it. */
export interface WorkOrderCard {
  readonly id: string;
  readonly title: string;
  readonly status: WorkOrderStatus;
  readonly priority: WorkOrderPriority;
  readonly startsAt: string | null;
  readonly endsAt: string | null;
  readonly address: string | null;
}

export interface BoardRow {
  readonly technicianId: string;
  readonly name: string;
  /** The week's days, Monday first, each with its work orders. */
  readonly days: readonly {
    readonly date: string;
    readonly orders: readonly WorkOrderCard[];
  }[];
}

export interface DispatchWeek {
  readonly days: readonly string[];
  readonly timeZone: string;
  readonly rows: readonly BoardRow[];
  readonly backlog: readonly WorkOrderCard[];
}

export interface TechnicianStopCard {
  readonly position: number;
  readonly workOrder: WorkOrderCard;
}

export interface TechnicianDayPlan {
  readonly date: string;
  readonly planned: boolean;
  readonly stops: readonly TechnicianStopCard[];
}

export interface ShipmentRow {
  readonly id: string;
  readonly reference: string;
  readonly status: ShipmentStatus;
  readonly recipient: string;
  readonly destination: string;
  readonly carrier: string | null;
  readonly trackingNumber: string | null;
  readonly updatedAt: string;
}

export interface TrackingStep {
  readonly id: string;
  readonly status: TrackingStatus;
  readonly occurredAt: string;
  readonly description: string | null;
  readonly location: string | null;
}

export interface ShipmentTracking {
  readonly shipments: readonly ShipmentRow[];
  readonly selected: ShipmentRow | null;
  readonly timeline: readonly TrackingStep[];
}

interface WorkOrderLike {
  readonly id: string;
  readonly title: string;
  readonly status: WorkOrderStatus;
  readonly priority: WorkOrderPriority;
  readonly startsAt?: Temporal.Instant;
  readonly endsAt?: Temporal.Instant;
  readonly address?: string;
}

function cardOf(order: WorkOrderLike): WorkOrderCard {
  return {
    id: order.id,
    title: order.title,
    status: order.status,
    priority: order.priority,
    startsAt: order.startsAt?.toString() ?? null,
    endsAt: order.endsAt?.toString() ?? null,
    address: order.address ?? null,
  };
}

/** The schedule board for the week starting on `monday`, with the backlog. */
export async function getDispatchWeek(
  monday: string,
): Promise<DispatchWeek | null> {
  "use cache: private";
  const request = await bsb.cached();
  cacheTag(tags.field());
  const { session, db } = request;
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const from = Temporal.PlainDate.from(monday);
  const to = from.add({ days: 6 });

  const [board, members] = await Promise.all([
    db.dispatch.board({ from, to }).orThrow(),
    readMembers(request, tenant),
  ]);

  const names = new Map(
    members.map((member) => [
      member.userId,
      member.name ?? member.email ?? member.userId,
    ]),
  );

  const days = Array.from({ length: 7 }, (_, index) =>
    from.add({ days: index }).toString(),
  );

  const rows = board.technicianIds.map((technicianId) => ({
    technicianId,
    name: names.get(technicianId) ?? technicianId,
    days: days.map((date) => ({
      date,
      orders: board.scheduled
        .filter(
          (order) =>
            order.technicianId === technicianId &&
            order.day?.toString() === date,
        )
        .map(cardOf),
    })),
  }));

  return {
    days,
    timeZone: board.timeZone,
    rows: rows.toSorted((a, b) => a.name.localeCompare(b.name)),
    backlog: board.backlog.map(cardOf),
  };
}

/** The caller's stops on `date`, in route order. */
export async function getTechnicianDay(
  date: string,
): Promise<TechnicianDayPlan | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(tags.field());
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const day = await db.dispatch
    .technicianDay({ day: Temporal.PlainDate.from(date) })
    .orThrow();

  return {
    date: day.date.toString(),
    planned: day.routeId !== undefined,
    stops: day.stops.map((stop) => ({
      position: stop.position,
      workOrder: cardOf(stop.workOrder),
    })),
  };
}

/** The latest shipments and the timeline of `selectedId` (or the newest). */
export async function getShipmentTracking(
  selectedId: string | undefined,
): Promise<ShipmentTracking | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(tags.field());
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const { shipments } = db;
  const list = await shipments.list({ limit: 50 }).orThrow();

  const rows: ShipmentRow[] = list.map((shipment) => ({
    id: shipment.id,
    reference: shipment.reference,
    status: shipment.status,
    recipient: shipment.to.name ?? shipment.to.company ?? "",
    destination: `${shipment.to.city}, ${shipment.to.country}`,
    carrier: shipment.carrier ?? null,
    trackingNumber: shipment.trackingNumber ?? null,
    updatedAt: shipment.updatedAt.toString(),
  }));

  const selected = rows.find((row) => row.id === selectedId) ?? rows[0] ?? null;

  const events = selected
    ? await shipments.trackingEvents(selected.id).orThrow()
    : [];

  return {
    shipments: rows,
    selected,
    timeline: events
      .map((event) => ({
        id: event.id,
        status: event.status,
        occurredAt: event.occurredAt.toString(),
        description: event.description ?? null,
        location: event.location ?? null,
      }))
      .toReversed(),
  };
}

// Detail pages

export interface WorkOrderPartRow {
  readonly id: string;
  readonly name: string;
  readonly quantity: string;
  readonly unit: string | null;
}

export interface MeterOption {
  readonly id: string;
  readonly name: string;
  readonly unit: string;
  readonly reading: string;
}

export interface WorkOrderDetail {
  readonly card: WorkOrderCard;
  readonly description: string | null;
  readonly technician: string | null;
  readonly enRouteAt: string | null;
  readonly arrivedAt: string | null;
  readonly completedAt: string | null;
  readonly completionNote: string | null;
  readonly createdAt: string;
  readonly parts: readonly WorkOrderPartRow[];
  readonly meters: readonly MeterOption[];
}

/**
 * One work order with its parts and the meters a visit can read; `null` when
 * absent.
 */
export async function getWorkOrder(
  id: string,
): Promise<WorkOrderDetail | undefined | null> {
  "use cache: private";
  const request = await bsb.cached();
  cacheTag(tags.field());
  const { session, db } = request;
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const order = await db.dispatch.get(id).orThrow();

  if (!order) {
    return undefined;
  }

  const [parts, metersRead, members] = await Promise.all([
    db.dispatch.parts(id).orThrow(),
    db.maintenance.meterPage({ limit: 100 }),
    readMembers(request, tenant),
  ]);

  // A technician without maintenance access still sees the visit, without meters.
  const meters = metersRead.ok ? metersRead.data.items : [];

  const technician = members.find(
    (member) => member.userId === order.technicianId,
  );

  return {
    card: cardOf(order),
    description: order.description ?? null,
    technician: technician
      ? (technician.name ?? technician.email ?? technician.userId)
      : null,
    enRouteAt: order.enRouteAt?.toString() ?? null,
    arrivedAt: order.arrivedAt?.toString() ?? null,
    completedAt: order.completedAt?.toString() ?? null,
    completionNote: order.completionNote ?? null,
    createdAt: order.createdAt.toString(),
    parts: parts.map((part) => ({
      id: part.id,
      name: part.name,
      quantity: part.quantity,
      unit: part.unit ?? null,
    })),
    meters: meters.map((meter) => ({
      id: meter.id,
      name: meter.name,
      unit: meter.unit,
      reading: meter.reading,
    })),
  };
}

export interface ShipmentDetail {
  readonly row: ShipmentRow;
  readonly direction: string | null;
  readonly service: string | null;
  readonly trackingUrl: string | null;
  readonly origin: string;
  readonly address: readonly string[];
  readonly packages: number;
  readonly weightGrams: number;
  readonly deliveredAt: string | null;
  readonly deliveredTo: string | null;
  readonly timeline: readonly TrackingStep[];
}

/** One shipment with its tracking timeline; `undefined` when it does not exist. */
export async function getShipment(
  id: string,
): Promise<ShipmentDetail | undefined | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(tags.field());

  if (!tenantOf(session)) {
    return null;
  }

  const shipment = await db.shipments.get(id).orThrow();

  if (!shipment) {
    return undefined;
  }

  const events = await db.shipments.trackingEvents(id).orThrow();
  const { to } = shipment;

  return {
    row: {
      id: shipment.id,
      reference: shipment.reference,
      status: shipment.status,
      recipient: to.name ?? to.company ?? "",
      destination: `${to.city}, ${to.country}`,
      carrier: shipment.carrier ?? null,
      trackingNumber: shipment.trackingNumber ?? null,
      updatedAt: shipment.updatedAt.toString(),
    },
    direction: shipment.direction ?? null,
    service: shipment.service ?? null,
    trackingUrl: shipment.trackingUrl ?? null,
    origin: shipment.from.company ?? shipment.from.name ?? shipment.from.city,
    address: [
      to.name,
      to.company,
      to.line1,
      to.line2,
      [to.postalCode, to.city].filter(Boolean).join(" "),
      to.country,
    ].filter((line): line is string => line !== undefined && line !== ""),
    packages: shipment.packages.length,
    weightGrams: shipment.packages.reduce(
      (sum, parcel) => sum + parcel.weightGrams,
      0,
    ),
    deliveredAt: shipment.deliveredAt?.toString() ?? null,
    deliveredTo: shipment.deliveredTo ?? null,
    timeline: events
      .map((event) => ({
        id: event.id,
        status: event.status,
        occurredAt: event.occurredAt.toString(),
        description: event.description ?? null,
        location: event.location ?? null,
      }))
      .toReversed(),
  };
}
