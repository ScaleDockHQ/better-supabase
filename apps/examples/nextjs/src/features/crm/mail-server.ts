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

import { connectCredentials } from "@/features/integrations/integrations-server";
import { blockConfig } from "@/lib/supabase/blocks.generated";
import { bsb } from "@/lib/supabase/server";

const API_SCHEMA = blockConfig["mail-sync"].api;

/** The route that records opens and clicks, under the app's origin. */
const TRACKING_PATH = "/api/mail/t";

/**
 * Mail sync acting as `supabase`'s caller, or as the service role without one.
 * Each member's Gmail or Outlook grant lives in Vercel Connect (connected on
 * the Integrations settings tab), which the adapter loads only when a sync or a
 * send asks it for a token. With `origin`, sent HTML is tracked through the
 * route at `TRACKING_PATH`.
 */
export function mailSync(
  supabase?: RpcClient,
  options: { readonly origin?: string } = {},
): MailSync {
  const base = {
    ...generatedOptions(blockConfig["mail-sync"]),
    transport: rpcTransport(supabase ?? bsb.admin().$client, {
      schema: API_SCHEMA,
    }),
    credentials: connectCredentials(),
    providers: [gmailMail(), outlookMail()],
  };

  return createMailSync(
    options.origin === undefined
      ? base
      : {
          ...base,
          tracking: { url: new URL(TRACKING_PATH, options.origin).href },
        },
  );
}
