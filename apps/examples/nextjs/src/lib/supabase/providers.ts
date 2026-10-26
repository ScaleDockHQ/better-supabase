import { peopleDataLabsEnrichment } from "better-supabase/blocks/enrichment";
import { gmailMail, outlookMail } from "better-supabase/blocks/mail-sync";

import { env } from "@/env";

import { blocks } from "./blocks.generated.ts";

/**
 * The providers the installed blocks take. Spread them over the generated
 * blocks: `defineBlocks(blockConfig, { ...blocks, ...providers })`.
 * `better-supabase add` appends a commented stub for each block that takes one,
 * and doctor (BS505) fails while a required one is still a comment.
 */
export const providers = {
  // enrichment (required): Looks companies and people up.
  // `provider` takes an implementation of EnrichmentProvider from "better-supabase/blocks/enrichment".
  enrichment: blocks.enrichment.with({
    provider: peopleDataLabsEnrichment({ apiKey: env.PDL_API_KEY ?? "" }),
  }),
  // mail-sync (required): Reads and sends each member's mailbox.
  // `providers` takes an implementation of MailProvider from "better-supabase/blocks/mail-sync".
  "mail-sync": blocks["mail-sync"].with({
    providers: [gmailMail(), outlookMail()],
  }),
  // shipments: Quotes, labels and tracks shipments; without one, shipments are recorded by hand.
  // `carriers` takes an implementation of ShippingProvider from "better-supabase/blocks/shipments".
  // shipments: blocks.shipments.with({ carriers: [yourCarrier] }),
  // orders: Takes payments; without one, payments are recorded by hand.
  // `payments` takes an implementation of PaymentProvider from "better-supabase/commerce".
  // orders: blocks.orders.with({ payments: stripePayments({ stripe }) }),
  // orders: Computes tax on order lines.
  // `tax` takes an implementation of TaxProvider from "better-supabase/commerce".
  // orders: blocks.orders.with({ tax: fixedRates({ rates }) }),
  // donations: Takes payments; without one, payments are recorded by hand.
  // `payments` takes an implementation of PaymentProvider from "better-supabase/commerce".
  // donations: blocks.donations.with({ payments: stripePayments({ stripe }) }),
} satisfies Partial<typeof blocks>;
