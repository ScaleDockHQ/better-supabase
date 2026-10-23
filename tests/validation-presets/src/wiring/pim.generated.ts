import {
  type RpcClient,
  defineBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { permissionsBlock } from "better-supabase/blocks/permissions";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { attachmentsBlock } from "better-supabase/blocks/attachments";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { bulkBlock } from "better-supabase/blocks/bulk";
import { catalogBlock } from "better-supabase/blocks/catalog";
import { customFieldsBlock } from "better-supabase/blocks/custom-fields";
import { enrollmentsBlock } from "better-supabase/blocks/enrollments";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { importsBlock } from "better-supabase/blocks/imports";
import { queueBlock } from "better-supabase/blocks/queue";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { savedViewsBlock } from "better-supabase/blocks/saved-views";
import { searchBlock } from "better-supabase/blocks/search";
import { settingsBlock } from "better-supabase/blocks/settings";
import { subjectsBlock } from "better-supabase/blocks/subjects";
import { tagsBlock } from "better-supabase/blocks/tags";
import { teamsBlock } from "better-supabase/blocks/teams";

import { blockConfig } from "./pim.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  permissions: permissionsBlock,
  apiKeys: apiKeysBlock,
  attachments: attachmentsBlock,
  audit: auditBlock,
  billing: billingBlock,
  bulk: bulkBlock,
  catalog: catalogBlock,
  customFields: customFieldsBlock,
  enrollments: enrollmentsBlock,
  entitlements: entitlementsBlock,
  imports: importsBlock,
  queue: queueBlock,
  notifications: notificationsBlock,
  onboarding: onboardingBlock,
  organizations: organizationsBlock,
  outbox: outboxBlock,
  profiles: profilesBlock,
  savedViews: savedViewsBlock,
  search: searchBlock,
  settings: settingsBlock,
  subjects: subjectsBlock,
  tags: tagsBlock,
  teams: teamsBlock,
});

/**
 * The blocks as typed clients, acting as the caller of `supabase`: its
 * token, so RLS and each function's checks apply.
 */
export function blocks(supabase: RpcClient) {
  return blockSet.create({ transport: rpcTransport(supabase) });
}
