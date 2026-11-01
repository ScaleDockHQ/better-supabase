import "server-only";
import { rpcTransport } from "better-supabase/blocks";
import { createCrm } from "better-supabase/blocks/crm";
import { createFilespace } from "better-supabase/blocks/filespace";

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
