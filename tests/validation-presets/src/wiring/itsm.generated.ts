import {
  type RpcClient,
  defineBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { permissionsBlock } from "better-supabase/blocks/permissions";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { approvalsBlock } from "better-supabase/blocks/approvals";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { assetsBlock } from "better-supabase/blocks/assets";
import { enrollmentsBlock } from "better-supabase/blocks/enrollments";
import { incidentsBlock } from "better-supabase/blocks/incidents";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { queueBlock } from "better-supabase/blocks/queue";
import { knowledgeBlock } from "better-supabase/blocks/knowledge";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { pipelinesBlock } from "better-supabase/blocks/pipelines";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { relationsBlock } from "better-supabase/blocks/relations";
import { settingsBlock } from "better-supabase/blocks/settings";
import { slaBlock } from "better-supabase/blocks/sla";
import { subjectsBlock } from "better-supabase/blocks/subjects";
import { teamsBlock } from "better-supabase/blocks/teams";
import { tasksBlock } from "better-supabase/blocks/tasks";

import { blockConfig } from "./itsm.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  permissions: permissionsBlock,
  apiKeys: apiKeysBlock,
  approvals: approvalsBlock,
  audit: auditBlock,
  billing: billingBlock,
  assets: assetsBlock,
  enrollments: enrollmentsBlock,
  incidents: incidentsBlock,
  entitlements: entitlementsBlock,
  queue: queueBlock,
  knowledge: knowledgeBlock,
  notifications: notificationsBlock,
  onboarding: onboardingBlock,
  organizations: organizationsBlock,
  outbox: outboxBlock,
  pipelines: pipelinesBlock,
  profiles: profilesBlock,
  relations: relationsBlock,
  settings: settingsBlock,
  sla: slaBlock,
  subjects: subjectsBlock,
  teams: teamsBlock,
  tasks: tasksBlock,
});

/**
 * The blocks as typed clients, acting as the caller of `supabase`: its
 * token, so RLS and each function's checks apply.
 */
export function blocks(supabase: RpcClient) {
  return blockSet.create({ transport: rpcTransport(supabase) });
}
