import "server-only";
import type { RpcClient } from "better-supabase/blocks";
import type {
  Attachments,
  AttachmentStorage,
} from "better-supabase/blocks/attachments";

import {
  createAttachments,
  rpcTransport,
} from "better-supabase/blocks/attachments";

import { blockConfig } from "@/lib/supabase/blocks.generated";

/**
 * The attachments block as the caller, in `tenant`. `blocks()` builds it
 * without a Storage client, so this one passes the caller's `supabase.storage`:
 * the `attachments` bucket's policies only accept a file a pending record
 * expects.
 */
export function customerAttachments(
  supabase: RpcClient & { readonly storage: AttachmentStorage },
  tenant?: string | null,
): Attachments {
  return createAttachments({
    transport: rpcTransport(supabase),
    storage: supabase.storage,
    schema: blockConfig.attachments.api,
    requireScan: blockConfig.attachments.options.requireScan,
    tenant: () => tenant,
  });
}
