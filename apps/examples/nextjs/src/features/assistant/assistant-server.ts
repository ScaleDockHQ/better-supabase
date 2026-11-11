import type { ToolSet } from "ai";

import "server-only";
import type { AssistantContext } from "better-supabase/ai-sdk/chat";
import type { AiChat, AiRuns } from "better-supabase/blocks/ai-chat";
import type { AiFiles, AiFileStorage } from "better-supabase/blocks/ai-files";
import type { AiKeys } from "better-supabase/blocks/ai-keys";
import type { RpcClient } from "better-supabase/blocks/organizations";

import { gateway, isStepCount, streamText, wrapLanguageModel } from "ai";
import { byokOptions, guardrailsMiddleware } from "better-supabase/ai-sdk";
import { createAssistant } from "better-supabase/ai-sdk/chat";
import { searchTool } from "better-supabase/ai-sdk/embeddings";
import { aiFileDownload } from "better-supabase/ai-sdk/files";
import { memoryTool, withMemory } from "better-supabase/ai-sdk/memory";
import { generatedOptions } from "better-supabase/blocks";
import { createAiChat } from "better-supabase/blocks/ai-chat";
import { createAiFiles } from "better-supabase/blocks/ai-files";
import { createAiKeys } from "better-supabase/blocks/ai-keys";
import { rpcTransport } from "better-supabase/blocks/organizations";
import { vaultCredentials } from "better-supabase/credentials";
import { postgresStreamStore } from "better-supabase/streams";
import { after } from "next/server";

import { env } from "@/env";
import { guardrailsBlock } from "@/features/guardrails/guardrails-server";
import { knowledge, memory } from "@/features/knowledge/knowledge-server";
import { promptsBlock } from "@/features/prompts/prompts-server";
import { blockConfig } from "@/lib/supabase/blocks.config";
import { bsbShell as bsb } from "@/lib/supabase/server-shell";

import { ASSISTANT_AGENT, ASSISTANT_PROMPT } from "./assistant-ops";
import { codeSandbox, NO_CODE } from "./code-sandbox";
import { demoModel } from "./demo-model";

/** The API schema `gen` wrote for the chat, its files and its streams. */
const API_SCHEMA = blockConfig["ai-chat"].api;

const DEFAULT_MODEL = "openai/gpt-5-mini";

/** Without a gateway key the sample answers with a scripted model. */
const demoMode = (): boolean => !env.AI_GATEWAY_API_KEY;

/**
 * Durable chats call the model inside workflow steps, which can't run the
 * scripted model.
 */
export const durableAvailable = (): boolean => !demoMode();

function languageModel(id: string) {
  return demoMode() ? demoModel() : gateway(id);
}

/**
 * The model behind the organization's guardrail policy for the assistant: the
 * last user message is checked before the call and the answer after it. With no
 * policy saved, both stages allow and log nothing.
 */
function guardedModel(
  id: string,
  organizationId: string | null,
  chatId: string,
) {
  return wrapLanguageModel({
    model: languageModel(id),
    middleware: guardrailsMiddleware(guardrailsBlock(), {
      agent: ASSISTANT_AGENT,
      chatId,
      ...(organizationId === null ? {} : { organizationId }),
    }),
  });
}

/**
 * The `assistant.system` prompt of the organization at its production label, or
 * the built-in instructions when none is saved. A template with variables is
 * used as written, since a chat has no values to fill them.
 */
async function systemPrompt(organizationId: string | null): Promise<string> {
  if (organizationId === null) {
    return INSTRUCTIONS;
  }

  const prompt = await promptsBlock().get({
    name: ASSISTANT_PROMPT,
    organizationId,
  });

  return prompt.ok && prompt.data !== undefined
    ? prompt.data.template
    : INSTRUCTIONS;
}

/** The service-role transport for what only the server writes. */
export function serviceTransport() {
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
 * The chat's runs, steps and approvals as the caller; engine writes go through
 * the service role.
 */
export function aiRuns(supabase: RpcClient): AiRuns {
  return aiChat(supabase).runs;
}

let providersInstance: AiKeys | undefined;

/** The organizations' own provider keys, read from Vault as the service role. */
function aiProviders(): AiKeys {
  if (providersInstance) {
    return providersInstance;
  }

  const service = serviceTransport();
  providersInstance = createAiKeys({
    transport: service,
    service,
    credentials: vaultCredentials({ transport: service, schema: API_SCHEMA }),
    ...generatedOptions(blockConfig["ai-keys"]),
  });

  return providersInstance;
}

const priorityOf = (settings: Readonly<Record<string, unknown>>): number =>
  typeof settings["priority"] === "number"
    ? settings["priority"]
    : Number.MAX_SAFE_INTEGER;

/**
 * Adds the organization's own keys (BYOK) to the gateway options, when it saved
 * any.
 */
async function withTenantKeys<T extends { readonly gateway: object }>(
  providerOptions: T,
  organizationId: string | null,
): Promise<T> {
  if (demoMode() || organizationId === null) {
    return providerOptions;
  }

  const keys = await aiProviders().keys.resolve({ organizationId });

  if (!keys.ok || keys.data.length === 0) {
    return providerOptions;
  }

  // The gateway tries providers in this order and moves on when one fails.
  const order = keys.data
    .toSorted((a, b) => priorityOf(a.settings) - priorityOf(b.settings))
    .map((key) => key.provider)
    .filter((provider, index, all) => all.indexOf(provider) === index);

  return {
    ...providerOptions,
    gateway: {
      ...providerOptions.gateway,
      // `priority` is the app's own setting; the gateway only gets the rest.
      ...byokOptions(
        keys.data.map(
          ({ settings: { priority: _priority, ...rest }, ...key }) => ({
            ...key,
            settings: rest,
          }),
        ),
      ),
      order,
    },
  };
}

/** The caller's client: RPC for the blocks, Storage for the files. */
type UserClient = RpcClient & { readonly storage: AiFileStorage };

/**
 * The files block acting as the caller; the service role stores generated
 * files.
 */
export function aiFiles(supabase: UserClient): AiFiles {
  return createAiFiles({
    ...generatedOptions(blockConfig["ai-files"]),
    transport: rpcTransport(supabase, { schema: API_SCHEMA }),
    storage: supabase.storage,
    service: serviceTransport(),
    serviceStorage: bsb.admin().$client.storage,
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
    run: async ({
      chat,
      model,
      messages,
      abortSignal,
      providerOptions,
      context,
    }) => {
      const scope = requestScopes.get(context);

      const code =
        demoMode() || context.organizationId === null
          ? NO_CODE
          : await codeSandbox(
              context.chats.sandboxes,
              context.organizationId,
              chat.id,
              { userId: context.userId, signal: abortSignal },
            );

      const base = await systemPrompt(context.organizationId);

      return streamText({
        model: guardedModel(model, context.organizationId, chat.id),
        instructions: scope ? await scope.instructions(base) : base,
        messages,
        abortSignal,
        providerOptions: await withTenantKeys(
          providerOptions,
          context.organizationId,
        ),
        ...code,
        tools: { ...scope?.tools, ...code.tools },
        toolApproval: { runCode: "user-approval" },
        stopWhen: isStepCount(5),
        telemetry: { functionId: "assistant.chat" },
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
