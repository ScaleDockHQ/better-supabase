import type { ChatTransport, UIMessage } from "ai";

import { afterEach, describe, expect, it, vi } from "vitest";

import {
  durableTransport,
  useDurableAssistant,
} from "../../../../src/ai-sdk/workflow/react/index.ts";
import {
  durableTransport as durableTransportOnServer,
  useDurableAssistant as useDurableAssistantOnServer,
} from "../../../../src/ai-sdk/workflow/react/server.ts";

const chatHook = vi.hoisted(() => vi.fn());

vi.mock("react", () => ({
  useMemo: (make: () => unknown) => make(),
  useCallback: (callback: unknown) => callback,
}));

vi.mock("@ai-sdk/react", () => ({ useChat: chatHook }));

const user: UIMessage = {
  id: "u1",
  role: "user",
  parts: [{ type: "text", text: "Delete the file" }],
};
const answered: UIMessage = {
  id: "a1",
  role: "assistant",
  parts: [
    {
      type: "tool-remove",
      toolCallId: "t1",
      state: "approval-responded",
      input: { path: "a.txt" },
      approval: { id: "approval-t1", approved: false, reason: "keep it" },
    },
    {
      type: "dynamic-tool",
      toolName: "write",
      toolCallId: "t2",
      state: "approval-responded",
      input: {},
      approval: { id: "approval-t2", approved: true },
    },
    { type: "text", text: "Asking first." },
  ],
};

const SSE = 'data: {"type":"start"}\n\ndata: {"type":"finish"}\n\n';

function capture() {
  const calls: { url: string; init: RequestInit | undefined }[] = [];
  vi.stubGlobal(
    "fetch",
    vi.fn(async (url: string, init?: RequestInit) => {
      calls.push({ url, init });
      return new Response(SSE, {
        headers: {
          "content-type": "text/event-stream",
          "x-workflow-run-id": "wrun_1",
        },
      });
    }),
  );
  return calls;
}

async function drain(stream: ReadableStream<unknown>): Promise<void> {
  const reader = stream.getReader();
  while (!(await reader.read()).done);
}

afterEach(() => {
  vi.unstubAllGlobals();
  chatHook.mockReset();
});

describe("durableTransport", () => {
  const config = {
    api: "/api/chat",
    model: "openai/gpt-5",
    body: { projectId: "p" },
    headers: { "x-test": "1" },
  };

  it("sends the newest user message with the model", async () => {
    const calls = capture();
    const transport = durableTransport(config);
    await drain(
      await transport.sendMessages({
        chatId: "c1",
        messages: [user],
        trigger: "submit-message",
        messageId: undefined,
        abortSignal: undefined,
      }),
    );
    expect(calls[0]?.url).toBe("/api/chat");
    expect(new Headers(calls[0]?.init?.headers).get("x-test")).toBe("1");
    expect(JSON.parse(String(calls[0]?.init?.body))).toEqual({
      projectId: "p",
      id: "c1",
      message: user,
      trigger: "submit-message",
      model: "openai/gpt-5",
    });
  });

  it("sends the answered approvals of the last answer", async () => {
    const calls = capture();
    const transport = durableTransport(config);
    await drain(
      await transport.sendMessages({
        chatId: "c1",
        messages: [user, answered],
        trigger: "submit-message",
        messageId: "a1",
        abortSignal: new AbortController().signal,
      }),
    );
    expect(JSON.parse(String(calls[0]?.init?.body))).toEqual({
      projectId: "p",
      id: "c1",
      approvals: [
        { approvalId: "approval-t1", approved: false, reason: "keep it" },
        { approvalId: "approval-t2", approved: true },
      ],
    });
  });

  it("reconnects to the chat's stream route", async () => {
    const calls = capture();
    const transport = durableTransport({ ...config, headers: undefined });
    const stream = await transport.reconnectToStream({ chatId: "c 1" });
    await drain(stream!);
    expect(calls[0]?.url).toBe("/api/chat/c%201/stream?startIndex=0");
  });
});

describe("useDurableAssistant", () => {
  it("does not resume by default and continues after approvals", () => {
    chatHook.mockReturnValue({ messages: [], stop: vi.fn() });
    useDurableAssistant({ id: "c1" });
    const options = chatHook.mock.lastCall?.[0] as {
      transport: ChatTransport<UIMessage>;
      resume: boolean;
      sendAutomaticallyWhen: (input: { messages: UIMessage[] }) => boolean;
    };
    expect(options.resume).toBe(false);
    expect(options.sendAutomaticallyWhen({ messages: [user, answered] })).toBe(
      true,
    );
    expect(options.sendAutomaticallyWhen({ messages: [user] })).toBe(false);
  });

  it("keeps the caller's resume", () => {
    chatHook.mockReturnValue({ messages: [], stop: vi.fn() });
    useDurableAssistant({ id: "c1", resume: true });
    expect(chatHook.mock.lastCall?.[0]).toMatchObject({ resume: true });
  });

  it("throws in a Server Component", () => {
    expect(() => useDurableAssistantOnServer({ id: "c1" })).toThrow(
      /Client Components/,
    );
    expect(() =>
      durableTransportOnServer({
        api: "/api/chat",
        model: undefined,
        body: undefined,
        headers: undefined,
      }),
    ).toThrow(/Client Components/);
  });
});
