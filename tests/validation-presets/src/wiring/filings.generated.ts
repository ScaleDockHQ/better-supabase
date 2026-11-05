import {
  type RpcClient,
  defineBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { saasBlock } from "better-supabase/blocks/saas";
import { governanceBlock } from "better-supabase/blocks/governance";
import { permissionsBlock } from "better-supabase/blocks/permissions";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { approvalsBlock } from "better-supabase/blocks/approvals";
import { attachmentsBlock } from "better-supabase/blocks/attachments";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { dataLifecycleBlock } from "better-supabase/blocks/data-lifecycle";
import { ledgerBlock } from "better-supabase/blocks/ledger";
import { enrollmentsBlock } from "better-supabase/blocks/enrollments";
import { shipmentsBlock } from "better-supabase/blocks/shipments";
import { casesBlock } from "better-supabase/blocks/cases";
import { legalEntitiesBlock } from "better-supabase/blocks/legal-entities";
import { documentTemplatesBlock } from "better-supabase/blocks/document-templates";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { signaturesBlock } from "better-supabase/blocks/signatures";
import { importsBlock } from "better-supabase/blocks/imports";
import { queueBlock } from "better-supabase/blocks/queue";
import { fieldHistoryBlock } from "better-supabase/blocks/field-history";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { numberingBlock } from "better-supabase/blocks/numbering";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { contactsBlock } from "better-supabase/blocks/contacts";
import { pipelinesBlock } from "better-supabase/blocks/pipelines";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { relationsBlock } from "better-supabase/blocks/relations";
import { remindersBlock } from "better-supabase/blocks/reminders";
import { settingsBlock } from "better-supabase/blocks/settings";
import { subjectsBlock } from "better-supabase/blocks/subjects";
import { teamsBlock } from "better-supabase/blocks/teams";
import { versionsBlock } from "better-supabase/blocks/versions";

import { blockConfig } from "./filings.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  saas: saasBlock,
  governance: governanceBlock,
  permissions: permissionsBlock,
  apiKeys: apiKeysBlock,
  approvals: approvalsBlock,
  attachments: attachmentsBlock,
  audit: auditBlock,
  billing: billingBlock,
  dataLifecycle: dataLifecycleBlock,
  ledger: ledgerBlock,
  enrollments: enrollmentsBlock,
  shipments: shipmentsBlock,
  cases: casesBlock,
  legalEntities: legalEntitiesBlock,
  documentTemplates: documentTemplatesBlock,
  entitlements: entitlementsBlock,
  signatures: signaturesBlock,
  imports: importsBlock,
  queue: queueBlock,
  fieldHistory: fieldHistoryBlock,
  notifications: notificationsBlock,
  numbering: numberingBlock,
  onboarding: onboardingBlock,
  organizations: organizationsBlock,
  outbox: outboxBlock,
  contacts: contactsBlock,
  pipelines: pipelinesBlock,
  profiles: profilesBlock,
  relations: relationsBlock,
  reminders: remindersBlock,
  settings: settingsBlock,
  subjects: subjectsBlock,
  teams: teamsBlock,
  versions: versionsBlock,
});

/**
 * The blocks as typed clients, acting as the caller of `supabase`: its
 * token, so RLS and each function's checks apply.
 */
export function blocks(supabase: RpcClient) {
  return blockSet.create({ transport: rpcTransport(supabase) });
}
