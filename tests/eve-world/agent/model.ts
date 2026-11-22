import { convertArrayToReadableStream, MockLanguageModelV4 } from "ai/test";
import { setTimeout as sleep } from "node:timers/promises";

const usage = {
  inputTokens: { total: 10, noCache: 10, cacheRead: 0, cacheWrite: 0 },
  outputTokens: { total: 5, text: 5, reasoning: 0 },
} as const;

const finish = (reason: "stop" | "tool-calls") =>
  ({
    type: "finish",
    finishReason: { unified: reason, raw: reason },
    usage,
  }) as const;

/** Text of the last user message, or the empty string. */
function lastUserText(
  prompt: readonly { role: string; content: unknown }[],
): string {
  const last = prompt.findLast((message) => message.role === "user");

  if (!last || !Array.isArray(last.content)) {
    return "";
  }

  return last.content
    .map((part: { type: string; text?: string }) =>
      part.type === "text" ? (part.text ?? "") : "",
    )
    .join(" ");
}

/**
 * The model holds no state, so a server restart between two steps loses
 * nothing. The last prompt message decides the reply: a tool result ends the
 * turn with text, a user message names the script (`tool:echo`,
 * `tool:delete_record`, `slow`, `words:<n>`) and anything else gets a greeting.
 * A call without tools is the compaction summary and gets plain text.
 */
export const scriptedModel = new MockLanguageModelV4({
  doStream: async ({ prompt, tools }) => {
    const last = prompt.at(-1);
    const summarizing = (tools ?? []).length === 0;

    if (last?.role === "tool") {
      return {
        stream: convertArrayToReadableStream([
          { type: "stream-start", warnings: [] },
          { type: "text-start", id: "t" },
          { type: "text-delta", id: "t", delta: "tool finished" },
          { type: "text-end", id: "t" },
          finish("stop"),
        ]),
      };
    }

    const text = lastUserText(prompt);
    const tool = summarizing ? undefined : /tool:(\w+)/u.exec(text)?.[1];

    if (tool) {
      const input = tool === "echo" ? { word: "ping" } : { id: "rec_1" };

      return {
        stream: convertArrayToReadableStream([
          { type: "stream-start", warnings: [] },
          {
            type: "tool-call",
            toolCallId: `call_${tool}`,
            toolName: tool,
            input: JSON.stringify(input),
          },
          finish("tool-calls"),
        ]),
      };
    }

    const words = Number(/words:(\d+)/u.exec(text)?.[1] ?? 0);
    const count = words > 0 ? words : 3;
    const slow = text.includes("slow");
    const pace = Number(/pace:(\d+)/u.exec(text)?.[1] ?? 0);
    const deltas = Array.from({ length: count }, (_, i) => `w${i} `);

    const stream = new ReadableStream({
      async start(controller) {
        controller.enqueue({ type: "stream-start", warnings: [] });
        controller.enqueue({ type: "text-start", id: "t" });

        for (const delta of deltas) {
          if (slow) {
            await sleep(400);
          } else if (pace > 0) {
            await sleep(pace);
          }

          controller.enqueue({ type: "text-delta", id: "t", delta });
        }

        controller.enqueue({ type: "text-end", id: "t" });
        controller.enqueue({
          ...finish("stop"),
          usage: {
            inputTokens: usage.inputTokens,
            outputTokens: { total: count, text: count, reasoning: 0 },
          },
        });
        controller.close();
      },
    });

    return { stream };
  },
});
