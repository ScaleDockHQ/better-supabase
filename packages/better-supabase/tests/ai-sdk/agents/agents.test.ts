import {
  generateText,
  jsonSchema,
  streamText,
  tool,
  wrapLanguageModel,
} from "ai";
import { convertArrayToReadableStream, MockLanguageModelV4 } from "ai/test";
import { describe, expect, it, vi } from "vitest";

import type { Agent } from "../../../src/blocks/agents/index.ts";
import type { Knowledge } from "../../../src/blocks/knowledge/index.ts";

import {
  agentScopes,
  agentTools,
  agentToolApproval,
  createAgentRuntime,
  ModerationBlockedError,
  moderationMiddleware,
} from "../../../src/ai-sdk/agents/index.ts";
import { AsyncResult } from "../../../src/core/result.ts";
import { fakeChats } from "../chat/fakes.ts";

const AT = Temporal.Instant.from("2026-01-01T00:00:00Z");

const agent = (over: Partial<Agent> = {}): Agent => ({
  id: "a1",
  organizationId: "o1",
  ownerId: "u1",
  slug: "writer",
  name: "Writer",
  description: "",
  instructions: "Be brief",
  model: "openai/gpt-5",
  tools: [],
  connectorIds: [],
  knowledgeScopes: [],
  starters: [],
  visibility: "private",
  publishedAt: undefined,
  installCount: 0,
  ratingCount: 0,
  rating: undefined,
  installed: false,
  myRating: undefined,
  skills: [],
  createdAt: AT,
  updatedAt: AT,
  ...over,
});

const echo = (name: string) =>
  tool({
    description: name,
    inputSchema: jsonSchema({ type: "object" }),
    execute: () => Promise.resolve(name),
  });

const usage = {
  inputTokens: { total: 1, noCache: 1, cacheRead: 0, cacheWrite: 0 },
  outputTokens: { total: 1, text: 1, reasoning: 0 },
};

function model(text: string): MockLanguageModelV4 {
  return new MockLanguageModelV4({
    doGenerate: () =>
      Promise.resolve({
        content: [{ type: "text", text }],
        finishReason: { unified: "stop", raw: "stop" },
        usage,
        warnings: [],
      }),
    doStream: () =>
      Promise.resolve({
        stream: convertArrayToReadableStream([
          { type: "stream-start", warnings: [] },
          { type: "text-start", id: "t" },
          { type: "text-delta", id: "t", delta: text },
          { type: "text-end", id: "t" },
          {
            type: "finish",
            finishReason: { unified: "stop", raw: "stop" },
            usage,
          },
        ]),
      }),
  });
}

describe("agentTools", () => {
  it("keeps the agent's tools, drops denied ones and asks for others", () => {
    const available = { a: echo("a"), b: echo("b"), c: echo("c") };
    const tools = agentTools(agent({ tools: ["a", "b"] }), available, {
      b: "ask",
      c: "auto",
    });
    expect(Object.keys(tools)).toEqual(["a", "b"]);
    expect(agentToolApproval(tools, { b: "ask", c: "ask" })).toEqual({
      b: "user-approval",
    });
    expect(Object.keys(agentTools(agent(), available, { a: "deny" }))).toEqual([
      "b",
      "c",
    ]);
  });
});

describe("agentScopes", () => {
  it("resolves the agent's own scope", () => {
    expect(
      agentScopes(
        agent({
          knowledgeScopes: [
            { scope: "agent" },
            { scope: "agent", id: "a2" },
            { scope: "organization" },
          ],
        }),
      ),
    ).toEqual([
      { scope: "agent", id: "a1" },
      { scope: "agent", id: "a2" },
      { scope: "organization" },
    ]);
  });
});

describe("createAgentRuntime", () => {
  it("builds a ToolLoopAgent with knowledge search and both instructions", async () => {
    const pick = vi.fn((id: string | undefined) => {
      expect(id).toBe("openai/gpt-5");
      return model("Done");
    });
    const search = vi.fn(() => AsyncResult.ok([]));
    const knowledge = { search } as unknown as Knowledge;
    const runtime = createAgentRuntime({
      agent: agent({ knowledgeScopes: [{ scope: "agent" }] }),
      model: pick,
      tools: { a: echo("a") },
      policies: { a: "ask" },
      knowledge: { knowledge, organizationId: "o1" },
      instructions: "Follow the rules",
    });
    expect(runtime.id).toBe("a1");
    expect(Object.keys(runtime.tools)).toEqual(["a", "search_knowledge"]);
    const result = await runtime.generate({ prompt: "Hi" });
    expect(result.text).toBe("Done");
    const call = vi.mocked(pick).mock.results[0]?.value as MockLanguageModelV4;
    expect(call.doGenerateCalls[0]?.prompt[0]).toEqual({
      role: "system",
      content: "Follow the rules\n\nBe brief",
    });
  });

  it("waits for the user before running an ask tool", async () => {
    const execute = vi.fn(() => Promise.resolve("ran"));
    const runtime = createAgentRuntime({
      agent: agent(),
      model: () =>
        new MockLanguageModelV4({
          doGenerate: () =>
            Promise.resolve({
              content: [
                {
                  type: "tool-call",
                  toolCallId: "call1",
                  toolName: "a",
                  input: "{}",
                },
              ],
              finishReason: { unified: "tool-calls", raw: "tool_calls" },
              usage,
              warnings: [],
            }),
        }),
      tools: {
        a: tool({
          description: "a",
          inputSchema: jsonSchema({ type: "object" }),
          execute,
        }),
      },
      policies: { a: "ask" },
    });
    const result = await runtime.generate({ prompt: "Hi" });
    expect(result.content.map((part) => part.type)).toContain(
      "tool-approval-request",
    );
    expect(execute).not.toHaveBeenCalled();
  });

  it("skips knowledge without scopes and empty instructions", () => {
    const runtime = createAgentRuntime({
      agent: agent({ instructions: "" }),
      model: () => model("x"),
      knowledge: { knowledge: {} as Knowledge, organizationId: "o1" },
    });
    expect(Object.keys(runtime.tools)).toEqual([]);
  });
});

describe("moderationMiddleware", () => {
  const options = (
    check: (text: string, stage: "input" | "output") => unknown,
  ) => {
    const fake = fakeChats();
    return {
      fake,
      middleware: moderationMiddleware({
        chats: fake.chats,
        organizationId: "o1",
        chatId: "c1",
        userId: "u1",
        check: (text, stage) =>
          Promise.resolve(check(text, stage) as undefined),
      }),
    };
  };

  it("blocks the input and records the verdict", async () => {
    const { fake, middleware } = options((text, stage) =>
      stage === "input" && text === "bad"
        ? { action: "block", category: "abuse", score: 0.9 }
        : undefined,
    );
    const wrapped = wrapLanguageModel({ model: model("ok"), middleware });
    await expect(
      generateText({ model: wrapped, prompt: "bad" }),
    ).rejects.toBeInstanceOf(ModerationBlockedError);
    expect(fake.moderated).toEqual([
      {
        organizationId: "o1",
        stage: "input",
        action: "block",
        category: "abuse",
        chatId: "c1",
        userId: "u1",
        score: 0.9,
      },
    ]);
    expect((await generateText({ model: wrapped, prompt: "fine" })).text).toBe(
      "ok",
    );
  });

  it("flags and blocks generated output", async () => {
    const { fake, middleware } = options((text, stage) =>
      stage === "input"
        ? undefined
        : text === "secret"
          ? { action: "block", category: "leak" }
          : { action: "flag", category: "tone" },
    );
    expect(
      (
        await generateText({
          model: wrapLanguageModel({ model: model("meh"), middleware }),
          prompt: "Hi",
        })
      ).text,
    ).toBe("meh");
    expect(fake.moderated).toHaveLength(1);
    await expect(
      generateText({
        model: wrapLanguageModel({ model: model("secret"), middleware }),
        prompt: "Hi",
      }),
    ).rejects.toThrow("output was blocked");
  });

  it("ends a blocked stream with an error part", async () => {
    const { middleware } = options((text, stage) =>
      stage === "output" && text === "secret"
        ? { action: "block", category: "leak" }
        : { action: "allow", category: "ok" },
    );
    const errors: unknown[] = [];
    const result = streamText({
      model: wrapLanguageModel({ model: model("secret"), middleware }),
      prompt: "Hi",
      onError: ({ error }) => {
        errors.push(error);
      },
    });
    await result.consumeStream();
    expect(errors[0]).toBeInstanceOf(ModerationBlockedError);

    const clean = streamText({
      model: wrapLanguageModel({ model: model("fine"), middleware }),
      prompt: "Hi",
    });
    expect(await clean.text).toBe("fine");
  });

  it("fails when the verdict cannot be recorded", async () => {
    const fake = fakeChats();
    const middleware = moderationMiddleware({
      chats: {
        ...fake.chats,
        moderation: {
          ...fake.chats.moderation,
          record: () =>
            AsyncResult.err({
              kind: "network",
              message: "down",
              status: 503,
            } as never),
        },
      },
      organizationId: "o1",
      check: () => Promise.resolve({ action: "flag", category: "x" }),
    });
    await expect(
      generateText({
        model: wrapLanguageModel({ model: model("x"), middleware }),
        prompt: "Hi",
      }),
    ).rejects.toThrow("down");
  });
});
