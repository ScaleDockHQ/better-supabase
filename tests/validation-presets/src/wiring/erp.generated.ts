import {
  type RpcClient,
  defineBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { saasBlock } from "better-supabase/blocks/saas";
import { financeBlock } from "better-supabase/blocks/finance";
import { permissionsBlock } from "better-supabase/blocks/permissions";
import { accountingBlock } from "better-supabase/blocks/accounting";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { approvalsBlock } from "better-supabase/blocks/approvals";
import { attachmentsBlock } from "better-supabase/blocks/attachments";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { catalogBlock } from "better-supabase/blocks/catalog";
import { customFieldsBlock } from "better-supabase/blocks/custom-fields";
import { leaveBlock } from "better-supabase/blocks/leave";
import { ledgerBlock } from "better-supabase/blocks/ledger";
import { assetsBlock } from "better-supabase/blocks/assets";
import { enrollmentsBlock } from "better-supabase/blocks/enrollments";
import { expensesBlock } from "better-supabase/blocks/expenses";
import { rfqsBlock } from "better-supabase/blocks/rfqs";
import { periodsBlock } from "better-supabase/blocks/periods";
import { bankingBlock } from "better-supabase/blocks/banking";
import { legalEntitiesBlock } from "better-supabase/blocks/legal-entities";
import { payrollExportBlock } from "better-supabase/blocks/payroll-export";
import { taxBlock } from "better-supabase/blocks/tax";
import { documentTemplatesBlock } from "better-supabase/blocks/document-templates";
import { employeesBlock } from "better-supabase/blocks/employees";
import { entitlementsBlock } from "better-supabase/blocks/entitlements";
import { importsBlock } from "better-supabase/blocks/imports";
import { inventoryBlock } from "better-supabase/blocks/inventory";
import { invoicesBlock } from "better-supabase/blocks/invoices";
import { queueBlock } from "better-supabase/blocks/queue";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { numberingBlock } from "better-supabase/blocks/numbering";
import { onboardingBlock } from "better-supabase/blocks/onboarding";
import { ordersBlock } from "better-supabase/blocks/orders";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { outboxBlock } from "better-supabase/blocks/outbox";
import { contactsBlock } from "better-supabase/blocks/contacts";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { quotesBlock } from "better-supabase/blocks/quotes";
import { relationsBlock } from "better-supabase/blocks/relations";
import { automationsBlock } from "better-supabase/blocks/automations";
import { savedViewsBlock } from "better-supabase/blocks/saved-views";
import { settingsBlock } from "better-supabase/blocks/settings";
import { subjectsBlock } from "better-supabase/blocks/subjects";
import { teamsBlock } from "better-supabase/blocks/teams";
import { timeEntriesBlock } from "better-supabase/blocks/time-entries";

import { blockConfig } from "./erp.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  saas: saasBlock,
  finance: financeBlock,
  permissions: permissionsBlock,
  accounting: accountingBlock,
  apiKeys: apiKeysBlock,
  approvals: approvalsBlock,
  attachments: attachmentsBlock,
  audit: auditBlock,
  billing: billingBlock,
  catalog: catalogBlock,
  customFields: customFieldsBlock,
  leave: leaveBlock,
  ledger: ledgerBlock,
  assets: assetsBlock,
  enrollments: enrollmentsBlock,
  expenses: expensesBlock,
  rfqs: rfqsBlock,
  periods: periodsBlock,
  banking: bankingBlock,
  legalEntities: legalEntitiesBlock,
  payrollExport: payrollExportBlock,
  tax: taxBlock,
  documentTemplates: documentTemplatesBlock,
  employees: employeesBlock,
  entitlements: entitlementsBlock,
  imports: importsBlock,
  inventory: inventoryBlock,
  invoices: invoicesBlock,
  queue: queueBlock,
  notifications: notificationsBlock,
  numbering: numberingBlock,
  onboarding: onboardingBlock,
  orders: ordersBlock,
  organizations: organizationsBlock,
  outbox: outboxBlock,
  contacts: contactsBlock,
  profiles: profilesBlock,
  quotes: quotesBlock,
  relations: relationsBlock,
  automations: automationsBlock,
  savedViews: savedViewsBlock,
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
