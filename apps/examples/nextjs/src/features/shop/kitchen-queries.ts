import "server-only";
import type {
  KitchenStation,
  KitchenTicket,
  OrderBoardCard,
  PreparationState,
} from "better-supabase/blocks/orders";

import { tenantOf } from "better-supabase/next";

import { bsb } from "@/lib/supabase/server";

import type { Loaded } from "./shop-queries";

import { settle } from "./shop-queries";
import { shopOrders } from "./shop-server";

export interface StationView {
  readonly id: string;
  readonly name: string;
}

export interface TicketLineView {
  readonly lineId: string;
  readonly title: string;
  readonly quantity: number;
  readonly state: PreparationState;
  readonly note: string | null;
}

export interface TicketView {
  readonly orderId: string;
  readonly number: string;
  readonly sentAt: string;
  readonly lines: readonly TicketLineView[];
}

export interface KitchenView {
  readonly organizationId: string;
  readonly stations: readonly StationView[];
  /** The station shown, or null for every station. */
  readonly stationId: string | null;
  readonly tickets: readonly TicketView[];
}

export interface BoardCardView {
  readonly orderId: string;
  readonly number: string;
  readonly state: PreparationState;
  readonly sentAt: string;
  readonly lines: number;
  readonly ready: number;
}

export interface BoardView {
  readonly organizationId: string;
  readonly cards: readonly BoardCardView[];
}

const stationView = (station: KitchenStation): StationView => ({
  id: station.id,
  name: station.name,
});

const ticketView = (ticket: KitchenTicket): TicketView => ({
  orderId: ticket.orderId,
  number: ticket.number,
  sentAt: ticket.sentAt.toString(),
  lines: ticket.lines.map((line) => ({
    lineId: line.lineId,
    title: line.title,
    quantity: line.quantity,
    state: line.state,
    note: line.note ?? null,
  })),
});

const cardView = (card: OrderBoardCard): BoardCardView => ({
  orderId: card.orderId,
  number: card.number,
  state: card.state,
  sentAt: card.sentAt.toString(),
  lines:
    card.counts.queued +
    card.counts.preparing +
    card.counts.ready +
    card.counts.served,
  ready: card.counts.ready + card.counts.served,
});

async function loadKitchen(
  station: string | null,
): Promise<KitchenView | null> {
  "use cache: private";
  const { session, supabase } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const { kitchen } = shopOrders(supabase);
  const stations = await kitchen.stations(tenant).orThrow();
  const active = stations.filter((each) => each.active);
  const stationId = active.some((each) => each.id === station) ? station : null;

  const tickets = await kitchen
    .queue({
      organizationId: tenant,
      query: stationId === null ? {} : { stationId },
    })
    .orThrow();

  return {
    organizationId: tenant,
    stations: active.map(stationView),
    stationId,
    tickets: tickets.map(ticketView),
  };
}

/** The open tickets at one station, or at every station when `station` is null. */
export function getKitchen(
  station: string | null,
): Promise<Loaded<KitchenView>> {
  return settle(() => loadKitchen(station));
}

async function loadBoard(): Promise<BoardView | null> {
  "use cache: private";
  const { session, supabase } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const cards = await shopOrders(supabase)
    .kitchen.board({ organizationId: tenant })
    .orThrow();

  return { organizationId: tenant, cards: cards.map(cardView) };
}

/** The orders sent to the kitchen in the last day, by state. */
export function getOrderBoard(): Promise<Loaded<BoardView>> {
  return settle(loadBoard);
}
