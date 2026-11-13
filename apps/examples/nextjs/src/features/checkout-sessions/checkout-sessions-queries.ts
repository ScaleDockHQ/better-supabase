import "server-only";
import type { Result } from "better-supabase";
import type { PageOptions } from "better-supabase/blocks";
import type { CheckoutSession } from "better-supabase/blocks/agent-checkout";

import { ok } from "better-supabase";
import { moneyToJson } from "better-supabase/commerce";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";
import * as v from "valibot";

import type { BlockPage } from "@/lib/block-page";
import type { BlockListQuery } from "@/lib/block-status-list";

import { bsb } from "@/lib/supabase/server";

import type { SessionRow } from "./session-row";

import { CHECKOUT_SESSIONS_TAG } from "./checkout-sessions-cache";
import {
  SESSION_PAGE_SIZE,
  SESSION_PROTOCOLS,
  SESSION_STATUSES,
  sessionList,
} from "./checkout-sessions-list";

/** The block's keyset cursor, carried through the URL as a JSON array. */
const Cursor = v.pipe(v.string(), v.parseJson(), v.array(v.string()));

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

const isStatus = (value: string): value is SessionRow["status"] =>
  SESSION_STATUSES.some((status) => status === value);

const isProtocol = (value: string): value is SessionRow["protocol"] =>
  SESSION_PROTOCOLS.some((protocol) => protocol === value);

/** The buyer details the agent supplied: only the text fields show. */
const BuyerText = v.record(
  v.string(),
  v.fallback(v.nullable(v.string()), null),
);

function buyerFields(session: CheckoutSession): Record<string, string> {
  const parsed = v.safeParse(BuyerText, session.buyer ?? {});

  return Object.fromEntries(
    Object.entries(parsed.success ? parsed.output : {}).flatMap(
      ([key, value]) => (value === null ? [] : [[key, value]]),
    ),
  );
}

function buyerName(session: CheckoutSession): string | null {
  const fields = buyerFields(session);

  return fields["name"] ?? fields["email"] ?? null;
}

function toRow(session: CheckoutSession): SessionRow {
  return {
    id: session.id,
    protocol: session.protocol,
    status: session.status,
    buyer: buyerName(session),
    orderId: session.orderId ?? null,
    expired: session.expired,
    createdAt: session.createdAt.toString(),
  };
}

/**
 * One page of sessions. The selected statuses and protocols are list filters of
 * one block call, and its keyset cursor pages (`after` holds it as JSON).
 */
export async function loadSessionPage(
  db: Db,
  query: BlockListQuery<"newest">,
): Promise<Result<BlockPage<SessionRow>>> {
  const statuses = (query.facets["status"] ?? []).filter(isStatus);
  const protocols = (query.facets["protocol"] ?? []).filter(isProtocol);

  const cursor =
    query.after === undefined ? undefined : v.safeParse(Cursor, query.after);

  const filters: Record<string, readonly string[]> = {};

  if (statuses.length > 0) {
    filters["status"] = statuses;
  }

  if (protocols.length > 0) {
    filters["protocol"] = protocols;
  }

  const options: PageOptions = { limit: SESSION_PAGE_SIZE, filters };

  const result = await db.agentCheckout.sessionPage(
    cursor?.success ? { ...options, after: cursor.output } : options,
  );

  if (!result.ok) {
    return result;
  }

  return ok({
    items: result.data.items.map(toRow),
    nextCursor:
      result.data.nextCursor === null
        ? null
        : JSON.stringify(result.data.nextCursor),
  });
}

/** The first page of sessions, for the instant shell. */
export async function getSessions(): Promise<BlockPage<SessionRow> | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(CHECKOUT_SESSIONS_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const result = await loadSessionPage(db, sessionList.defaults);

  if (!result.ok) {
    throw new Error(result.error.message);
  }

  return result.data;
}

export interface SessionDetailData extends SessionRow {
  readonly cartId: string;
  readonly expiresAt: string | null;
  readonly buyerDetails: readonly (readonly [string, string])[];
  readonly total: ReturnType<typeof moneyToJson> | null;
}

/** One session with the buyer details and the cart at today's price. */
export async function getSession(
  id: string,
): Promise<SessionDetailData | null> {
  "use cache: private";
  const { db } = await bsb.cached();
  cacheTag(CHECKOUT_SESSIONS_TAG);

  const found = await db.agentCheckout.getSession(id);

  if (!found.ok) {
    if (found.error.code === "not_found") {
      return null;
    }

    throw new Error(found.error.message);
  }

  const session = found.data;
  const priced = await db.agentCheckout.priceSession(id);

  return {
    ...toRow(session),
    cartId: session.cartId,
    expiresAt: session.expiresAt?.toString() ?? null,
    buyerDetails: Object.entries(buyerFields(session)),
    total: priced.ok ? moneyToJson(priced.data.total) : null,
  };
}
