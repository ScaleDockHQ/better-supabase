import "server-only";
import type { ToolSet } from "ai";
import type { AssistantContext } from "better-supabase/ai-sdk/chat";
import type { AiChat } from "better-supabase/blocks/ai-chat";
import type { RpcClient } from "better-supabase/blocks/organizations";

import { stepCountIs, streamText } from "ai";
import { createAssistant } from "better-supabase/ai-sdk/chat";
import { generatedOptions } from "better-supabase/blocks";
import { createAiChat } from "better-supabase/blocks/ai-chat";
import { rpcTransport } from "better-supabase/blocks/organizations";
import { postgresStreamStore } from "better-supabase/streams";
import { after } from "next/server";

import { blockConfig } from "@/lib/supabase/blocks.generated";
import { bsb } from "@/lib/supabase/server";

/** The API schema `gen` wrote for the chat and its streams. */
const API_SCHEMA = blockConfig["ai-chat"].api;

/** A model id on the AI Gateway. */
const DEFAULT_MODEL = "openai/gpt-5-mini";

const INSTRUCTIONS = "You are a concise assistant inside this app.";

/** The service-role transport for what only the server writes. */
function serviceTransport(): ReturnType<typeof rpcTransport> {
  return rpcTransport(bsb.admin().$client, { schema: API_SCHEMA });
}

/** The chat block acting as the caller, with service writes on the side. */
export function aiChat(supabase: RpcClient): AiChat {
  return createAiChat({
    ...generatedOptions(blockConfig["ai-chat"]),
    transport: rpcTransport(supabase, { schema: API_SCHEMA }),
    service: serviceTransport(),
  });
}

/**
 * The tools the model may call for a member of `organizationId`, built per
 * request so they read as the caller. Add the blocks' tools here, such as
 * `searchTool` from `better-supabase/ai-sdk/embeddings` with the knowledge
 * block, or `memoryTool` from `better-supabase/ai-sdk/memory`.
 */
export function assistantTools(
  _supabase: RpcClient,
  _organizationId: string,
): ToolSet {
  return {};
}

/** Per request, so `run` uses the caller's tools. */
const requestTools = new WeakMap<AssistantContext, ToolSet>();

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
    run: ({ model, messages, abortSignal, providerOptions, context }) =>
      streamText({
        model,
        instructions: INSTRUCTIONS,
        messages,
        abortSignal,
        providerOptions,
        tools: requestTools.get(context) ?? {},
        stopWhen: stepCountIs(5),
      }),
  });

  return assistantInstance;
}

/** The per-request context of a signed-in member of `organizationId`. */
export function assistantContext(
  supabase: RpcClient,
  userId: string,
  organizationId: string,
): AssistantContext {
  const context: AssistantContext = {
    chats: aiChat(supabase),
    userId,
    organizationId,
    waitUntil: after,
  };

  requestTools.set(context, assistantTools(supabase, organizationId));

  return context;
}
