import type { ChatTransport, UIMessage } from "ai";

import { afterEach, describe, expect, it, vi } from "vitest";

import { useAssistant } from "../../../src/ai-sdk/react/index.ts";
import { useAssistant as useAssistantOnServer } from "../../../src/ai-sdk/react/server.ts";

const chatHook = vi.hoisted(() => vi.fn());

vi.mock("react", () => ({
  useMemo: (make: () => unknown) => make(),
  useCallback: (callback: unknown) => callback,
}));

vi.mock("@ai-sdk/react", () => ({ useChat: chatHook }));

const user: UIMessage = {
  id: "u1",
  role: "user",
  parts: [{ type: "text", text: "Hi" }],
};
const answer: UIMessage = {
  id: "a1",
  role: "assistant",
  parts: [{ type: "text", text: "Hello" }],
};

function capture() {
  const calls: { url: string; init: RequestInit | undefined }[] = [];
  vi.stubGlobal(
    "fetch",
    vi.fn(async (url: string, init?: RequestInit) => {
      calls.push({ url, init });
      return new Response("data: [DONE]\n\n", {
        headers: { "content-type": "text/event-stream" },
      });
    }),
  );
  return calls;
}

function useRendered(options: Parameters<typeof useAssistant>[0]) {
  const stopLocal = vi.fn(async () => undefined);
  chatHook.mockReturnValue({ messages: [], stop: stopLocal });
  const state = useAssistant(options);
  const chatOptions = chatHook.mock.lastCall?.[0] as {
    transport: ChatTransport<UIMessage>;
    resume: boolean;
  };
  return { state, stopLocal, chatOptions };
}

afterEach(() => {
  vi.unstubAllGlobals();
  chatHook.mockReset();
});

describe("useAssistant", () => {
  it("sends only the newest user message with the model", async () => {
    const calls = capture();
    const { chatOptions } = useRendered({
      id: "c1",
      model: "openai/gpt-5",
      body: { projectId: "p" },
      headers: { "x-test": "1" },
      messages: [user],
      onError: vi.fn(),
      onFinish: vi.fn(),
      throttle: 50,
    });
    expect(chatOptions.resume).toBe(true);
    await chatOptions.transport.sendMessages({
      chatId: "c1",
      messages: [user, answer],
      trigger: "regenerate-message",
      messageId: "a1",
      abortSignal: undefined,
    });
    expect(calls[0]?.url).toBe("/api/chat");
    expect(JSON.parse(String(calls[0]?.init?.body))).toEqual({
      projectId: "p",
      id: "c1",
      message: user,
      trigger: "regenerate-message",
      messageId: "a1",
      model: "openai/gpt-5",
    });
    expect(chatHook).toHaveBeenCalledWith(
      expect.objectContaining({ id: "c1", throttle: 50, messages: [user] }),
    );
  });

  it("reconnects to the stream route and stops on the server", async () => {
    const calls = capture();
    const { state, stopLocal, chatOptions } = useRendered({
      id: "c 1",
      api: "/chat",
      resume: false,
    });
    expect(chatOptions.resume).toBe(false);
    await chatOptions.transport.sendMessages({
      chatId: "c 1",
      messages: [user],
      trigger: "submit-message",
      messageId: undefined,
      abortSignal: undefined,
    });
    expect(JSON.parse(String(calls[0]?.init?.body))).toEqual({
      id: "c 1",
      message: user,
      trigger: "submit-message",
    });
    await chatOptions.transport.reconnectToStream({ chatId: "c 1" });
    expect(calls[1]?.url).toBe("/chat/c%201/stream");
    await state.stop();
    expect(stopLocal).toHaveBeenCalledOnce();
    expect(calls[2]).toEqual({
      url: "/chat/c%201/stop",
      init: { method: "POST" },
    });
  });

  it("sends the headers with the stop request", async () => {
    const calls = capture();
    const { state } = useRendered({
      id: "c1",
      headers: { authorization: "x" },
    });
    await state.stop();
    expect(calls[0]?.init).toEqual({
      method: "POST",
      headers: { authorization: "x" },
    });
  });

  it("throws in a Server Component", () => {
    expect(() => useAssistantOnServer({ id: "c1" })).toThrow(/toUIMessages/);
  });
});
