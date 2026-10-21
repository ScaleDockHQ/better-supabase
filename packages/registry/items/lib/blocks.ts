import type { RpcClient } from "better-supabase/blocks";

import { defineBlocks, rpcTransport } from "better-supabase/blocks";
import { auditBlock } from "better-supabase/blocks/audit";
import {
  createNotifications,
  notificationsBlock,
} from "better-supabase/blocks/notifications";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { searchBlock } from "better-supabase/blocks/search";

import { notificationTypes } from "@/lib/notification-types";
import { blockConfig } from "@/lib/supabase/blocks.generated";

/**
 * The blocks the app uses. Each one's schema (the API schema when `sql.api` is
 * set) and the options its SQL half shares come from `blocks.generated.ts`,
 * which `better-supabase gen` writes from the config. Add a block here after
 * `npx better-supabase add <block>`.
 */
export const blockSet = defineBlocks(blockConfig, {
  organizations: organizationsBlock,
  audit: auditBlock,
  search: searchBlock,
  notifications: notificationsBlock.using((options) =>
    createNotifications({ ...options, types: notificationTypes }),
  ),
});

/**
 * The blocks as typed clients over the Data API, acting as the caller of
 * `supabase`: its token, so RLS and each function's checks apply. Pass the
 * server client in a server action and the browser or native client in a hook.
 */
export function blocks(supabase: RpcClient) {
  return blockSet.create({ transport: rpcTransport(supabase) });
}
