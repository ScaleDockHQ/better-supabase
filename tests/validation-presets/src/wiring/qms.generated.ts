import {
  type RpcClient,
  defineBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { permissionsBlock } from "better-supabase/blocks/permissions";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { approvalsBlock } from "better-supabase/blocks/approvals";
import { attachmentsBlock } from "better-supabase/blocks/attachments";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { commentsBlock } from "better-supabase/blocks/comments";
import { assetsBlock } from "better-supabase/blocks/assets";
import { moderationBlock } from "better-supabase/blocks/moderation";
import { enrollmentsBlock } from "better-supabase/blocks/enrollments";
import { dispatchBlock } from "better-supabase/blocks/dispatch";
import { complianceBlock } from "better-supabase/blocks/compliance";
import { acknowledgementsBlock } from "better-supabase/blocks/acknowledgements";
import { coursesBlock } from "better-supabase/blocks/courses";
import { postsBlock } from "better-supabase/blocks/posts";
import { qualificationsBlock } from "better-supabase/blocks/qualifications";
import { risksBlock } from "better-supabase/blocks/risks";
import { casesBlock } from "better-supabase/blocks/cases";
import { inspectionsBlock } from "better-supabase/blocks/inspections";
import { meetingsBlock } from "better-supabase/blocks/meetings";
import { maintenanceBlock } from "better-supabase/blocks/maintenance";
import { driveBlock } from "better-supabase/blocks/drive";
import { employeesBlock } from "better-supabase/blocks/employees";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { formsBlock } from "better-supabase/blocks/forms";
import { signaturesBlock } from "better-supabase/blocks/signatures";
import { messagingBlock } from "better-supabase/blocks/messaging";
import { metricsBlock } from "better-supabase/blocks/metrics";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { numberingBlock } from "better-supabase/blocks/numbering";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { contactsBlock } from "better-supabase/blocks/contacts";
import { pipelinesBlock } from "better-supabase/blocks/pipelines";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { reactionsBlock } from "better-supabase/blocks/reactions";
import { relationsBlock } from "better-supabase/blocks/relations";
import { settingsBlock } from "better-supabase/blocks/settings";
import { stateMachineBlock } from "better-supabase/blocks/state-machine";
import { subjectsBlock } from "better-supabase/blocks/subjects";
import { teamsBlock } from "better-supabase/blocks/teams";
import { versionsBlock } from "better-supabase/blocks/versions";
import { tasksBlock } from "better-supabase/blocks/tasks";

import { blockConfig } from "./qms.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  permissions: permissionsBlock,
  apiKeys: apiKeysBlock,
  approvals: approvalsBlock,
  attachments: attachmentsBlock,
  audit: auditBlock,
  billing: billingBlock,
  comments: commentsBlock,
  assets: assetsBlock,
  moderation: moderationBlock,
  enrollments: enrollmentsBlock,
  dispatch: dispatchBlock,
  compliance: complianceBlock,
  acknowledgements: acknowledgementsBlock,
  courses: coursesBlock,
  posts: postsBlock,
  qualifications: qualificationsBlock,
  risks: risksBlock,
  cases: casesBlock,
  inspections: inspectionsBlock,
  meetings: meetingsBlock,
  maintenance: maintenanceBlock,
  drive: driveBlock,
  employees: employeesBlock,
  entitlements: entitlementsBlock,
  forms: formsBlock,
  signatures: signaturesBlock,
  messaging: messagingBlock,
  metrics: metricsBlock,
  notifications: notificationsBlock,
  numbering: numberingBlock,
  onboarding: onboardingBlock,
  organizations: organizationsBlock,
  outbox: outboxBlock,
  contacts: contactsBlock,
  pipelines: pipelinesBlock,
  profiles: profilesBlock,
  reactions: reactionsBlock,
  relations: relationsBlock,
  settings: settingsBlock,
  stateMachine: stateMachineBlock,
  subjects: subjectsBlock,
  teams: teamsBlock,
  versions: versionsBlock,
  tasks: tasksBlock,
});

/**
 * The blocks as typed clients, acting as the caller of `supabase`: its
 * token, so RLS and each function's checks apply.
 */
export function blocks(supabase: RpcClient) {
  return blockSet.create({ transport: rpcTransport(supabase) });
}
