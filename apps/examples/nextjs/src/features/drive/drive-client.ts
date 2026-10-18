import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";

import { rpcTransport } from "better-supabase/blocks";
import { createDrive } from "better-supabase/blocks/drive";

import { blocks } from "@/lib/blocks";
import { blockConfig } from "@/lib/supabase/blocks.generated";

/**
 * The drive client with the caller's Storage, which `blocks()` leaves out:
 * uploads need it for the signed upload URL, and downloads go through the
 * attachments block's scan gate.
 */
export function driveOf(supabase: SupabaseClient) {
  return createDrive({
    transport: rpcTransport(supabase),
    storage: supabase.storage,
    attachments: blocks(supabase).attachments,
    schema: blockConfig.drive.api,
  });
}
