import {
  type RpcClient,
  defineBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { auditBlock } from "better-supabase/blocks/audit";
import { commentsBlock } from "better-supabase/blocks/comments";
import { inboxBlock } from "better-supabase/blocks/inbox";
import { createMetrics, metricsBlock } from "better-supabase/blocks/metrics";
import {
  createNotifications,
  notificationsBlock,
} from "better-supabase/blocks/notifications";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { searchBlock } from "better-supabase/blocks/search";
import { createSettings, settingsBlock } from "better-supabase/blocks/settings";
import { usageBlock } from "better-supabase/blocks/usage";
import { workflowsBlock } from "better-supabase/blocks/workflows";

import {
  notificationTypes,
  renderNotification,
} from "@/features/notifications/notification-types";
import { settings } from "@/features/settings/settings-definition";
import { blockConfig } from "@/lib/supabase/blocks.generated";
import { metrics } from "@/metrics";

/** `sql.api` in better-supabase.config.ts, as `gen` wrote it. */
const API_SCHEMA = blockConfig.organizations.api;

/**
 * The blocks the app uses. Each one's schema (the `api` wrappers) and the
 * options its SQL half shares come from `blocks.generated.ts`.
 */
const blockSet = defineBlocks(blockConfig, {
  organizations: organizationsBlock,
  apiKeys: apiKeysBlock,
  audit: auditBlock,
  comments: commentsBlock,
  notifications: notificationsBlock.using((options) =>
    createNotifications({
      ...options,
      types: notificationTypes,
      render: renderNotification,
    }),
  ),
  inbox: inboxBlock,
  search: searchBlock,
  metrics: metricsBlock.using((options) =>
    createMetrics({ ...options, metrics }),
  ),
  usage: usageBlock,
  workflows: workflowsBlock,
  onboarding: onboardingBlock,
  settings: settingsBlock.using((options) =>
    createSettings({ ...options, settings }),
  ),
});

/**
 * The blocks as typed clients over the Data API, acting as the caller of
 * `supabase` (its token, so RLS and each function's checks apply).
 */
export function blocks(supabase: RpcClient) {
  const transport = rpcTransport(supabase);
  const built = blockSet.create({ transport });

  return {
    ...built,
    /** A module function without a typed client, such as `flag_enabled`. */
    call: (fn: string, args: Parameters<typeof transport.call>[2]) =>
      transport.call(API_SCHEMA, fn, args),
  };
}
