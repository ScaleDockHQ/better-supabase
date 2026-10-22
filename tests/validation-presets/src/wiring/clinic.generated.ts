import {
  type RpcClient,
  defineBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { permissionsBlock } from "better-supabase/blocks/permissions";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { bookingsBlock } from "better-supabase/blocks/bookings";
import { calendarBlock } from "better-supabase/blocks/calendar";
import { customFieldsBlock } from "better-supabase/blocks/custom-fields";
import { enrollmentsBlock } from "better-supabase/blocks/enrollments";
import { guestsBlock } from "better-supabase/blocks/guests";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { formsBlock } from "better-supabase/blocks/forms";
import { signaturesBlock } from "better-supabase/blocks/signatures";
import { queueBlock } from "better-supabase/blocks/queue";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { remindersBlock } from "better-supabase/blocks/reminders";
import { settingsBlock } from "better-supabase/blocks/settings";
import { teamsBlock } from "better-supabase/blocks/teams";
import { templatesBlock } from "better-supabase/blocks/templates";
import { versionsBlock } from "better-supabase/blocks/versions";

import { blockConfig } from "./clinic.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  permissions: permissionsBlock,
  apiKeys: apiKeysBlock,
  audit: auditBlock,
  billing: billingBlock,
  bookings: bookingsBlock,
  calendar: calendarBlock,
  customFields: customFieldsBlock,
  enrollments: enrollmentsBlock,
  guests: guestsBlock,
  entitlements: entitlementsBlock,
  forms: formsBlock,
  signatures: signaturesBlock,
  queue: queueBlock,
  notifications: notificationsBlock,
  onboarding: onboardingBlock,
  organizations: organizationsBlock,
  outbox: outboxBlock,
  profiles: profilesBlock,
  reminders: remindersBlock,
  settings: settingsBlock,
  teams: teamsBlock,
  templates: templatesBlock,
  versions: versionsBlock,
});

/**
 * The blocks as typed clients, acting as the caller of `supabase`: its
 * token, so RLS and each function's checks apply.
 */
export function blocks(supabase: RpcClient) {
  return blockSet.create({ transport: rpcTransport(supabase) });
}
