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
import { documentsBlock } from "better-supabase/blocks/documents";
import { ledgerBlock } from "better-supabase/blocks/ledger";
import { enrollmentsBlock } from "better-supabase/blocks/enrollments";
import { billableTimeBlock } from "better-supabase/blocks/billable-time";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { signaturesBlock } from "better-supabase/blocks/signatures";
import { invoicesBlock } from "better-supabase/blocks/invoices";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { contactsBlock } from "better-supabase/blocks/contacts";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { settingsBlock } from "better-supabase/blocks/settings";
import { subjectsBlock } from "better-supabase/blocks/subjects";
import { teamsBlock } from "better-supabase/blocks/teams";
import { timeTrackingBlock } from "better-supabase/blocks/time-tracking";
import { versionsBlock } from "better-supabase/blocks/versions";

import { blockConfig } from "./legal.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  permissions: permissionsBlock,
  apiKeys: apiKeysBlock,
  approvals: approvalsBlock,
  audit: auditBlock,
  billing: billingBlock,
  documents: documentsBlock,
  ledger: ledgerBlock,
  enrollments: enrollmentsBlock,
  billableTime: billableTimeBlock,
  entitlements: entitlementsBlock,
  signatures: signaturesBlock,
  invoices: invoicesBlock,
  notifications: notificationsBlock,
  onboarding: onboardingBlock,
  organizations: organizationsBlock,
  outbox: outboxBlock,
  contacts: contactsBlock,
  profiles: profilesBlock,
  settings: settingsBlock,
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
