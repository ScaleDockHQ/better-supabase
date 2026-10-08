import { createClient } from "@supabase/supabase-js";
import { createAiChat, rpcTransport } from "better-supabase/blocks/ai-chat";
import { createInbox } from "better-supabase/blocks/inbox";
import { createKnowledge } from "better-supabase/blocks/knowledge";
import { createMemory } from "better-supabase/blocks/memory";
import { vaultCredentials } from "better-supabase/credentials";
import { loadEnv } from "better-supabase/env";

export const env = loadEnv();

if (env.secretKey === undefined) {
  throw new Error("The agent needs SUPABASE_SECRET_KEY");
}

// eve runs hooks, memory and connections outside the member's request, so
// every block here calls the `api` wrappers as the service role.
export const transport = rpcTransport(
  createClient(env.url, env.secretKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  }),
  { schema: "api" },
);

export const chats = createAiChat({ transport, service: transport });
export const memory = createMemory({ transport, service: transport });
export const knowledge = createKnowledge({ transport, service: transport });
export const inbox = createInbox({ transport });
export const credentials = vaultCredentials({ transport });
