import {
  type RpcClient,
  defineBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { accessBlock } from "better-supabase/blocks/access";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { bookingsBlock } from "better-supabase/blocks/bookings";
import { catalogBlock } from "better-supabase/blocks/catalog";
import { ledgerBlock } from "better-supabase/blocks/ledger";
import { enrollmentsBlock } from "better-supabase/blocks/enrollments";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { inventoryBlock } from "better-supabase/blocks/inventory";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { ordersBlock } from "better-supabase/blocks/orders";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { promotionsBlock } from "better-supabase/blocks/promotions";
import { settingsBlock } from "better-supabase/blocks/settings";
import { teamsBlock } from "better-supabase/blocks/teams";

import { blockConfig } from "./pos.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  access: accessBlock,
  apiKeys: apiKeysBlock,
  audit: auditBlock,
  billing: billingBlock,
  bookings: bookingsBlock,
  catalog: catalogBlock,
  ledger: ledgerBlock,
  enrollments: enrollmentsBlock,
  entitlements: entitlementsBlock,
  inventory: inventoryBlock,
  notifications: notificationsBlock,
  onboarding: onboardingBlock,
  orders: ordersBlock,
  organizations: organizationsBlock,
  outbox: outboxBlock,
  profiles: profilesBlock,
  promotions: promotionsBlock,
  settings: settingsBlock,
  teams: teamsBlock,
});

/**
 * The blocks as typed clients, acting as the caller of `supabase`: its
 * token, so RLS and each function's checks apply.
 */
export function blocks(supabase: RpcClient) {
  return blockSet.create({ transport: rpcTransport(supabase) });
}
