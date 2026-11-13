import type { BlockOf } from "../define-block.ts";
import type { VercelMarketplaceEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { vercelMarketplaceEvents } from "./events.ts";
import { vercelMarketplaceSqlOptions } from "./options.ts";
import { createVercelMarketplace } from "./vercel-marketplace.ts";

/** The `vercel-marketplace` block's manifest (ADR 0029). */
export const vercelMarketplaceBlock: BlockOf<
  "vercel-marketplace",
  typeof createVercelMarketplace,
  VercelMarketplaceEvents
> = defineBlock({
  name: "vercel-marketplace",
  sql: ["vercel-marketplace"],
  options: { "vercel-marketplace": vercelMarketplaceSqlOptions },
  events: vercelMarketplaceEvents,
  create: createVercelMarketplace,
  env: [
    {
      key: "VERCEL_MARKETPLACE_CLIENT_ID",
      description:
        "The integration's client id from the Vercel dashboard; createVercelMarketplace() checks it as the audience of SSO and webhook tokens.",
    },
    {
      key: "VERCEL_MARKETPLACE_CLIENT_SECRET",
      description:
        "Server-only: the integration's client secret; it signs the webhook check and exchanges SSO codes.",
    },
  ],
  category: "developer",
  description:
    "Vercel Marketplace provider state: installations per configuration id, provisioned resources with their tenant and secret handles, access tokens sealed in Vault, plans, invoices kept by event time and meter reports sent to Vercel per period. Only the service role calls it; createVercelMarketplace() in better-supabase/blocks/vercel-marketplace serves the Partner API, verifies webhooks, exchanges SSO codes and reports usage.",
});
