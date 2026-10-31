import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** What the `pick_wave.*` events carry. */
export interface PickWaveEventData {
  readonly organizationId: string;
  /** The wave. */
  readonly id: string;
  readonly name: string;
  readonly locationId: string;
  /** `draft`, `released`, `completed` or `cancelled`. */
  readonly status: string;
}

/** What the `pick_list.*` events carry. */
export interface PickListEventData {
  readonly organizationId: string;
  /** The pick list. */
  readonly id: string;
  readonly waveId: string | null;
  readonly locationId: string;
  readonly documentType: string;
  readonly documentId: string;
  readonly status: string;
}

/** `pick_list.picked`. */
export interface PickListPickedEventData extends PickListEventData {
  /** How many lines were picked short. */
  readonly short: number;
}

/** What the `count_plan.*` events carry. */
export interface CountPlanEventData {
  readonly organizationId: string;
  /** The plan. */
  readonly id: string;
  readonly name: string;
  readonly locationId: string;
}

/** `count_plan.executed`. */
export interface CountPlanExecutedEventData extends CountPlanEventData {
  /** The stock count the run opened. */
  readonly countId: string;
}

/** The events of the `warehouse` block: type to data. */
export type WarehouseEvents = {
  readonly "pick_wave.created": PickWaveEventData;
  readonly "pick_wave.released": PickWaveEventData;
  readonly "pick_wave.completed": PickWaveEventData;
  readonly "pick_list.created": PickListEventData;
  readonly "pick_list.picked": PickListPickedEventData;
  readonly "count_plan.created": CountPlanEventData;
  readonly "count_plan.executed": CountPlanExecutedEventData;
};

/** The `warehouse` block's event types, for its manifest and `onBlockEvent`. */
export const warehouseEvents: Events<WarehouseEvents> = defineEvents({
  "pick_wave.created": event<PickWaveEventData>(),
  "pick_wave.released": event<PickWaveEventData>(),
  "pick_wave.completed": event<PickWaveEventData>(),
  "pick_list.created": event<PickListEventData>(),
  "pick_list.picked": event<PickListPickedEventData>(),
  "count_plan.created": event<CountPlanEventData>(),
  "count_plan.executed": event<CountPlanExecutedEventData>(),
});
