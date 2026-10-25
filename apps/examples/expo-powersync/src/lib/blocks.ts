import type { RpcClient } from "better-supabase/blocks";

import { defineBlocks, rpcTransport } from "better-supabase/blocks";
import { createNotifications } from "better-supabase/blocks/notifications";
import * as v from "valibot";

import { blockConfig, blocks as generated } from "./supabase/blocks.generated";

export { blockConfig } from "./supabase/blocks.generated";

/** `sql.api` in the config: the schema the block functions are wrapped in. */
export const API_SCHEMA = blockConfig.notifications.api;

const Titled = v.object({ title: v.string() });

/**
 * The notification types the Next.js example sends, and the data each one
 * carries.
 */
const notificationTypes = { "test.sent": Titled, "workflow.message": Titled };

/**
 * The generated block instances, with the notification types set. On native,
 * PowerSync serves `notifications` offline (`gen.powersync.instances`); the
 * others need the network.
 */
const blockSet = defineBlocks(blockConfig, {
  ...generated,
  notifications: generated.notifications.using((options) =>
    createNotifications({ ...options, types: notificationTypes }),
  ),
});

/**
 * The blocks as typed clients over the Data API, acting as the caller of
 * `supabase` (its token, so RLS and each function's checks apply).
 */
export function blocks(supabase: RpcClient) {
  return blockSet.create({
    transport: rpcTransport(supabase, { schema: API_SCHEMA }),
  });
}
