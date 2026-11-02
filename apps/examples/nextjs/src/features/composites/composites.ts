import "server-only";
import { rpcTransport } from "better-supabase/blocks";
import { createCommerce } from "better-supabase/blocks/commerce";
import { createCrm } from "better-supabase/blocks/crm";
import { createFilespace } from "better-supabase/blocks/filespace";
import { createProjects } from "better-supabase/blocks/projects";
import { createKeyRotator } from "better-supabase/blocks/saas";
import { createSupport } from "better-supabase/blocks/support";

import type { driveOf } from "@/features/drive/drive-client";
import type { AppDb } from "@/lib/supabase";

/**
 * The `crm` composite's helpers over the clients this app already installs. The
 * parts stay ordinary blocks in the config; the composite adds `closeWon` and
 * `closeLost` on top of them.
 */
export function crmOf(db: AppDb) {
  const { $blocks: blocks } = db;

  return createCrm({
    transport: rpcTransport(db.$client),
    parts: {
      contacts: blocks.contacts,
      pipelines: blocks.pipelines,
      deals: blocks.deals,
      quotes: blocks.quotes,
      goals: blocks.goals,
      activities: blocks.activities,
      "mail-sync": blocks.mailSync,
      sequences: blocks.sequences,
      segments: blocks.segments,
      assignment: blocks.assignment,
      enrichment: blocks.enrichment,
      forecasts: blocks.forecasts,
      "lead-scoring": blocks.leadScoring,
      queue: blocks.queue,
    },
  });
}

/**
 * The `filespace` composite's helpers over the drive, attachments, versions,
 * share-links, search and trash clients: `put`, `shareMany` and `publicLink`.
 */
export function filespaceOf(db: AppDb, drive: ReturnType<typeof driveOf>) {
  const { $blocks: blocks } = db;

  return createFilespace({
    transport: rpcTransport(db.$client),
    parts: {
      drive,
      attachments: blocks.attachments,
      versions: blocks.versions,
      "share-links": blocks.shareLinks,
      search: blocks.search,
      trash: blocks.trash,
    },
  });
}

/**
 * The `support` composite's helpers: `openTicket` and `escalate` over the
 * inbox, tasks, SLA and knowledge clients.
 */
export function supportOf(db: AppDb) {
  const { $blocks: blocks } = db;

  return createSupport({
    transport: rpcTransport(db.$client),
    parts: {
      inbox: blocks.inbox,
      tasks: blocks.tasks,
      sla: blocks.sla,
      knowledge: blocks.knowledge,
    },
  });
}

/**
 * The `commerce` composite's helpers: `payAndFulfil` and `processReturn` over
 * the catalog, inventory, orders and promotions clients.
 */
export function commerceOf(db: AppDb) {
  const { $blocks: blocks } = db;

  return createCommerce({
    transport: rpcTransport(db.$client),
    parts: {
      catalog: blocks.catalog,
      inventory: blocks.inventory,
      orders: blocks.orders,
      promotions: blocks.promotions,
    },
  });
}

/**
 * The `projects` composite's helpers: `utilization`, `financials` and
 * `retainerDrawdown` over the time tracking client, among others.
 */
export function projectsOf(db: AppDb) {
  const { $blocks: blocks } = db;

  return createProjects({
    transport: rpcTransport(db.$client),
    parts: {
      tasks: blocks.tasks,
      "time-tracking": blocks.timeTracking,
      "billable-time": blocks.billableTime,
      approvals: blocks.approvals,
      invoices: blocks.invoices,
      meetings: blocks.meetings,
    },
  });
}

/**
 * `saas.rotateApiKey` over the API keys client. This app installs the key block
 * without the billing part of `saas`, so it builds the one helper it uses.
 */
export function keyRotationOf(db: AppDb) {
  return createKeyRotator({ apiKeys: db.$blocks.apiKeys });
}
