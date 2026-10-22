import {
  type RpcClient,
  defineBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { accessBlock } from "better-supabase/blocks/access";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { attachmentsBlock } from "better-supabase/blocks/attachments";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { catalogBlock } from "better-supabase/blocks/catalog";
import { ledgerBlock } from "better-supabase/blocks/ledger";
import { assetsBlock } from "better-supabase/blocks/assets";
import { enrollmentsBlock } from "better-supabase/blocks/enrollments";
import { dispatchBlock } from "better-supabase/blocks/dispatch";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { formsBlock } from "better-supabase/blocks/forms";
import { signaturesBlock } from "better-supabase/blocks/signatures";
import { inventoryBlock } from "better-supabase/blocks/inventory";
import { invoicesBlock } from "better-supabase/blocks/invoices";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { partiesBlock } from "better-supabase/blocks/parties";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { quotesBlock } from "better-supabase/blocks/quotes";
import { settingsBlock } from "better-supabase/blocks/settings";
import { subjectsBlock } from "better-supabase/blocks/subjects";
import { teamsBlock } from "better-supabase/blocks/teams";
import { versionsBlock } from "better-supabase/blocks/versions";

import { blockConfig } from "./field-service.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  access: accessBlock,
  apiKeys: apiKeysBlock,
  attachments: attachmentsBlock,
  audit: auditBlock,
  billing: billingBlock,
  catalog: catalogBlock,
  ledger: ledgerBlock,
  assets: assetsBlock,
  enrollments: enrollmentsBlock,
  dispatch: dispatchBlock,
  entitlements: entitlementsBlock,
  forms: formsBlock,
  signatures: signaturesBlock,
  inventory: inventoryBlock,
  invoices: invoicesBlock,
  notifications: notificationsBlock,
  onboarding: onboardingBlock,
  organizations: organizationsBlock,
  outbox: outboxBlock,
  parties: partiesBlock,
  profiles: profilesBlock,
  quotes: quotesBlock,
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
