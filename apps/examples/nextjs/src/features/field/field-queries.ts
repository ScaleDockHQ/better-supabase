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
import { Temporal } from "temporal-polyfill";

import { getMembers } from "@/features/organization/organization-queries";
import { blocks } from "@/lib/blocks";
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
export async function loadDispatchWeek(
  monday: string,
): Promise<DispatchWeek | null> {
  "use cache: private";
  const { session, supabase } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const from = Temporal.PlainDate.from(monday);
  const to = from.add({ days: 6 });

  const [board, members] = await Promise.all([
    blocks(supabase, tenant).dispatch.board({ from, to }).orThrow(),
    getMembers(tenant),
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
export async function loadTechnicianDay(
  date: string,
): Promise<TechnicianDayPlan | null> {
  "use cache: private";
  const { session, supabase } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const day = await blocks(supabase, tenant)
    .dispatch.technicianDay(Temporal.PlainDate.from(date))
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
export async function loadShipmentTracking(
  selectedId: string | undefined,
): Promise<ShipmentTracking | null> {
  "use cache: private";
  const { session, supabase } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const { shipments } = blocks(supabase, tenant);
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
