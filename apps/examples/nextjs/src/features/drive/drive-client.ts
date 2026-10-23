import "server-only";
import { rpcTransport } from "better-supabase/blocks";
import { createDrive } from "better-supabase/blocks/drive";

import type { AppDb } from "@/lib/supabase";

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
    schema: blockConfig.drive.api,
  });
}
