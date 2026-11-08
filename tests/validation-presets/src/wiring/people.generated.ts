import {
  type RpcClient,
  defineBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { saasBlock } from "better-supabase/blocks/saas";
import { recruitingBlock } from "better-supabase/blocks/recruiting";
import { permissionsBlock } from "better-supabase/blocks/permissions";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { approvalsBlock } from "better-supabase/blocks/approvals";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { calendarBlock } from "better-supabase/blocks/calendar";
import { documentsBlock } from "better-supabase/blocks/documents";
import { enrollmentsBlock } from "better-supabase/blocks/enrollments";
import { employeesBlock } from "better-supabase/blocks/employees";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { hiringBlock } from "better-supabase/blocks/hiring";
import { queueBlock } from "better-supabase/blocks/queue";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { pipelinesBlock } from "better-supabase/blocks/pipelines";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { relationsBlock } from "better-supabase/blocks/relations";
import { remindersBlock } from "better-supabase/blocks/reminders";
import { automationsBlock } from "better-supabase/blocks/automations";
import { settingsBlock } from "better-supabase/blocks/settings";
import { subjectsBlock } from "better-supabase/blocks/subjects";
import { teamsBlock } from "better-supabase/blocks/teams";
import { timeEntriesBlock } from "better-supabase/blocks/time-entries";

import { blockConfig } from "./people.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  saas: saasBlock,
  recruiting: recruitingBlock,
  permissions: permissionsBlock,
  apiKeys: apiKeysBlock,
  approvals: approvalsBlock,
  audit: auditBlock,
  billing: billingBlock,
  calendar: calendarBlock,
  documents: documentsBlock,
  enrollments: enrollmentsBlock,
  employees: employeesBlock,
  entitlements: entitlementsBlock,
  hiring: hiringBlock,
  queue: queueBlock,
  notifications: notificationsBlock,
  onboarding: onboardingBlock,
  organizations: organizationsBlock,
  outbox: outboxBlock,
  pipelines: pipelinesBlock,
  profiles: profilesBlock,
  relations: relationsBlock,
  reminders: remindersBlock,
  automations: automationsBlock,
  settings: settingsBlock,
  subjects: subjectsBlock,
  teams: teamsBlock,
  timeEntries: timeEntriesBlock,
});

/**
 * The blocks as typed clients, acting as the caller of `supabase`: its
 * token, so RLS and each function's checks apply.
 */
export function blocks(supabase: RpcClient) {
  return blockSet.create({ transport: rpcTransport(supabase) });
}
