import { rpcTransport } from "better-supabase/blocks";

import { blockSet } from "@/lib/supabase";

/**
 * The outbox sinks the installed blocks provide, built on the service role: the
 * tasks block creates the next item of a repeating task when one is completed,
 * and search drops or refreshes a subject on trash and restore.
 */
export function blockSinks(admin: Parameters<typeof rpcTransport>[0]) {
  return blockSet.create({ transport: rpcTransport(admin) }).sinks;
}
