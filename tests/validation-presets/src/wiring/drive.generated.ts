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
import { enrollmentsBlock } from "better-supabase/blocks/enrollments";
import { driveBlock } from "better-supabase/blocks/drive";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { searchBlock } from "better-supabase/blocks/search";
import { settingsBlock } from "better-supabase/blocks/settings";
import { shareLinksBlock } from "better-supabase/blocks/share-links";
import { subjectsBlock } from "better-supabase/blocks/subjects";
import { teamsBlock } from "better-supabase/blocks/teams";
import { trashBlock } from "better-supabase/blocks/trash";
import { versionsBlock } from "better-supabase/blocks/versions";

import { blockConfig } from "./drive.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  permissions: permissionsBlock,
  apiKeys: apiKeysBlock,
  attachments: attachmentsBlock,
  audit: auditBlock,
  billing: billingBlock,
  enrollments: enrollmentsBlock,
  drive: driveBlock,
  entitlements: entitlementsBlock,
  notifications: notificationsBlock,
  onboarding: onboardingBlock,
  organizations: organizationsBlock,
  outbox: outboxBlock,
  profiles: profilesBlock,
  search: searchBlock,
  settings: settingsBlock,
  shareLinks: shareLinksBlock,
  subjects: subjectsBlock,
  teams: teamsBlock,
  trash: trashBlock,
  versions: versionsBlock,
});

/**
 * The blocks as typed clients, acting as the caller of `supabase`: its
 * token, so RLS and each function's checks apply.
 */
export function blocks(supabase: RpcClient) {
  return blockSet.create({ transport: rpcTransport(supabase) });
}
