import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `work_order.created`. */
export interface WorkOrderCreatedEventData {
  readonly organizationId: string;
  /** The work order. */
  readonly id: string;
  /** `unscheduled`, or `scheduled` when it was created with a slot. */
  readonly status: string;
  readonly technicianId: string | null;
  readonly subjectType: string | null;
  readonly subjectId: string | null;
}

/** `work_order.updated`: its title, description, priority or place changed. */
export interface WorkOrderUpdatedEventData {
  readonly organizationId: string;
  readonly id: string;
}

/** `work_order.scheduled`: it got a technician and a slot, or a new one. */
export interface WorkOrderScheduledEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly technicianId: string;
  /** ISO 8601. */
  readonly startsAt: string;
  readonly endsAt: string;
}

/** `work_order.unscheduled`: it went back to the backlog. */
export interface WorkOrderUnscheduledEventData {
  readonly organizationId: string;
  readonly id: string;
  /** The technician it had. */
  readonly technicianId: string | null;
}

/** `work_order.status_changed`: en route, on site, done or cancelled. */
export interface WorkOrderStatusChangedEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly from: string;
  readonly to: string;
  readonly technicianId: string | null;
}

/** `work_order.part_used`: a part was recorded on the work order. */
export interface WorkOrderPartUsedEventData {
  readonly organizationId: string;
  /** The work order. */
  readonly id: string;
  readonly partId: string;
  readonly assetId: string | null;
  readonly variantId: string | null;
  /** A decimal string. */
  readonly quantity: string;
}

/** `dispatch_route.planned`: a technician's day got its ordered stops. */
export interface DispatchRoutePlannedEventData {
  readonly organizationId: string;
  /** The route. */
  readonly id: string;
  readonly technicianId: string;
  /** `YYYY-MM-DD`. */
  readonly routeDate: string;
  readonly stops: number;
}

/** The events of the `dispatch` block: type to data. */
export type DispatchEvents = {
  readonly "work_order.created": WorkOrderCreatedEventData;
  readonly "work_order.updated": WorkOrderUpdatedEventData;
  readonly "work_order.scheduled": WorkOrderScheduledEventData;
  readonly "work_order.unscheduled": WorkOrderUnscheduledEventData;
  readonly "work_order.status_changed": WorkOrderStatusChangedEventData;
  readonly "work_order.part_used": WorkOrderPartUsedEventData;
  readonly "dispatch_route.planned": DispatchRoutePlannedEventData;
};

/** The `dispatch` block's event types, for its manifest and `onBlockEvent`. */
export const dispatchEvents: Events<DispatchEvents> = defineEvents({
  "work_order.created": event<WorkOrderCreatedEventData>(),
  "work_order.updated": event<WorkOrderUpdatedEventData>(),
  "work_order.scheduled": event<WorkOrderScheduledEventData>(),
  "work_order.unscheduled": event<WorkOrderUnscheduledEventData>(),
  "work_order.status_changed": event<WorkOrderStatusChangedEventData>(),
  "work_order.part_used": event<WorkOrderPartUsedEventData>(),
  "dispatch_route.planned": event<DispatchRoutePlannedEventData>(),
});
