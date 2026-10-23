import {
  type RpcClient,
  defineBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { permissionsBlock } from "better-supabase/blocks/permissions";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { commentsBlock } from "better-supabase/blocks/comments";
import { customFieldsBlock } from "better-supabase/blocks/custom-fields";
import { dealsBlock } from "better-supabase/blocks/deals";
import { scoresBlock } from "better-supabase/blocks/scores";
import { enrollmentsBlock } from "better-supabase/blocks/enrollments";
import { sequencesBlock } from "better-supabase/blocks/sequences";
import { leadScoringBlock } from "better-supabase/blocks/lead-scoring";
import { activitiesBlock } from "better-supabase/blocks/activities";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { messagingBlock } from "better-supabase/blocks/messaging";
import { timelineBlock } from "better-supabase/blocks/timeline";
import { mailSyncBlock } from "better-supabase/blocks/mail-sync";
import { segmentsBlock } from "better-supabase/blocks/segments";
import { assignmentBlock } from "better-supabase/blocks/assignment";
import { enrichmentBlock } from "better-supabase/blocks/enrichment";
import { forecastsBlock } from "better-supabase/blocks/forecasts";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { contactsBlock } from "better-supabase/blocks/contacts";
import { pipelinesBlock } from "better-supabase/blocks/pipelines";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { quotesBlock } from "better-supabase/blocks/quotes";
import { automationsBlock } from "better-supabase/blocks/automations";
import { savedViewsBlock } from "better-supabase/blocks/saved-views";
import { searchBlock } from "better-supabase/blocks/search";
import { settingsBlock } from "better-supabase/blocks/settings";
import { subjectsBlock } from "better-supabase/blocks/subjects";
import { tagsBlock } from "better-supabase/blocks/tags";
import { goalsBlock } from "better-supabase/blocks/goals";
import { teamsBlock } from "better-supabase/blocks/teams";

import { blockConfig } from "./crm.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  permissions: permissionsBlock,
  apiKeys: apiKeysBlock,
  audit: auditBlock,
  billing: billingBlock,
  comments: commentsBlock,
  customFields: customFieldsBlock,
  deals: dealsBlock,
  scores: scoresBlock,
  enrollments: enrollmentsBlock,
  sequences: sequencesBlock,
  leadScoring: leadScoringBlock,
  activities: activitiesBlock,
  entitlements: entitlementsBlock,
  messaging: messagingBlock,
  timeline: timelineBlock,
  mailSync: mailSyncBlock,
  segments: segmentsBlock,
  assignment: assignmentBlock,
  enrichment: enrichmentBlock,
  forecasts: forecastsBlock,
  notifications: notificationsBlock,
  onboarding: onboardingBlock,
  organizations: organizationsBlock,
  outbox: outboxBlock,
  contacts: contactsBlock,
  pipelines: pipelinesBlock,
  profiles: profilesBlock,
  quotes: quotesBlock,
  automations: automationsBlock,
  savedViews: savedViewsBlock,
  search: searchBlock,
  settings: settingsBlock,
  subjects: subjectsBlock,
  tags: tagsBlock,
  goals: goalsBlock,
  teams: teamsBlock,
});

/**
 * The blocks as typed clients, acting as the caller of `supabase`: its
 * token, so RLS and each function's checks apply.
 */
export function blocks(supabase: RpcClient) {
  return blockSet.create({ transport: rpcTransport(supabase) });
}
