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
import { catalogBlock } from "better-supabase/blocks/catalog";
import { leaveBlock } from "better-supabase/blocks/leave";
import { ledgerBlock } from "better-supabase/blocks/ledger";
import { assetsBlock } from "better-supabase/blocks/assets";
import { enrollmentsBlock } from "better-supabase/blocks/enrollments";
import { expensesBlock } from "better-supabase/blocks/expenses";
import { employeesBlock } from "better-supabase/blocks/employees";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { inventoryBlock } from "better-supabase/blocks/inventory";
import { invoicesBlock } from "better-supabase/blocks/invoices";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { numberingBlock } from "better-supabase/blocks/numbering";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { ordersBlock } from "better-supabase/blocks/orders";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { contactsBlock } from "better-supabase/blocks/contacts";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { quotesBlock } from "better-supabase/blocks/quotes";
import { automationsBlock } from "better-supabase/blocks/automations";
import { savedViewsBlock } from "better-supabase/blocks/saved-views";
import { settingsBlock } from "better-supabase/blocks/settings";
import { subjectsBlock } from "better-supabase/blocks/subjects";
import { teamsBlock } from "better-supabase/blocks/teams";
import { timeTrackingBlock } from "better-supabase/blocks/time-tracking";

import { blockConfig } from "./erp.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  permissions: permissionsBlock,
  apiKeys: apiKeysBlock,
  approvals: approvalsBlock,
  audit: auditBlock,
  billing: billingBlock,
  catalog: catalogBlock,
  leave: leaveBlock,
  ledger: ledgerBlock,
  assets: assetsBlock,
  enrollments: enrollmentsBlock,
  expenses: expensesBlock,
  employees: employeesBlock,
  entitlements: entitlementsBlock,
  inventory: inventoryBlock,
  invoices: invoicesBlock,
  notifications: notificationsBlock,
  numbering: numberingBlock,
  onboarding: onboardingBlock,
  orders: ordersBlock,
  organizations: organizationsBlock,
  outbox: outboxBlock,
  contacts: contactsBlock,
  profiles: profilesBlock,
  quotes: quotesBlock,
  automations: automationsBlock,
  savedViews: savedViewsBlock,
  settings: settingsBlock,
  subjects: subjectsBlock,
  teams: teamsBlock,
  timeTracking: timeTrackingBlock,
});

/**
 * The blocks as typed clients, acting as the caller of `supabase`: its
 * token, so RLS and each function's checks apply.
 */
export function blocks(supabase: RpcClient) {
  return blockSet.create({ transport: rpcTransport(supabase) });
}
