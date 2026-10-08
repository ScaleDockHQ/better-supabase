import "server-only";
import { stepCountIs, streamText, type LanguageModel, type ToolSet } from "ai";
import {
  type AssistantContext,
  createAssistant,
} from "better-supabase/ai-sdk/chat";
import { searchTool } from "better-supabase/ai-sdk/embeddings";
import { aiFileDownload } from "better-supabase/ai-sdk/files";
import { memoryTool, withMemory } from "better-supabase/ai-sdk/memory";
import {
  type AiChat,
  type AiRuns,
  createAiChat,
  createAiRuns,
} from "better-supabase/blocks/ai-chat";
import {
  type AiFiles,
  type AiFileStorage,
  createAiFiles,
} from "better-supabase/blocks/ai-files";
import {
  type RpcClient,
  rpcTransport,
} from "better-supabase/blocks/organizations";
import { postgresStreamStore } from "better-supabase/streams";
import { after } from "next/server";

import { knowledge, memory } from "@/features/knowledge/knowledge-server";
import { bs } from "@/lib/supabase/server";

import { demoModel } from "./demo-model";

/** `sql.modules["ai-chat"].api`, `["ai-files"].api` and `streams.api`. */
const API_SCHEMA = "api";

const DEFAULT_MODEL = "openai/gpt-5-mini";

/** Without a gateway key the sample answers with a scripted model. */
const demoMode = (): boolean => !process.env["AI_GATEWAY_API_KEY"];

/** Durable chats call the model inside workflow steps, which can't run the scripted model. */
export const durableAvailable = (): boolean => !demoMode();

function languageModel(id: string): LanguageModel {
  return demoMode() ? demoModel() : id;
}

/** The service-role transport for what only the server writes. */
export function serviceTransport() {
  return rpcTransport(bs.admin().$client, { schema: API_SCHEMA });
}

/** The chat block acting as the caller, with service writes on the side. */
export function aiChat(supabase: RpcClient): AiChat {
  return createAiChat({
    transport: rpcTransport(supabase, { schema: API_SCHEMA }),
    service: serviceTransport(),
    schema: API_SCHEMA,
  });
}

/** The chat's runs, steps and approvals as the caller; engine writes go through the service role. */
export function aiRuns(supabase: RpcClient): AiRuns {
  return createAiRuns({
    transport: rpcTransport(supabase, { schema: API_SCHEMA }),
    service: serviceTransport(),
    schema: API_SCHEMA,
  });
}

/** The caller's client: RPC for the blocks, Storage for the files. */
type UserClient = RpcClient & { readonly storage: AiFileStorage };

/** The files block acting as the caller; the service role stores generated files. */
export function aiFiles(supabase: UserClient): AiFiles {
  return createAiFiles({
    transport: rpcTransport(supabase, { schema: API_SCHEMA }),
    storage: supabase.storage,
    service: serviceTransport(),
    serviceStorage: bs.admin().$client.storage,
    schema: API_SCHEMA,
  });
}

interface RequestScope {
  readonly files: AiFiles;
  readonly tools: ToolSet;
  /** The caller's core memory appended to the instructions. */
  readonly instructions: (base: string) => Promise<string>;
}

/** Per request, so `run` reads files, documents and memory as the caller. */
const requestScopes = new WeakMap<AssistantContext, RequestScope>();

const INSTRUCTIONS =
  "You are a concise assistant inside a CRM sample app. Search the knowledge base before you answer a question about the organization, and keep notes about the user in your memory.";

let assistantInstance: ReturnType<typeof createAssistant> | undefined;

/** One assistant per process; the stream store writes as the service role. */
export function assistant(): ReturnType<typeof createAssistant> {
  assistantInstance ??= createAssistant({
    streams: postgresStreamStore({
      transport: serviceTransport(),
      schema: API_SCHEMA,
      wake: "poll",
    }),
    defaultModel: DEFAULT_MODEL,
    run: async ({ model, messages, abortSignal, providerOptions, context }) => {
      const scope = requestScopes.get(context);
      return streamText({
        model: languageModel(model),
        instructions: scope
          ? await scope.instructions(INSTRUCTIONS)
          : INSTRUCTIONS,
        messages,
        abortSignal,
        providerOptions,
        tools: scope?.tools ?? {},
        stopWhen: stepCountIs(5),
        experimental_download: scope ? aiFileDownload(scope.files) : undefined,
      });
    },
  });
  return assistantInstance;
}

/** The per-request context of a signed-in member of `organizationId`. */
export function assistantContext(
  supabase: UserClient,
  userId: string,
  organizationId: string,
): AssistantContext {
  const context: AssistantContext = {
    chats: aiChat(supabase),
    userId,
    organizationId,
    waitUntil: after,
  };
  const memories = memory(supabase);
  requestScopes.set(context, {
    files: aiFiles(supabase),
    tools: {
      searchKnowledge: searchTool(knowledge(supabase), organizationId),
      memory: memoryTool(memories, organizationId),
    },
    instructions: (base) => withMemory(base, memories, organizationId),
  });
  return context;
}
