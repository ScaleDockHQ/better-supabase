import {
  type RpcClient,
  defineBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { permissionsBlock } from "better-supabase/blocks/permissions";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { scoresBlock } from "better-supabase/blocks/scores";
import { enrollmentsBlock } from "better-supabase/blocks/enrollments";
import { activitiesBlock } from "better-supabase/blocks/activities";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { formsBlock } from "better-supabase/blocks/forms";
import { queueBlock } from "better-supabase/blocks/queue";
import { metricsBlock } from "better-supabase/blocks/metrics";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { contactsBlock } from "better-supabase/blocks/contacts";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { remindersBlock } from "better-supabase/blocks/reminders";
import { automationsBlock } from "better-supabase/blocks/automations";
import { settingsBlock } from "better-supabase/blocks/settings";
import { subjectsBlock } from "better-supabase/blocks/subjects";
import { teamsBlock } from "better-supabase/blocks/teams";

import { blockConfig } from "./customer-success.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  permissions: permissionsBlock,
  apiKeys: apiKeysBlock,
  audit: auditBlock,
  billing: billingBlock,
  scores: scoresBlock,
  enrollments: enrollmentsBlock,
  activities: activitiesBlock,
  entitlements: entitlementsBlock,
  forms: formsBlock,
  queue: queueBlock,
  metrics: metricsBlock,
  notifications: notificationsBlock,
  onboarding: onboardingBlock,
  organizations: organizationsBlock,
  outbox: outboxBlock,
  contacts: contactsBlock,
  profiles: profilesBlock,
  reminders: remindersBlock,
  automations: automationsBlock,
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
