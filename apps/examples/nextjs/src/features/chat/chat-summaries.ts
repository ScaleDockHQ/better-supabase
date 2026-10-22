import "server-only";
import type { RpcClient } from "better-supabase/blocks";
import type {
  Messaging,
  ThreadSummarizer,
} from "better-supabase/blocks/messaging";

import { summarizeWith } from "better-supabase/ai-sdk";
import { generatedOptions } from "better-supabase/blocks";
import {
  createMessaging,
  rpcTransport,
} from "better-supabase/blocks/messaging";

import { aiProviders } from "@/features/ai-providers/ai-providers-server";
import { blockConfig } from "@/lib/supabase/blocks.generated";
import { bsb } from "@/lib/supabase/server";

const API_SCHEMA = blockConfig.messaging.api;

const SUMMARY_MODEL = "anthropic/claude-sonnet-4.5";

/**
 * Messaging acting as the caller, with summaries saved through the service role
 * so a member can't store one that misstates the thread.
 */
export function summaryMessaging(
  supabase: RpcClient,
  tenant: string,
): Messaging {
  return createMessaging({
    ...generatedOptions(blockConfig.messaging),
    transport: rpcTransport(supabase, { schema: API_SCHEMA }),
    service: rpcTransport(bsb.admin().$client, { schema: API_SCHEMA }),
    tenant: () => tenant,
  });
}

/**
 * Without a gateway key the sample lists who wrote what instead of calling a
 * model.
 */
const demoSummarizer: ThreadSummarizer = {
  apiVersion: 1,
  summarize: ({ messages }) => {
    const authors = new Set(
      messages.map(
        (message) => message.authorName ?? message.authorId ?? "Someone",
      ),
    );

    return Promise.resolve({
      summary: `${String(messages.length)} messages from ${[...authors].join(", ")}. Set AI_GATEWAY_API_KEY for a model-written summary.`,
      model: "demo",
    });
  },
};

/**
 * The summarizer for threads: an AI Gateway model, billed to the tenant's own
 * key when the organization saved one in the ai-providers block.
 */
export function threadSummarizer(supabase: RpcClient): ThreadSummarizer {
  return process.env["AI_GATEWAY_API_KEY"]
    ? summarizeWith(SUMMARY_MODEL, {
        providers: aiProviders(supabase),
        maxOutputTokens: 400,
      })
    : demoSummarizer;
}
