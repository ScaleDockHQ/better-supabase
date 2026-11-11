import "server-only";
import type { EvalItem } from "better-supabase/blocks/ai-evals";

import { gateway, generateText } from "ai";

import { env } from "@/env";

const text = (value: unknown): string =>
  typeof value === "string" ? value : JSON.stringify(value ?? "");

/** A stable number from an id and a version, so a demo run repeats. */
function bucket(id: string, version: number): number {
  let hash = version;

  for (const char of id) {
    hash = (hash * 31 + (char.codePointAt(0) ?? 0)) % 9973;
  }

  return hash % 4;
}

/**
 * The model's answer for one item. With an AI Gateway key it calls the model
 * with the template as the system prompt. Without one a scripted answer stands
 * in: the expected text, except for one item in four, which misses so the
 * report has a failure to triage. A newer version misses fewer, so the trend
 * moves when a prompt is promoted.
 */
export async function answerFor({
  template,
  model,
  item,
  version,
}: {
  template: string;
  model: string;
  item: EvalItem;
  version: number;
}): Promise<string> {
  if (!env.AI_GATEWAY_API_KEY) {
    const expected = text(item.expected);

    return bucket(item.id, version) === 0 && version < 2
      ? "I am not sure."
      : expected;
  }

  const answer = await generateText({
    model: gateway(model),
    instructions: template,
    prompt: text(item.input),
  });

  return answer.text;
}
