import {
  type RpcClient,
  createBlocks,
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
import { settingsBlock } from "better-supabase/blocks/settings";
import { usageBlock } from "better-supabase/blocks/usage";
import { workflowsBlock } from "better-supabase/blocks/workflows";

import {
  notificationTypes,
  renderNotification,
} from "@/features/notifications/notification-types";
import { gettingStarted } from "@/features/onboarding/checklist";
import { settings } from "@/features/settings/settings-definition";
import { metrics } from "@/metrics";

/** `blocks.<module>.api` in better-supabase.config.ts. */
const API_SCHEMA = "api";

/**
 * The SQL modules as typed clients over the Data API, acting as the caller
 * of `supabase` (its token, so RLS and each function's checks apply).
 */
export function blocks(supabase: RpcClient) {
  const transport = rpcTransport(supabase, { schema: API_SCHEMA });
  const built = createBlocks(
    { transport, schema: API_SCHEMA },
    {
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
      onboarding: onboardingBlock.using((options) =>
        gettingStarted.connect(options),
      ),
      settings: settingsBlock.using((options) => settings.connect(options)),
    },
  );
  return {
    ...built,
    /** A module function without a typed client, such as `flag_enabled`. */
    call: (fn: string, args: Parameters<typeof transport.call>[2]) =>
      transport.call(API_SCHEMA, fn, args),
  };
}
