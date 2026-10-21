import type { GeneratedBlocks, RpcClient } from "better-supabase/blocks";

import { createBlocks, rpcTransport } from "better-supabase/blocks";
import {
  createNotifications,
  notificationsBlock,
} from "better-supabase/blocks/notifications";
import * as v from "valibot";

/**
 * `blocks.<module>.api` in the Next.js example's config, which owns the
 * database.
 */
export const API_SCHEMA = "api";

/**
 * The entries of the Next.js example's `blocks.generated.ts` for the blocks
 * whose hooks read the client's `blocks` config. This app runs no `gen`.
 */
export const blockConfig = {
  comments: { schema: "better_supabase", api: API_SCHEMA, options: {} },
  tags: { schema: "better_supabase", api: API_SCHEMA, options: {} },
} as const satisfies GeneratedBlocks;

const Titled = v.object({ title: v.string() });

/**
 * The notification types the Next.js example sends, and the data each one
 * carries.
 */
const notificationTypes = { "test.sent": Titled, "workflow.message": Titled };

/**
 * The blocks as typed clients over the Data API, acting as the caller of
 * `supabase` (its token, so RLS and each function's checks apply).
 */
export function blocks(supabase: RpcClient) {
  return createBlocks(
    { transport: rpcTransport(supabase, { schema: API_SCHEMA }) },
    {
      notifications: notificationsBlock.using((options) =>
        createNotifications({ ...options, types: notificationTypes }),
      ),
    },
  );
}
