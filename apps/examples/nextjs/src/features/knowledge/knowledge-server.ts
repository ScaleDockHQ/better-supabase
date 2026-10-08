import "server-only";
import { embedWith } from "better-supabase/ai-sdk/embeddings";
import {
  createKnowledge,
  type Embedder,
  type Knowledge,
} from "better-supabase/blocks/knowledge";
import { createMemory, type Memory } from "better-supabase/blocks/memory";
import {
  type RpcClient,
  rpcTransport,
} from "better-supabase/blocks/organizations";

import { bs } from "@/lib/supabase/server";

import { demoEmbedder } from "./demo-embedder";

/** `sql.modules.knowledge.api` and `sql.modules.memory.api`. */
const API_SCHEMA = "api";

let embedderInstance: Embedder | undefined;

/** The gateway's embedding model, or the demo embedder without a key. */
function embedder(): Embedder {
  embedderInstance ??= process.env["AI_GATEWAY_API_KEY"]
    ? embedWith("openai/text-embedding-3-small")
    : demoEmbedder;
  return embedderInstance;
}

const service = () => rpcTransport(bs.admin().$client, { schema: API_SCHEMA });

/** The knowledge block acting as the caller; the service role writes embeddings. */
export function knowledge(supabase: RpcClient): Knowledge {
  return createKnowledge({
    transport: rpcTransport(supabase, { schema: API_SCHEMA }),
    service: service(),
    schema: API_SCHEMA,
    embedder: embedder(),
  });
}

/** The memory block acting as the caller. */
export function memory(supabase: RpcClient): Memory {
  return createMemory({
    transport: rpcTransport(supabase, { schema: API_SCHEMA }),
    service: service(),
    schema: API_SCHEMA,
    embedder: embedder(),
  });
}
