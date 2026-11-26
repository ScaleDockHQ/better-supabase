import { createClient } from "@supabase/supabase-js";
import { createBlocks, rpcTransport } from "better-supabase/blocks";
import { aiChatBlock } from "better-supabase/blocks/ai-chat";
import { aiSchedulesBlock } from "better-supabase/blocks/ai-schedules";
import { inboxBlock } from "better-supabase/blocks/inbox";
import {
  DOCX_TYPE,
  PDF_TYPE,
  createUrlSource,
  docxExtractor,
  extractors,
  knowledgeBlock,
  pdfExtractor,
} from "better-supabase/blocks/knowledge";
import { memoryBlock } from "better-supabase/blocks/memory";
import { vaultCredentials } from "better-supabase/credentials";
import { getEnv } from "better-supabase/env";

export const env = getEnv();

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

export const credentials = vaultCredentials({ transport });

export const { chats, memory, knowledge, inbox, aiSchedules } = createBlocks(
  { transport, service: transport, credentials },
  {
    aiSchedules: aiSchedulesBlock,
    chats: aiChatBlock,
    memory: memoryBlock,
    knowledge: knowledgeBlock,
    inbox: inboxBlock,
  },
);

// Pages the agent ingests from a URL. HTML is read by the source itself; PDF
// and Word files use the optional peers `unpdf` and `mammoth` on first use.
// Only the hosts below are fetched.
export const urlSource = createUrlSource({
  knowledge,
  allowedHosts: ["docs.example.com"],
  extract: extractors({
    [PDF_TYPE]: pdfExtractor(),
    [DOCX_TYPE]: docxExtractor(),
  }),
});
