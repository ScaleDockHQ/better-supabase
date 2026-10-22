import {
  type RpcClient,
  defineBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { accessBlock } from "better-supabase/blocks/access";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { catalogBlock } from "better-supabase/blocks/catalog";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { invoicesBlock } from "better-supabase/blocks/invoices";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { ordersBlock } from "better-supabase/blocks/orders";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { partiesBlock } from "better-supabase/blocks/parties";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { reactionsBlock } from "better-supabase/blocks/reactions";
import { settingsBlock } from "better-supabase/blocks/settings";
import { shareLinksBlock } from "better-supabase/blocks/share-links";
import { subjectsBlock } from "better-supabase/blocks/subjects";
import { teamsBlock } from "better-supabase/blocks/teams";

import { blockConfig } from "./marketplace.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  access: accessBlock,
  apiKeys: apiKeysBlock,
  audit: auditBlock,
  billing: billingBlock,
  catalog: catalogBlock,
  entitlements: entitlementsBlock,
  invoices: invoicesBlock,
  notifications: notificationsBlock,
  onboarding: onboardingBlock,
  orders: ordersBlock,
  organizations: organizationsBlock,
  outbox: outboxBlock,
  parties: partiesBlock,
  profiles: profilesBlock,
  reactions: reactionsBlock,
  settings: settingsBlock,
  shareLinks: shareLinksBlock,
  subjects: subjectsBlock,
  teams: teamsBlock,
});

/**
 * The blocks as typed clients, acting as the caller of `supabase`: its
 * token, so RLS and each function's checks apply.
 */
export function blocks(supabase: RpcClient) {
  return blockSet.create({ transport: rpcTransport(supabase) });
}
