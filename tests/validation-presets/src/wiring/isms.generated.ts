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
import { complianceBlock } from "better-supabase/blocks/compliance";
import { acknowledgementsBlock } from "better-supabase/blocks/acknowledgements";
import { risksBlock } from "better-supabase/blocks/risks";
import { casesBlock } from "better-supabase/blocks/cases";
import { inspectionsBlock } from "better-supabase/blocks/inspections";
import { driveBlock } from "better-supabase/blocks/drive";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { formsBlock } from "better-supabase/blocks/forms";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { pipelinesBlock } from "better-supabase/blocks/pipelines";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { settingsBlock } from "better-supabase/blocks/settings";
import { subjectsBlock } from "better-supabase/blocks/subjects";
import { teamsBlock } from "better-supabase/blocks/teams";
import { versionsBlock } from "better-supabase/blocks/versions";

import { blockConfig } from "./isms.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  permissions: permissionsBlock,
  apiKeys: apiKeysBlock,
  attachments: attachmentsBlock,
  audit: auditBlock,
  billing: billingBlock,
  enrollments: enrollmentsBlock,
  compliance: complianceBlock,
  acknowledgements: acknowledgementsBlock,
  risks: risksBlock,
  cases: casesBlock,
  inspections: inspectionsBlock,
  drive: driveBlock,
  entitlements: entitlementsBlock,
  forms: formsBlock,
  notifications: notificationsBlock,
  onboarding: onboardingBlock,
  organizations: organizationsBlock,
  outbox: outboxBlock,
  pipelines: pipelinesBlock,
  profiles: profilesBlock,
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
