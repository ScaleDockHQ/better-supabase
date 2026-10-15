import {
  type RpcClient,
  createBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { catalogBlock } from "better-supabase/blocks/catalog";
import { inventoryBlock } from "better-supabase/blocks/inventory";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { ordersBlock } from "better-supabase/blocks/orders";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { promotionsBlock } from "better-supabase/blocks/promotions";
import { teamsBlock } from "better-supabase/blocks/teams";

/**
 * The blocks as typed clients, acting as the caller of `supabase`: its
 * token, so RLS and each function's checks apply.
 */
export function blocks(supabase: RpcClient) {
  return createBlocks(
    { transport: rpcTransport(supabase) },
    {
      apiKeys: apiKeysBlock,
      audit: auditBlock,
      billing: billingBlock,
      catalog: catalogBlock,
      inventory: inventoryBlock,
      notifications: notificationsBlock,
      orders: ordersBlock,
      organizations: organizationsBlock,
      profiles: profilesBlock,
      promotions: promotionsBlock,
      teams: teamsBlock,
    },
  );
}
