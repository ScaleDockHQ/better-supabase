import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/**
 * `marketplace_installation.*`: the Vercel team's installation of the
 * integration.
 */
export interface MarketplaceInstallationEventData {
  readonly installationId: string;
  readonly configurationId: string;
  readonly teamId: string | null;
}

/** `marketplace_invoice.state_changed`: Vercel moved an invoice to a new state. */
export interface MarketplaceInvoiceEventData {
  readonly installationId: string;
  readonly invoiceId: string;
  readonly externalId: string;
  readonly state: string;
}

/** The events of the `vercel-marketplace` block: type to data. */
export type VercelMarketplaceEvents = {
  readonly "marketplace_installation.upserted": MarketplaceInstallationEventData;
  readonly "marketplace_installation.removed": MarketplaceInstallationEventData;
  readonly "marketplace_invoice.state_changed": MarketplaceInvoiceEventData;
};

/**
 * The `vercel-marketplace` block's event types, for its manifest and
 * `onBlockEvent`.
 */
export const vercelMarketplaceEvents: Events<VercelMarketplaceEvents> =
  defineEvents({
    "marketplace_installation.upserted":
      event<MarketplaceInstallationEventData>(),
    "marketplace_installation.removed":
      event<MarketplaceInstallationEventData>(),
    "marketplace_invoice.state_changed": event<MarketplaceInvoiceEventData>(),
  });
