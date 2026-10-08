import { simulateReadableStream } from "ai";
import { MockLanguageModelV4 } from "ai/test";

const REPLY = [
  "This is the demo assistant: no AI_GATEWAY_API_KEY is set, so a scripted",
  "model answers. The answer still runs through the ai-chat block: your",
  "message is stored, the answer streams through the streams module, and a",
  "reload resumes it. Set AI_GATEWAY_API_KEY to talk to a real model.",
].join(" ");

/** A scripted model that streams a fixed answer word by word. */
export function demoModel(): MockLanguageModelV4 {
  const words = REPLY.split(" ");
  return new MockLanguageModelV4({
    doStream: () =>
      Promise.resolve({
        stream: simulateReadableStream({
          initialDelayInMs: 200,
          chunkDelayInMs: 40,
          chunks: [
            { type: "stream-start", warnings: [] },
            { type: "text-start", id: "demo" },
            ...words.map((word, index) => ({
              type: "text-delta" as const,
              id: "demo",
              delta: index === 0 ? word : ` ${word}`,
            })),
            { type: "text-end", id: "demo" },
            {
              type: "finish",
              finishReason: { unified: "stop", raw: "stop" },
              usage: {
                inputTokens: {
                  total: 12,
                  noCache: 12,
                  cacheRead: 0,
                  cacheWrite: 0,
                },
                outputTokens: {
                  total: words.length,
                  text: words.length,
                  reasoning: 0,
                },
              },
            },
          ],
        }),
      }),
  });
}
