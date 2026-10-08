import "server-only";
import { streamText, type LanguageModel } from "ai";
import {
  type AssistantContext,
  createAssistant,
} from "better-supabase/ai-sdk/chat";
import { aiFileDownload } from "better-supabase/ai-sdk/files";
import { createAiChat, type AiChat } from "better-supabase/blocks/ai-chat";
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

import { bs } from "@/lib/supabase/server";

import { demoModel } from "./demo-model";

/** `sql.modules["ai-chat"].api`, `["ai-files"].api` and `streams.api`. */
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

/** The caller's files per request, so `run` reads attachments as the caller. */
const requestFiles = new WeakMap<AssistantContext, AiFiles>();

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
    run: ({ model, messages, abortSignal, providerOptions, context }) => {
      const files = requestFiles.get(context);
      return streamText({
        model: languageModel(model),
        instructions: "You are a concise assistant inside a CRM sample app.",
        messages,
        abortSignal,
        providerOptions,
        experimental_download: files ? aiFileDownload(files) : undefined,
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
  requestFiles.set(context, aiFiles(supabase));
  return context;
}
