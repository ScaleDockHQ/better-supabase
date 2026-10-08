import "server-only";
import { streamText, type LanguageModel } from "ai";
import {
  type AssistantContext,
  createAssistant,
} from "better-supabase/ai-sdk/chat";
import { createAiChat, type AiChat } from "better-supabase/blocks/ai-chat";
import {
  type RpcClient,
  rpcTransport,
} from "better-supabase/blocks/organizations";
import { postgresStreamStore } from "better-supabase/streams";
import { after } from "next/server";

import { bs } from "@/lib/supabase/server";

import { demoModel } from "./demo-model";

/** `sql.modules["ai-chat"].api` and `sql.modules.streams.api`. */
const API_SCHEMA = "api";

const DEFAULT_MODEL = "openai/gpt-5-mini";

/** Without a gateway key the sample answers with a scripted model. */
const demoMode = (): boolean => !process.env["AI_GATEWAY_API_KEY"];

function languageModel(id: string): LanguageModel {
  return demoMode() ? demoModel() : id;
}

/** The service-role transport for what only the server writes. */
function serviceTransport() {
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
    run: ({ model, messages, abortSignal, providerOptions }) =>
      streamText({
        model: languageModel(model),
        instructions: "You are a concise assistant inside a CRM sample app.",
        messages,
        abortSignal,
        providerOptions,
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
  return { chats: aiChat(supabase), userId, organizationId, waitUntil: after };
}
