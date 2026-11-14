import "server-only";
import {
  createPartyResolver,
  subjectKey,
} from "better-supabase/blocks/subjects";
import { formatMoney } from "better-supabase/commerce";

import type { bsb } from "@/lib/supabase/server";

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

/**
 * An open deal that names the contact, with its company named by the party
 * core.
 */
export interface ContactDeal {
  readonly id: string;
  readonly name: string;
  /** The amount in the caller's locale. */
  readonly amount: string;
  readonly company: string | null;
}

const DEAL_LIMIT = 5;

/**
 * The open deals that name a person as a contact, newest first. An inbox
 * contact is a CRM person, so no lookup table links them; the party core names
 * each deal's company through `subjects.label`.
 */
export async function loadContactDeals(
  db: Db,
  contactId: string,
  locale: string,
): Promise<readonly ContactDeal[]> {
  const deals = await db.deals
    .list({ subject: { type: "person", id: contactId } })
    .orThrow();

  const open = deals
    .filter((deal) => deal.outcome === "open")
    .slice(0, DEAL_LIMIT);

  const parties = createPartyResolver({
    label: (refs) => db.subjects.label(refs),
  });

  const companies = await parties
    .resolve(
      open.flatMap((deal) =>
        deal.company === undefined ? [] : [deal.company],
      ),
    )
    .orThrow();

  return open.map((deal) => ({
    id: deal.id,
    name: deal.name,
    amount: formatMoney(deal.amount, locale),
    company:
      deal.company === undefined
        ? null
        : (companies[subjectKey(deal.company)]?.name ?? null),
  }));
}
