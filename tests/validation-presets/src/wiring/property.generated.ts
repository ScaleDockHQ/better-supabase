import {
  type RpcClient,
  defineBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { accessBlock } from "better-supabase/blocks/access";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { attachmentsBlock } from "better-supabase/blocks/attachments";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { commentsBlock } from "better-supabase/blocks/comments";
import { ledgerBlock } from "better-supabase/blocks/ledger";
import { assetsBlock } from "better-supabase/blocks/assets";
import { enrollmentsBlock } from "better-supabase/blocks/enrollments";
import { guestsBlock } from "better-supabase/blocks/guests";
import { leasesBlock } from "better-supabase/blocks/leases";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { jobsBlock } from "better-supabase/blocks/jobs";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { partiesBlock } from "better-supabase/blocks/parties";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { remindersBlock } from "better-supabase/blocks/reminders";
import { settingsBlock } from "better-supabase/blocks/settings";
import { subjectsBlock } from "better-supabase/blocks/subjects";
import { teamsBlock } from "better-supabase/blocks/teams";

import { blockConfig } from "./property.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  access: accessBlock,
  apiKeys: apiKeysBlock,
  attachments: attachmentsBlock,
  audit: auditBlock,
  billing: billingBlock,
  comments: commentsBlock,
  ledger: ledgerBlock,
  assets: assetsBlock,
  enrollments: enrollmentsBlock,
  guests: guestsBlock,
  leases: leasesBlock,
  entitlements: entitlementsBlock,
  jobs: jobsBlock,
  notifications: notificationsBlock,
  onboarding: onboardingBlock,
  organizations: organizationsBlock,
  outbox: outboxBlock,
  parties: partiesBlock,
  profiles: profilesBlock,
  reminders: remindersBlock,
  settings: settingsBlock,
  subjects: subjectsBlock,
  teams: teamsBlock,
});

/**
 * The blocks as typed clients, acting as the caller of `supabase`: its
 * token, so RLS and each function's checks apply.
 */
export function blocks(supabase: RpcClient) {
  return blockSet.create({ transport: rpcTransport(supabase) });
}
