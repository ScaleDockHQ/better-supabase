import "server-only";
import type { Money } from "better-supabase/commerce";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { readContacts } from "@/features/crm/crm-queries";
import { bsb } from "@/lib/supabase/server";

import { RFQS_TAG } from "./rfqs-cache";

export type RfqStatus = "draft" | "open" | "closed" | "awarded" | "cancelled";

/** A request as the overview shows it, serializable. */
export interface RfqRow {
  readonly id: string;
  readonly number: string;
  readonly title: string;
  readonly currency: string;
  readonly status: RfqStatus;
  readonly dueAt: string | null;
  readonly createdAt: string;
  readonly awarded: boolean;
}

/**
 * The newest 200 requests. The block has no text search on `listRfqs`, so the
 * overview searches, filters and pages these rows on the server (EX-1101).
 */
export async function loadRfqs(): Promise<readonly RfqRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(RFQS_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const rfqs = await db.rfqs.listRfqs({ limit: 200 }).orThrow();

  return rfqs.map((row) => ({
    id: row.id,
    number: row.number,
    title: row.title,
    currency: row.currency,
    status: row.status,
    dueAt: row.dueAt?.toString() ?? null,
    createdAt: row.createdAt.toString(),
    awarded: row.awardedQuoteId !== undefined,
  }));
}

export interface RfqLineRow {
  readonly id: string;
  readonly ordinal: number;
  readonly description: string;
  readonly quantity: number;
  readonly unit: string | null;
  readonly variantId: string | null;
}

export interface RfqSupplierRow {
  readonly id: string;
  readonly supplierId: string;
  readonly name: string;
  readonly status: "invited" | "quoted" | "declined";
  readonly invitedAt: string;
  readonly respondedAt: string | null;
}

export interface RfqQuoteRow {
  readonly id: string;
  readonly invitationId: string;
  readonly supplier: string;
  readonly status: string;
  readonly total: Money;
  readonly leadTimeDays: number | null;
  readonly validUntil: string | null;
  readonly revision: number;
}

export interface RfqCompareCell {
  readonly quoteId: string;
  readonly unitAmount: Money;
  readonly lowest: boolean;
}

export interface RfqCompareRow {
  readonly lineId: string;
  readonly description: string;
  readonly quantity: number;
  readonly offers: readonly RfqCompareCell[];
}

export interface RfqCompareQuote {
  readonly quoteId: string;
  readonly supplier: string;
  readonly total: Money;
  readonly complete: boolean;
  readonly lowest: boolean;
}

export interface RfqFull extends RfqRow {
  readonly notes: string | null;
  readonly cancelReason: string | null;
  readonly purchaseOrderId: string | null;
  readonly openedAt: string | null;
  readonly awardedAt: string | null;
  readonly lines: readonly RfqLineRow[];
  readonly suppliers: readonly RfqSupplierRow[];
  readonly quotes: readonly RfqQuoteRow[];
  readonly compare: {
    readonly lines: readonly RfqCompareRow[];
    readonly quotes: readonly RfqCompareQuote[];
  };
}

/**
 * One request with its lines, invitations, quotes and the side-by-side
 * comparison.
 */
export async function loadRfq(id: string): Promise<RfqFull | null | undefined> {
  "use cache: private";
  const cached = await bsb.cached();
  const { session, db } = cached;
  cacheTag(RFQS_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const [found, contacts] = await Promise.all([
    db.rfqs.getRfq(id),
    readContacts(cached),
  ]);

  if (!found.ok) {
    if (found.error.kind === "not_found") {
      return undefined;
    }

    throw new Error(found.error.message);
  }

  const rfq = found.data;
  const names = new Map((contacts ?? []).map((row) => [row.id, row.name]));
  const nameOf = (supplierId: string) => names.get(supplierId) ?? supplierId;
  const supplierOf = new Map(rfq.suppliers.map((row) => [row.id, row]));

  const compared =
    rfq.quotes.length > 0 ? await db.rfqs.compare(id).orThrow() : undefined;

  return {
    id: rfq.id,
    number: rfq.number,
    title: rfq.title,
    currency: rfq.currency,
    status: rfq.status,
    dueAt: rfq.dueAt?.toString() ?? null,
    createdAt: rfq.createdAt.toString(),
    awarded: rfq.awardedQuoteId !== undefined,
    notes: rfq.notes ?? null,
    cancelReason: rfq.cancelReason ?? null,
    purchaseOrderId: rfq.purchaseOrderId ?? null,
    openedAt: rfq.openedAt?.toString() ?? null,
    awardedAt: rfq.awardedAt?.toString() ?? null,
    lines: rfq.lines.map((line) => ({
      id: line.id,
      ordinal: line.ordinal,
      description: line.description,
      quantity: line.quantity,
      unit: line.unit ?? null,
      variantId: line.variantId ?? null,
    })),
    suppliers: rfq.suppliers.map((row) => ({
      id: row.id,
      supplierId: row.supplierId,
      name: nameOf(row.supplierId),
      status: row.status,
      invitedAt: row.invitedAt.toString(),
      respondedAt: row.respondedAt?.toString() ?? null,
    })),
    quotes: rfq.quotes.map((quote) => ({
      id: quote.id,
      invitationId: quote.invitationId,
      supplier: nameOf(supplierOf.get(quote.invitationId)?.supplierId ?? ""),
      status: quote.status,
      total: quote.total,
      leadTimeDays: quote.leadTimeDays ?? null,
      validUntil: quote.validUntil?.toString() ?? null,
      revision: quote.revision,
    })),
    compare: {
      lines: (compared?.lines ?? []).map((line) => ({
        lineId: line.lineId,
        description: line.description,
        quantity: line.quantity,
        offers: line.offers.map((offer) => ({
          quoteId: offer.quoteId,
          unitAmount: offer.unitAmount,
          lowest: offer.lowest,
        })),
      })),
      quotes: (compared?.quotes ?? []).map((quote) => ({
        quoteId: quote.quoteId,
        supplier: nameOf(quote.supplierId),
        total: quote.total,
        complete: quote.complete,
        lowest: quote.lowest,
      })),
    },
  };
}
