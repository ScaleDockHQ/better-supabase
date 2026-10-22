import "server-only";
import type { RpcClient } from "better-supabase/blocks";
import type { MailSync } from "better-supabase/blocks/mail-sync";

import { generatedOptions } from "better-supabase/blocks";
import {
  createMailSync,
  gmailMail,
  outlookMail,
  rpcTransport,
} from "better-supabase/blocks/mail-sync";
import { vercelConnectCredentials } from "better-supabase/vercel-connect";

import { blockConfig } from "@/lib/supabase/blocks.generated";
import { bs } from "@/lib/supabase/server";

const API_SCHEMA = blockConfig["mail-sync"].api;

/**
 * Mail sync acting as `supabase`'s caller, or as the service role without one.
 * Each member's Gmail or Outlook grant lives in Vercel Connect, which the
 * adapter loads only when a sync or a send asks it for a token.
 */
export function mailSync(supabase?: RpcClient): MailSync {
  return createMailSync({
    ...generatedOptions(blockConfig["mail-sync"]),
    transport: rpcTransport(supabase ?? bs.admin().$client, {
      schema: API_SCHEMA,
    }),
    credentials: vercelConnectCredentials(),
    providers: [gmailMail(), outlookMail()],
  });
}
