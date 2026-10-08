import { readUIMessageStream, UI_MESSAGE_STREAM_HEADERS } from "ai";
import { describe, expect, it } from "vitest";

import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import { post, setup, userMessage } from "../ai-sdk/chat/fakes.ts";

/** The SSE body as UI message chunks, the way `DefaultChatTransport` reads it. */
function chunks(body: ReadableStream<Uint8Array<ArrayBuffer>>) {
  return body.pipeThrough(new TextDecoderStream()).pipeThrough(
    new TransformStream<string, unknown>({
      transform(text, controller) {
        for (const line of text.split("\n")) {
          if (!line.startsWith("data: ")) continue;
          const data = line.slice("data: ".length);
          if (data !== "[DONE]") controller.enqueue(JSON.parse(data));
        }
      },
    }),
  );
}

describe("AI SDK UI message stream protocol", () => {
  it("pins the protocol version the installed SDK speaks", () => {
    expect(SPEC_PINS.aiSdkUiMessageStream).toBe("v1");
    expect(UI_MESSAGE_STREAM_HEADERS["x-vercel-ai-ui-message-stream"]).toBe(
      SPEC_PINS.aiSdkUiMessageStream,
    );
  });

  it("createAssistant answers with the protocol's headers and frames", async () => {
    const { assistant, context, pending } = setup();
    const response = await assistant.respond(
      post({ id: "c1", message: userMessage() }),
      context,
    );
    for (const [name, value] of Object.entries(UI_MESSAGE_STREAM_HEADERS))
      expect(response.headers.get(name)).toBe(value);
    const text = await response.clone().text();
    expect(text.trimEnd().endsWith("data: [DONE]")).toBe(true);
    const body = response.body;
    expect(body).not.toBeNull();
    let last;
    // SAFETY: the protocol's frames are UI message chunks; readUIMessageStream validates them.
    const stream = chunks(body!) as Parameters<
      typeof readUIMessageStream
    >[0]["stream"];
    for await (const message of readUIMessageStream({
      stream,
      terminateOnError: true,
    }))
      last = message;
    await Promise.all(pending);
    expect(last).toMatchObject({
      role: "assistant",
      parts: expect.arrayContaining([
        expect.objectContaining({ type: "text", text: "Hello there" }),
      ]),
    });
  });

  it("replays the same frames when the client reconnects", async () => {
    const { assistant, context, pending } = setup();
    const live = await (
      await assistant.respond(
        post({ id: "c1", message: userMessage() }),
        context,
      )
    ).text();
    await Promise.all(pending);
    const replay = await assistant.resume("c1", context);
    expect(replay.headers.get("x-vercel-ai-ui-message-stream")).toBe(
      SPEC_PINS.aiSdkUiMessageStream,
    );
    expect(await replay.text()).toBe(live);
  });
});
