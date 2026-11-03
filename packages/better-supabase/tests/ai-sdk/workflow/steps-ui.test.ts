import type { UIMessageChunk } from "ai";

import { describe, expect, it, vi } from "vitest";

import type { AiChat } from "../../../src/blocks/ai-chat/index.ts";

import { durableSteps } from "../../../src/ai-sdk/workflow/index.ts";
import { AsyncResult, ok } from "../../../src/core/result.ts";

const api = vi.hoisted(() => ({ getRun: vi.fn() }));

vi.mock(import("workflow/api"), () => api as never);

vi.mock(
  import("@ai-sdk/workflow"),
  () =>
    ({
      createModelCallToUIChunkTransform: () => new TransformStream(),
      async *normalizeUIMessageStreamParts(source: AsyncIterable<unknown>) {
        yield* source;
      },
    }) as never,
);

function readable(chunks: readonly unknown[]): ReadableStream {
  return new ReadableStream({
    start(controller) {
      for (const chunk of chunks) {
        controller.enqueue(chunk);
      }

      controller.close();
    },
  });
}

function saved() {
  const calls: { message: { parts: unknown[]; metadata?: unknown } }[] = [];

  const chats = {
    messages: {
      saveAssistant: (call: (typeof calls)[number]) => {
        calls.push(call);

        return AsyncResult.from(async () =>
          ok({ messageId: "m1", parentId: "u1", created: true }),
        );
      },
    },
  };

  // SAFETY: the fake implements the one call the save step makes.
  return { chats: chats as unknown as AiChat, calls };
}

const input = {
  chatId: "c1",
  message: {
    id: "m1",
    role: "assistant" as const,
    parts: [{ type: "text" as const, text: "Hi", state: "done" as const }],
  },
  parentId: "u1",
  model: "openai/gpt-5",
  runId: "run1",
  status: "complete" as const,
  streams: { workflowRunId: "wrun", streamIds: ["s1"] },
};

describe("save step with the UI stream", () => {
  it("keeps data parts and message metadata", async () => {
    const chunks: UIMessageChunk[] = [
      { type: "start" },
      { type: "data-weather", id: "w", data: { c: 1 } },
      { type: "data-weather", id: "w", data: { c: 2 } },
      { type: "data-note", data: "gone", transient: true },
      { type: "message-metadata", messageMetadata: { model: "m" } },
      { type: "finish" },
    ];

    api.getRun.mockReturnValue({ getReadable: () => readable(chunks) });
    const { chats, calls } = saved();

    await durableSteps(chats).save(input);

    expect(calls[0]?.message.parts).toEqual([
      ...input.message.parts,
      { type: "data", name: "weather", id: "w", data: { c: 2 } },
    ]);

    expect(calls[0]?.message.metadata).toEqual({ model: "m" });
  });

  it("saves from the model messages when the stream can't be read", async () => {
    api.getRun.mockImplementation(() => {
      throw new Error("no run");
    });

    const { chats, calls } = saved();

    await durableSteps(chats).save(input);

    expect(calls[0]?.message.parts).toEqual(input.message.parts);
  });
});
