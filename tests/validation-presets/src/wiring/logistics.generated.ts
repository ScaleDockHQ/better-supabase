import {
  type RpcClient,
  defineBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { permissionsBlock } from "better-supabase/blocks/permissions";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { catalogBlock } from "better-supabase/blocks/catalog";
import { assetsBlock } from "better-supabase/blocks/assets";
import { enrollmentsBlock } from "better-supabase/blocks/enrollments";
import { shipmentsBlock } from "better-supabase/blocks/shipments";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { ordersBlock } from "better-supabase/blocks/orders";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { contactsBlock } from "better-supabase/blocks/contacts";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { settingsBlock } from "better-supabase/blocks/settings";
import { teamsBlock } from "better-supabase/blocks/teams";

import { blockConfig } from "./logistics.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  permissions: permissionsBlock,
  apiKeys: apiKeysBlock,
  audit: auditBlock,
  billing: billingBlock,
  catalog: catalogBlock,
  assets: assetsBlock,
  enrollments: enrollmentsBlock,
  shipments: shipmentsBlock,
  entitlements: entitlementsBlock,
  notifications: notificationsBlock,
  onboarding: onboardingBlock,
  orders: ordersBlock,
  organizations: organizationsBlock,
  outbox: outboxBlock,
  contacts: contactsBlock,
  profiles: profilesBlock,
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
