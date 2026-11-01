"use server";

import { ok } from "better-supabase";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { driveOf } from "@/features/drive/drive-client";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { crmOf, filespaceOf } from "./composites";

const Id = v.pipe(v.string(), v.uuid());

/**
 * Wins a deal and drafts its quote in one call: `crm.closeWon`. The deal is won
 * first, so a refused move leaves no quote behind.
 */
export const closeDealWon = bsb.action(
  {
    input: v.object({ dealId: Id, quote: v.optional(v.boolean(), true) }),
    requireTenant: true,
    permission: "deals.write",
  },
  async ({ dealId, quote }, { db, auth }) => {
    const closed = await crmOf(db).closeWon({ dealId, quote });

    if (!closed.ok) {
      return closed;
    }

    await refreshCaller(auth);

    return ok({
      dealId: closed.data.deal.id,
      quoteId: closed.data.quote?.id ?? null,
    });
  },
);

/**
 * Makes a link anyone with the token can open for a drive item, valid for
 * `days`: `filespace.publicLink`.
 */
export const createPublicLink = bsb.action(
  {
    input: v.object({
      id: Id,
      days: v.pipe(v.number(), v.integer(), v.minValue(1), v.maxValue(90)),
    }),
    requireTenant: true,
    permission: "drive.read",
  },
  async ({ id, days }, { db }) => {
    const link = await filespaceOf(db, driveOf(db)).publicLink({
      id,
      expiresAt: Temporal.Now.instant().add({ hours: days * 24 }),
    });

    if (!link.ok) {
      return link;
    }

    return ok({ token: link.data.token });
  },
);
