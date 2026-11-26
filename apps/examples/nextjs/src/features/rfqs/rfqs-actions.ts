"use server";

import { ok } from "better-supabase";
import { parseMoney } from "better-supabase/commerce";
import * as v from "valibot";

import {
  Decimal,
  Id,
  instantOf,
  given,
  Name,
  Optional,
  Whole,
} from "@/lib/form-input";
import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

const TAGS = [tags.rfqs()];

const Currency = v.picklist(["EUR", "USD", "GBP"]);

/** Creates a draft request with an optional first line. */
export const createRfq = bsb.action(
  {
    input: v.object({
      title: Name,
      currency: Currency,
      dueOn: Optional,
      notes: Optional,
      description: Optional,
      variantId: Optional,
      quantity: Optional,
    }),
    requireTenant: true,
    permission: "rfqs.write",
    tags: () => TAGS,
    refresh: true,
  },
  async (input, { db }) => {
    const quantity = Number(input.quantity ?? "1");

    const created = await db.rfqs.createRfq({
      input: {
        title: input.title,
        currency: input.currency,
        ...given("dueAt", instantOf(input.dueOn)),
        ...given("notes", input.notes),
      },
      lines:
        input.description === undefined
          ? []
          : [
              {
                description: input.description,
                ...given("variantId", input.variantId),
                quantity:
                  Number.isFinite(quantity) && quantity > 0 ? quantity : 1,
              },
            ],
    });

    if (!created.ok) {
      return created;
    }

    return ok({ id: created.data.id });
  },
);

/**
 * Adds a line to a draft; the block replaces all lines on an update. A line
 * that names a variant lets the award create a purchase order (EX-1112).
 */
export const addRfqLine = bsb.action(
  {
    input: v.object({
      rfqId: Id,
      description: Name,
      variantId: Optional,
      quantity: Whole(1, 1_000_000),
    }),
    requireTenant: true,
    permission: "rfqs.write",
    tags: () => TAGS,
    refresh: true,
  },
  async ({ rfqId, description, variantId, quantity }, { db }) => {
    const current = await db.rfqs.getRfq(rfqId);

    if (!current.ok) {
      return current;
    }

    const saved = await db.rfqs.updateRfq({
      rfqId,
      input: {},
      lines: [
        ...current.data.lines.map((line) => ({
          description: line.description,
          quantity: line.quantity,
          ...given("variantId", line.variantId),
          ...given("unit", line.unit),
        })),
        { description, quantity, ...given("variantId", variantId) },
      ],
    });

    if (!saved.ok) {
      return saved;
    }

    return ok(true);
  },
);

export const inviteSupplier = bsb.action(
  {
    input: v.object({ rfqId: Id, supplierId: Id }),
    requireTenant: true,
    permission: "rfqs.write",
    tags: () => TAGS,
    refresh: true,
  },
  async ({ rfqId, supplierId }, { db }) => {
    const invited = await db.rfqs.inviteSupplier({
      rfqId,
      supplier: { type: "company", id: supplierId },
    });

    if (!invited.ok) {
      return invited;
    }

    return ok(true);
  },
);

export const declineInvitation = bsb.action(
  {
    input: v.object({ invitationId: Id }),
    requireTenant: true,
    permission: "rfqs.write",
    tags: () => TAGS,
    refresh: true,
  },
  async ({ invitationId }, { db }) => {
    const declined = await db.rfqs.declineInvitation(invitationId);

    if (!declined.ok) {
      return declined;
    }

    return ok(true);
  },
);

/** Sends a draft to its suppliers, or stops accepting quotes. */
export const transitionRfq = bsb.action(
  {
    input: v.object({ rfqId: Id, action: v.picklist(["open", "close"]) }),
    requireTenant: true,
    permission: "rfqs.write",
    tags: () => TAGS,
    refresh: true,
  },
  async ({ rfqId, action }, { db }) => {
    const moved =
      action === "open"
        ? await db.rfqs.openRfq(rfqId)
        : await db.rfqs.closeRfq(rfqId);

    if (!moved.ok) {
      return moved;
    }

    return ok(true);
  },
);

export const cancelRfq = bsb.action(
  {
    input: v.object({
      rfqId: Id,
      reason: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(500)),
    }),
    requireTenant: true,
    permission: "rfqs.manage",
    tags: () => TAGS,
    refresh: true,
  },
  async ({ rfqId, reason }, { db }) => {
    const cancelled = await db.rfqs.cancelRfq({ rfqId, reason });

    if (!cancelled.ok) {
      return cancelled;
    }

    return ok(true);
  },
);

/**
 * Records a supplier's unit price per line: the form has one `line_<id>` field
 * per line of the request, and a quote replaces the supplier's earlier one.
 */
export const recordQuote = bsb.action(
  {
    input: v.looseObject({
      rfqId: Id,
      invitationId: Id,
      currency: Currency,
      leadTimeDays: Optional,
    }),
    requireTenant: true,
    permission: "rfqs.write",
    tags: () => TAGS,
    refresh: true,
  },
  async (input, { db }) => {
    const lines = Object.entries(input).flatMap(([key, value]) => {
      const lineId = key.startsWith("line_") ? key.slice(5) : undefined;

      return lineId !== undefined && v.is(Decimal, value)
        ? [{ lineId, unitAmount: parseMoney(value, input.currency) }]
        : [];
    });

    const lead = Number(input.leadTimeDays);

    const recorded = await db.rfqs.recordQuote({
      rfqId: input.rfqId,
      invitationId: input.invitationId,
      lines,
      input: Number.isInteger(lead) && lead > 0 ? { leadTimeDays: lead } : {},
    });

    if (!recorded.ok) {
      return recorded;
    }

    return ok(true);
  },
);

export const withdrawQuote = bsb.action(
  {
    input: v.object({ quoteId: Id }),
    requireTenant: true,
    permission: "rfqs.write",
    tags: () => TAGS,
    refresh: true,
  },
  async ({ quoteId }, { db }) => {
    const withdrawn = await db.rfqs.withdrawQuote(quoteId);

    if (!withdrawn.ok) {
      return withdrawn;
    }

    return ok(true);
  },
);

/**
 * Awards the request to one quote, or to the cheapest complete one when
 * `quoteId` is empty. With a location and variants on every line, the block
 * also creates a draft purchase order at the quoted prices.
 */
export const awardRfq = bsb.action(
  {
    input: v.object({ rfqId: Id, quoteId: Optional, location: Optional }),
    requireTenant: true,
    permission: "rfqs.manage",
    tags: () => TAGS,
    refresh: true,
  },
  async ({ rfqId, quoteId, location }, { db }) => {
    const awarded =
      quoteId === undefined
        ? await db.rfqs.awardBest({ rfqId, location })
        : await db.rfqs.award({
            rfqId,
            quoteId,
            ...given("location", location),
          });

    if (!awarded.ok) {
      return awarded;
    }

    return ok({ purchaseOrderId: awarded.data.purchaseOrderId ?? null });
  },
);
