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
import { bookingsBlock } from "better-supabase/blocks/bookings";
import { calendarBlock } from "better-supabase/blocks/calendar";
import { carePlansBlock } from "better-supabase/blocks/care-plans";
import { dataLifecycleBlock } from "better-supabase/blocks/data-lifecycle";
import { enrollmentsBlock } from "better-supabase/blocks/enrollments";
import { guestsBlock } from "better-supabase/blocks/guests";
import { acknowledgementsBlock } from "better-supabase/blocks/acknowledgements";
import { coursesBlock } from "better-supabase/blocks/courses";
import { qualificationsBlock } from "better-supabase/blocks/qualifications";
import { casesBlock } from "better-supabase/blocks/cases";
import { fundingBlock } from "better-supabase/blocks/funding";
import { shiftsBlock } from "better-supabase/blocks/shifts";
import { consentsBlock } from "better-supabase/blocks/consents";
import { observationsBlock } from "better-supabase/blocks/observations";
import { medicationsBlock } from "better-supabase/blocks/medications";
import { driveBlock } from "better-supabase/blocks/drive";
import { activitiesBlock } from "better-supabase/blocks/activities";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { formsBlock } from "better-supabase/blocks/forms";
import { signaturesBlock } from "better-supabase/blocks/signatures";
import { queueBlock } from "better-supabase/blocks/queue";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { numberingBlock } from "better-supabase/blocks/numbering";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { contactsBlock } from "better-supabase/blocks/contacts";
import { pipelinesBlock } from "better-supabase/blocks/pipelines";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { remindersBlock } from "better-supabase/blocks/reminders";
import { settingsBlock } from "better-supabase/blocks/settings";
import { stateMachineBlock } from "better-supabase/blocks/state-machine";
import { subjectsBlock } from "better-supabase/blocks/subjects";
import { teamsBlock } from "better-supabase/blocks/teams";
import { timeTrackingBlock } from "better-supabase/blocks/time-tracking";
import { versionsBlock } from "better-supabase/blocks/versions";

import { blockConfig } from "./care.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  permissions: permissionsBlock,
  apiKeys: apiKeysBlock,
  approvals: approvalsBlock,
  attachments: attachmentsBlock,
  audit: auditBlock,
  billing: billingBlock,
  bookings: bookingsBlock,
  calendar: calendarBlock,
  carePlans: carePlansBlock,
  dataLifecycle: dataLifecycleBlock,
  enrollments: enrollmentsBlock,
  guests: guestsBlock,
  acknowledgements: acknowledgementsBlock,
  courses: coursesBlock,
  qualifications: qualificationsBlock,
  cases: casesBlock,
  funding: fundingBlock,
  shifts: shiftsBlock,
  consents: consentsBlock,
  observations: observationsBlock,
  medications: medicationsBlock,
  drive: driveBlock,
  activities: activitiesBlock,
  entitlements: entitlementsBlock,
  forms: formsBlock,
  signatures: signaturesBlock,
  queue: queueBlock,
  notifications: notificationsBlock,
  numbering: numberingBlock,
  onboarding: onboardingBlock,
  organizations: organizationsBlock,
  outbox: outboxBlock,
  contacts: contactsBlock,
  pipelines: pipelinesBlock,
  profiles: profilesBlock,
  reminders: remindersBlock,
  settings: settingsBlock,
  stateMachine: stateMachineBlock,
  subjects: subjectsBlock,
  teams: teamsBlock,
  timeTracking: timeTrackingBlock,
  versions: versionsBlock,
});

/**
 * The blocks as typed clients, acting as the caller of `supabase`: its
 * token, so RLS and each function's checks apply.
 */
export function blocks(supabase: RpcClient) {
  return blockSet.create({ transport: rpcTransport(supabase) });
}
