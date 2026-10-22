import type { AsyncResult } from "../../core/result.ts";
import type { BlockCall } from "../shared.ts";

import {
  enumOrThrow,
  instantArg,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  stringsOf,
  textOf,
} from "../shared.ts";

/** Where a line is in the kitchen, in order. */
export type PreparationState = "queued" | "preparing" | "ready" | "served";

export const PREPARATION_STATES: readonly PreparationState[] = [
  "queued",
  "preparing",
  "ready",
  "served",
];

/** The Realtime event every preparation change sends on `kitchenTopic`. */
export const KITCHEN_EVENT = "preparation";

/**
 * The private Realtime channel a kitchen display and an order board join: every
 * change to a line's state or station is sent there.
 */
export const kitchenTopic = (organizationId: string): string =>
  `kitchen:${organizationId}`;

/** A place lines are prepared at, such as a grill, a bar or a cold station. */
export interface KitchenStation {
  readonly id: string;
  readonly organizationId: string;
  /** Lowercase letters, digits, `-` and `_`. */
  readonly key: string;
  readonly name: string;
  readonly position: number;
  /** Lines of a product no station claims go here. */
  readonly isDefault: boolean;
  readonly active: boolean;
  /** The catalog products routed to this station. */
  readonly productIds: readonly string[];
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface KitchenStationInput {
  readonly key?: string;
  readonly name?: string;
  readonly position?: number;
  readonly default?: boolean;
  readonly active?: boolean;
  /** Replaces the products routed to the station. */
  readonly productIds?: readonly string[];
}

/** One order line at a station. */
export interface PreparationLine {
  readonly lineId: string;
  readonly orderId: string;
  readonly stationId?: string;
  readonly title: string;
  readonly sku: string;
  readonly quantity: number;
  readonly position: number;
  readonly state: PreparationState;
  /** The note for the cook, such as `no onions`. */
  readonly note?: string;
  readonly queuedAt: Temporal.Instant;
  readonly startedAt?: Temporal.Instant;
  readonly readyAt?: Temporal.Instant;
  readonly servedAt?: Temporal.Instant;
}

/** A kitchen display ticket: one order's lines at a station. */
export interface KitchenTicket {
  readonly orderId: string;
  readonly number: string;
  readonly sentAt: Temporal.Instant;
  readonly lines: readonly PreparationLine[];
}

/** An order on the order-state board, in its least advanced line's state. */
export interface OrderBoardCard {
  readonly orderId: string;
  readonly number: string;
  readonly customerId?: string;
  readonly status: string;
  readonly state: PreparationState;
  readonly sentAt: Temporal.Instant;
  /** When the last line became ready, once every line is. */
  readonly readyAt?: Temporal.Instant;
  readonly servedAt?: Temporal.Instant;
  readonly counts: Readonly<Record<PreparationState, number>>;
}

export interface KitchenQueueQuery {
  /** One station's tickets. Default: every station. */
  readonly stationId?: string;
  /** Default: queued, preparing and ready. */
  readonly states?: readonly PreparationState[];
  /** Default 100, at most 500 tickets. */
  readonly pageSize?: number;
}

export interface OrderBoardQuery {
  /** Orders sent to the kitchen since. Default: the last 24 hours. */
  readonly since?: Temporal.Instant;
  /** Default 200, at most 1000 orders. */
  readonly pageSize?: number;
}

/**
 * The kitchen of `blocks.orders.options.kitchen`: stations, line states, a
 * kitchen display's queue and an order-state board. Members need
 * `orders.prepare` (or `orders.manage`) to move lines, and `orders.manage` to
 * change stations.
 */
export interface OrderKitchen {
  saveStation(
    organizationId: string,
    input: KitchenStationInput,
    stationId?: string,
  ): AsyncResult<KitchenStation>;
  deleteStation(stationId: string): AsyncResult<boolean>;
  stations(organizationId: string): AsyncResult<readonly KitchenStation[]>;
  /**
   * Queues the order's lines not sent yet at their product's station. `notes`
   * maps a line id to a note for the cook. Returns how many it queued.
   */
  send(
    orderId: string,
    notes?: Readonly<Record<string, string>>,
  ): AsyncResult<number>;
  /** Moves one line; moving back clears the later times. */
  setState(
    lineId: string,
    state: PreparationState,
  ): AsyncResult<PreparationLine>;
  /**
   * Moves every line of the order behind `state` up to it, at one station or
   * all. Returns how many lines moved.
   */
  bump(
    orderId: string,
    state: PreparationState,
    stationId?: string,
  ): AsyncResult<number>;
  queue(
    organizationId: string,
    query?: KitchenQueueQuery,
  ): AsyncResult<readonly KitchenTicket[]>;
  board(
    organizationId: string,
    query?: OrderBoardQuery,
  ): AsyncResult<readonly OrderBoardCard[]>;
}

const countOf = (value: unknown): number =>
  typeof value === "number" ? value : Number(value ?? 0);

function stationOf(value: unknown): KitchenStation {
  const row = recordOf(value, "kitchen station");

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    key: textOf(row["key"]),
    name: textOf(row["name"]),
    position: countOf(row["position"]),
    isDefault: row["isDefault"] === true,
    active: row["active"] !== false,
    productIds: stringsOf(row["productIds"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
  };
}

const stateOf = (value: unknown): PreparationState =>
  enumOrThrow(value, PREPARATION_STATES, "preparation state");

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): Partial<Record<K, V>> {
  // SAFETY: a one-key object whose key is K.
  return value === undefined ? {} : ({ [key]: value } as Record<K, V>);
}

function preparationLineOf(value: unknown): PreparationLine {
  const row = recordOf(value, "preparation line");

  return {
    lineId: textOf(row["lineId"]),
    orderId: textOf(row["orderId"]),
    ...optional("stationId", optionalText(row["stationId"])),
    title: textOf(row["title"]),
    sku: textOf(row["sku"]),
    quantity: countOf(row["quantity"]),
    position: countOf(row["position"]),
    state: stateOf(row["state"]),
    ...optional("note", optionalText(row["note"])),
    queuedAt: requiredInstant(row["queuedAt"], "queuedAt"),
    ...optional("startedAt", optionalInstant(row["startedAt"])),
    ...optional("readyAt", optionalInstant(row["readyAt"])),
    ...optional("servedAt", optionalInstant(row["servedAt"])),
  };
}

function ticketOf(row: Record<string, unknown>): KitchenTicket {
  return {
    orderId: textOf(row["orderId"]),
    number: textOf(row["number"]),
    sentAt: requiredInstant(row["sentAt"], "sentAt"),
    lines: recordsOf(row["lines"], "ticket lines").map(preparationLineOf),
  };
}

function cardOf(row: Record<string, unknown>): OrderBoardCard {
  const counts = recordOf(row["counts"] ?? {}, "board counts");

  return {
    orderId: textOf(row["orderId"]),
    number: textOf(row["number"]),
    ...optional("customerId", optionalText(row["customerId"])),
    status: textOf(row["status"]),
    state: stateOf(row["state"]),
    sentAt: requiredInstant(row["sentAt"], "sentAt"),
    ...optional("readyAt", optionalInstant(row["readyAt"])),
    ...optional("servedAt", optionalInstant(row["servedAt"])),
    counts: {
      queued: countOf(counts["queued"]),
      preparing: countOf(counts["preparing"]),
      ready: countOf(counts["ready"]),
      served: countOf(counts["served"]),
    },
  };
}

function stationArg(input: KitchenStationInput): Record<string, unknown> {
  return {
    ...optional("key", input.key),
    ...optional("name", input.name),
    ...optional("position", input.position),
    ...optional("default", input.default),
    ...optional("active", input.active),
    ...optional("productIds", input.productIds),
  };
}

/** The kitchen methods over the orders SQL functions. */
export function orderKitchen(call: BlockCall): OrderKitchen {
  return {
    saveStation: (organizationId, input, stationId) =>
      call(
        "save_kitchen_station",
        {
          tenant: organizationId,
          station: stationId ?? null,
          attrs: stationArg(input),
        },
        stationOf,
      ),
    deleteStation: (stationId) =>
      call(
        "delete_kitchen_station",
        { station: stationId },
        (value) => value === true,
      ),
    stations: (organizationId) =>
      call("kitchen_stations", { tenant: organizationId }, (value) =>
        recordsOf(value, "kitchen_stations").map(stationOf),
      ),
    send: (orderId, notes) =>
      call(
        "send_order_to_kitchen",
        { order_id: orderId, notes: notes ?? null },
        countOf,
      ),
    setState: (lineId, state) =>
      call("set_line_preparation", { line: lineId, state }, preparationLineOf),
    bump: (orderId, state, stationId) =>
      call(
        "bump_kitchen_ticket",
        { order_id: orderId, station: stationId ?? null, state },
        countOf,
      ),
    queue: (organizationId, query = {}) =>
      call(
        "kitchen_queue",
        {
          tenant: organizationId,
          station: query.stationId ?? null,
          states: query.states ?? null,
          page_size: query.pageSize ?? null,
        },
        (value) => recordsOf(value, "kitchen_queue").map(ticketOf),
      ),
    board: (organizationId, query = {}) =>
      call(
        "order_board",
        {
          tenant: organizationId,
          since: instantArg(query.since) ?? null,
          page_size: query.pageSize ?? null,
        },
        (value) => recordsOf(value, "order_board").map(cardOf),
      ),
  };
}
