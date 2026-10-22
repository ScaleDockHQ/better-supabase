/** Where a work order is in its life. */
export const WORK_ORDER_STATUSES = [
  "unscheduled",
  "scheduled",
  "en_route",
  "on_site",
  "done",
  "cancelled",
] as const;

export type WorkOrderStatus = (typeof WORK_ORDER_STATUSES)[number];

export const WORK_ORDER_PRIORITIES = [
  "low",
  "normal",
  "high",
  "urgent",
] as const;

export type WorkOrderPriority = (typeof WORK_ORDER_PRIORITIES)[number];
