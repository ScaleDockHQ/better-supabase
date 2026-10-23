import type { DbOf } from "better-supabase";

import { defineSupabase } from "better-supabase";
import { defineBlocks } from "better-supabase/blocks";
import { createMetrics } from "better-supabase/blocks/metrics";
import { createNotifications } from "better-supabase/blocks/notifications";
import { createSettings } from "better-supabase/blocks/settings";
import { Temporal } from "temporal-polyfill";

import {
  notificationTypes,
  renderNotification,
} from "../../features/notifications/notification-types.ts";
import { settings } from "../../features/settings/settings-definition.ts";
import { metrics } from "../../metrics.ts";
import { toAppError } from "../app-error.ts";
import { avatars, logos } from "../buckets.ts";
import { Claims, Profile } from "../claims.ts";
import { blockConfig, blocks } from "./blocks.generated.ts";
import { schema } from "./generated.ts";
import { providers } from "./providers.ts";

export type { Functions, Models } from "./generated.ts";

/**
 * The block instances as `db.<instance>`: the generated map, with the blocks
 * that take app definitions (notification types, metrics, settings) and the
 * outbox's event source set here.
 */
const blockSet = defineBlocks(blockConfig, {
  ...blocks,
  ...providers,
  notifications: blocks.notifications.using((options) =>
    createNotifications({
      ...options,
      types: notificationTypes,
      render: renderNotification,
    }),
  ),
  metrics: blocks.metrics.using((options) =>
    createMetrics({ ...options, metrics }),
  ),
  settings: blocks.settings.using((options) =>
    createSettings({ ...options, settings }),
  ),
  outbox: blocks.outbox.with({ source: "https://example.bettersupabase.com" }),
});

/**
 * `.orThrow()` throws an `AppError`; results keep their `DbError`. `maxRows`
 * matches `[api] max_rows` in `supabase/config.toml`. Node 24 and Safari have
 * no `Temporal`, which the blocks return times as.
 */
export const betterSupabase = defineSupabase(schema, {
  maxRows: 1000,
  temporal: Temporal,
})
  .claims(Claims)
  .userMetadata(Profile)
  .mapError(toAppError)
  .buckets({ avatars, logos })
  .blocks(blockSet);

/** The `Db` the app's requests get, with every block instance on it. */
export type AppDb = DbOf<typeof betterSupabase>;
