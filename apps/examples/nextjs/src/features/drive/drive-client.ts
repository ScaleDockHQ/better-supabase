import "server-only";
import { rpcTransport } from "better-supabase/blocks";
import {
  createDrive,
  createDriveText,
  plainTextExtractor,
} from "better-supabase/blocks/drive";

import type { AppDb } from "@/lib/supabase";

import { knowledge } from "@/features/knowledge/knowledge-server";
import { blockConfig } from "@/lib/supabase/blocks.generated";

/**
 * The drive client with the caller's Storage, which `db.drive` leaves out:
 * uploads need it for the signed upload URL, and downloads go through the
 * attachments block's scan gate.
 */
export function driveOf(db: AppDb) {
  return createDrive({
    transport: rpcTransport(db.$client),
    storage: db.$client.storage,
    attachments: db.attachments,
    recordAccess: db.accessRequests,
    schema: blockConfig.drive.api,
  });
}

/**
 * Extracts the text of each clean drive upload as the service role, for search
 * and for the assistant's knowledge. The outbox relay runs its sink.
 */
export function driveTextOf(admin: AppDb) {
  return createDriveText({
    transport: rpcTransport(admin.$client),
    storage: admin.$client.storage,
    extractor: plainTextExtractor(),
    schema: blockConfig.drive.api,
    knowledge: knowledge(admin.$client),
  });
}
