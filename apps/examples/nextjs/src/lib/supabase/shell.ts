import { defineBlocks } from "better-supabase/blocks";
import { createNotifications } from "better-supabase/blocks/notifications";

import {
  notificationTypes,
  renderNotification,
} from "../../features/notifications/notification-types.ts";
import { app } from "./app.ts";
import { blockConfig } from "./blocks.config.ts";
import { shellInstances } from "./blocks.shell.ts";

/**
 * The app with the blocks the page shell reads (`gen.serverBlocks.shell`). The
 * layout and the pages that read only the app's own tables build their server
 * from this, so they bundle no other block (ADR 0542). Notifications take the
 * app's types here as in `index.ts`. Server only.
 */
export const betterSupabaseShell = app.blocks(
  defineBlocks(blockConfig, {
    ...shellInstances,
    notifications: shellInstances.notifications.using((options) =>
      createNotifications({
        ...options,
        types: notificationTypes,
        render: renderNotification,
      }),
    ),
  }),
);
