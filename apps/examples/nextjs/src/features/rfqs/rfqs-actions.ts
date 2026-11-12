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
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { RFQS_TAG } from "./rfqs-cache";

const TAGS = [RFQS_TAG];

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
      quantity: Optional,
    }),
    requireTenant: true,
    permission: "rfqs.write",
  },
  async (input, { db, auth }) => {
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
                quantity:
                  Number.isFinite(quantity) && quantity > 0 ? quantity : 1,
              },
            ],
    });

    if (!created.ok) {
      return created;
    }

    await refreshCaller(auth, TAGS);

    return ok({ id: created.data.id });
  },
);

/** Adds a line to a draft; the block replaces all lines on an update. */
export const addRfqLine = bsb.action(
  {
    input: v.object({
      rfqId: Id,
      description: Name,
      quantity: Whole(1, 1_000_000),
    }),
    requireTenant: true,
    permission: "rfqs.write",
  },
  async ({ rfqId, description, quantity }, { db, auth }) => {
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
        { description, quantity },
      ],
    });

    if (!saved.ok) {
      return saved;
    }

    await refreshCaller(auth, TAGS);

    return ok(true);
  },
);

export const inviteSupplier = bsb.action(
  {
    input: v.object({ rfqId: Id, supplierId: Id }),
    requireTenant: true,
    permission: "rfqs.write",
  },
  async ({ rfqId, supplierId }, { db, auth }) => {
    const invited = await db.rfqs.inviteSupplier({
      rfqId,
      supplier: { type: "company", id: supplierId },
    });

    if (!invited.ok) {
      return invited;
    }

    await refreshCaller(auth, TAGS);

    return ok(true);
  },
);

export const declineInvitation = bsb.action(
  {
    input: v.object({ invitationId: Id }),
    requireTenant: true,
    permission: "rfqs.write",
  },
  async ({ invitationId }, { db, auth }) => {
    const declined = await db.rfqs.declineInvitation(invitationId);

    if (!declined.ok) {
      return declined;
    }

    await refreshCaller(auth, TAGS);

    return ok(true);
  },
);

/** Sends a draft to its suppliers, or stops accepting quotes. */
export const transitionRfq = bsb.action(
  {
    input: v.object({ rfqId: Id, action: v.picklist(["open", "close"]) }),
    requireTenant: true,
    permission: "rfqs.write",
  },
  async ({ rfqId, action }, { db, auth }) => {
    const moved =
      action === "open"
        ? await db.rfqs.openRfq(rfqId)
        : await db.rfqs.closeRfq(rfqId);

    if (!moved.ok) {
      return moved;
    }

    await refreshCaller(auth, TAGS);

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
  },
  async ({ rfqId, reason }, { db, auth }) => {
    const cancelled = await db.rfqs.cancelRfq({ rfqId, reason });

    if (!cancelled.ok) {
      return cancelled;
    }

    await refreshCaller(auth, TAGS);

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
  },
  async (input, { db, auth }) => {
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

    await refreshCaller(auth, TAGS);

    return ok(true);
  },
);

export const withdrawQuote = bsb.action(
  {
    input: v.object({ quoteId: Id }),
    requireTenant: true,
    permission: "rfqs.write",
  },
  async ({ quoteId }, { db, auth }) => {
    const withdrawn = await db.rfqs.withdrawQuote(quoteId);

    if (!withdrawn.ok) {
      return withdrawn;
    }

    await refreshCaller(auth, TAGS);

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
  },
  async ({ rfqId, quoteId, location }, { db, auth }) => {
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

    await refreshCaller(auth, TAGS);

    return ok({ purchaseOrderId: awarded.data.purchaseOrderId ?? null });
  },
);
