import type { LanguageModel } from "ai";

import { generateText } from "ai";

import type { AiProviders } from "../blocks/ai-providers/ai-providers.ts";
import type {
  ThreadSummarizer,
  ThreadSummaryInput,
} from "../blocks/messaging/summaries.ts";
import type { GatewayOptions } from "./gateway-options.ts";

import { gatewayOptions } from "./gateway-options.ts";
import { tenantGatewayOptions } from "./providers.ts";

export interface SummarizeWithOptions {
  /** Replaces the default summary prompt. */
  readonly instructions?: string;
  /**
   * The ai-providers block: the tenant's own keys go to the AI Gateway as
   * `byok` for each summary, and the app's credentials apply without them.
   */
  readonly providers?: Pick<AiProviders, "keys">;
  /** More AI Gateway options, such as `order` or `zeroDataRetention`. */
  readonly gateway?: GatewayOptions;
  readonly maxOutputTokens?: number;
}

const INSTRUCTIONS =
  "Summarize this team conversation for someone who missed it. Lead with the outcome or the open question, then the decisions, who owns which next step and what is still unresolved. Write at most eight short plain sentences and name people as the messages do. When a previous summary is given, update it with the newer messages instead of starting over. Never add facts the messages don't state.";

function promptOf(input: ThreadSummaryInput): string {
  const lines = input.messages.map(
    (message) =>
      `[${message.sentAt.toString()}] ${message.authorName ?? message.authorId ?? "Someone"}: ${message.body}`,
  );

  return input.previous === undefined
    ? lines.join("\n")
    : `Previous summary:\n${input.previous}\n\nMessages:\n${lines.join("\n")}`;
}

const nameOf = (model: LanguageModel): string =>
  typeof model === "string" ? model : `${model.provider}/${model.modelId}`;

/**
 * A `ThreadSummarizer` for `messaging.summarize` over `generateText`. Pass an
 * AI Gateway model string such as `anthropic/claude-sonnet-4.5`; the spend is
 * tagged with the tenant and the `summary` feature.
 */
export function summarizeWith(
  model: LanguageModel,
  options: SummarizeWithOptions = {},
): ThreadSummarizer {
  return {
    apiVersion: 1,
    summarize: async (input) => {
      const context = {
        organizationId: input.organizationId,
        feature: "summary",
      };

      const providerOptions =
        options.providers === undefined
          ? gatewayOptions(context, options.gateway)
          : await tenantGatewayOptions(
              options.providers,
              context,
              options.gateway,
              input.signal === undefined ? {} : { signal: input.signal },
            ).orThrow();

      const { text } = await generateText({
        model,
        instructions: options.instructions ?? INSTRUCTIONS,
        prompt: promptOf(input),
        providerOptions,
        ...(options.maxOutputTokens === undefined
          ? {}
          : { maxOutputTokens: options.maxOutputTokens }),
        ...(input.signal === undefined ? {} : { abortSignal: input.signal }),
      });

      return { summary: text.trim(), model: nameOf(model) };
    },
  };
}
