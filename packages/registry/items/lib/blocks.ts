import {
  type RpcClient,
  createBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { auditBlock } from "better-supabase/blocks/audit";
import {
  createNotifications,
  notificationsBlock,
} from "better-supabase/blocks/notifications";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { searchBlock } from "better-supabase/blocks/search";

import { notificationTypes } from "@/lib/notification-types";

/** The schema the blocks expose through the Data API (`sql.api` in the config). */
export const API_SCHEMA = "api";

/**
 * The blocks as typed clients over the Data API, acting as the caller of
 * `supabase`: its token, so RLS and each function's checks apply. Pass the
 * server client in a server action and the browser or native client in a
 * hook. Add a block here after `npx better-supabase sql add <block>`.
 */
export function blocks(supabase: RpcClient) {
  return createBlocks(
    {
      transport: rpcTransport(supabase, { schema: API_SCHEMA }),
      schema: API_SCHEMA,
    },
    {
      organizations: organizationsBlock,
      audit: auditBlock,
      search: searchBlock,
      notifications: notificationsBlock.using((options) =>
        createNotifications({ ...options, types: notificationTypes }),
      ),
    },
  );
}
