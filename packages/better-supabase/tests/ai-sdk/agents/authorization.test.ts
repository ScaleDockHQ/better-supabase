import { jsonSchema, tool, type ToolSet } from "ai";
import { MockLanguageModelV4 } from "ai/test";
import { describe, expect, it, vi } from "vitest";

import type { Agent } from "../../../src/blocks/agents/index.ts";
import type {
  Knowledge,
  KnowledgeHit,
} from "../../../src/blocks/knowledge/index.ts";

import {
  agentClaims,
  agentRunContext,
  agentToolOperation,
  type AgentRuntimeOptions,
  createAgentRuntime,
} from "../../../src/ai-sdk/agents/index.ts";
import { DbException } from "../../../src/core/errors.ts";
import { AsyncResult } from "../../../src/core/result.ts";

const AT = Temporal.Instant.from("2026-01-01T00:00:00Z");

const agent = (over: Partial<Agent> = {}): Agent => ({
  id: "a1",
  organizationId: "o1",
  ownerId: "owner",
  slug: "writer",
  name: "Writer",
  description: "",
  instructions: "Be brief",
  model: "openai/gpt-5",
  tools: [],
  connectorIds: [],
  knowledgeScopes: [],
  starters: [],
  visibility: "organization",
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

const usage = {
  inputTokens: { total: 1, noCache: 1, cacheRead: 0, cacheWrite: 0 },
  outputTokens: { total: 1, text: 1, reasoning: 0 },
};

const toolCall = {
  content: [
    {
      type: "tool-call" as const,
      toolCallId: "call1",
      toolName: "a",
      input: "{}",
    },
  ],
  finishReason: { unified: "tool-calls" as const, raw: "tool_calls" },
  usage,
  warnings: [],
};

const answer = {
  content: [{ type: "text" as const, text: "Done" }],
  finishReason: { unified: "stop" as const, raw: "stop" },
  usage,
  warnings: [],
};

/** A model that calls tool `a` once, then answers. */
function callingModel(): MockLanguageModelV4 {
  let calls = 0;

  return new MockLanguageModelV4({
    modelId: "openai/gpt-5",
    doGenerate: () => {
      calls += 1;

      return Promise.resolve(calls === 1 ? toolCall : answer);
    },
  });
}

const toolA = (execute = vi.fn(() => Promise.resolve({ user: "evil" }))) => ({
  execute,
  tools: {
    a: tool({
      description: "a",
      inputSchema: jsonSchema({ type: "object" }),
      execute,
    }),
  } satisfies ToolSet,
});

function runtime(
  over: Partial<AgentRuntimeOptions> = {},
  model: MockLanguageModelV4 = callingModel(),
) {
  const { tools, execute } = toolA();

  return {
    model,
    execute,
    agent: createAgentRuntime({
      agent: agent(),
      model: () => model,
      tools,
      caller: { userId: "u1", organizationId: "o2" },
      ...over,
    }),
  };
}

describe("agentRunContext", () => {
  it("keeps the caller as the principal and the agent as the actor", () => {
    const context = agentRunContext(agent(), {
      userId: "u1",
      organizationId: "o2",
    });

    expect(context).toEqual({
      userId: "u1",
      organizationId: "o2",
      actor: { kind: "agent", id: "a1" },
      act: { agent: "a1", tools: [] },
    });
    expect(Object.isFrozen(context)).toBe(true);
    expect(Object.isFrozen(context.actor)).toBe(true);
  });

  it("has no principal without a caller, never the agent", () => {
    const context = agentRunContext(agent());
    expect(context.userId).toBeUndefined();
    expect(context.organizationId).toBe("o1");
    expect(Object.values(context)).not.toContain("a1");
  });

  it("carries the act level with the run's tools for database calls", () => {
    const context = agentRunContext(agent(), { userId: "u1" }, ["lookup"]);
    expect(context.act).toEqual({ agent: "a1", tools: ["lookup"] });
    expect(Object.isFrozen(context.act.tools)).toBe(true);
    expect(
      agentClaims({ sub: "u1", role: "authenticated" }, context.act),
    ).toEqual({
      sub: "u1",
      role: "authenticated",
      act: { kind: "agent", sub: "a1", tools: ["lookup"] },
    });
  });
});

describe("agentToolOperation", () => {
  it("prefers the provider's operation over the tool's own permission", () => {
    const operations = {
      "ai.tool.send_email": {
        permission: "email.send_external",
        meta: { risk: "high" as const, effects: ["external" as const] },
      },
    };

    expect(
      agentToolOperation("send_email", operations, {
        send_email: "email.send",
      }),
    ).toEqual({
      operation: "ai.tool.send_email",
      permission: "email.send_external",
      risk: "high",
      effects: ["external"],
    });
    expect(
      agentToolOperation("search", operations, { search: "docs.read" }),
    ).toEqual({ operation: "ai.tool.search", permission: "docs.read" });
    expect(agentToolOperation("ping", undefined, { ping: false })).toEqual({
      operation: "ai.tool.ping",
      permission: false,
    });
    expect(agentToolOperation("other")).toEqual({
      operation: "ai.tool.other",
      permission: undefined,
    });
  });

  it("looks up the tool's own operation in place of ai.tool.<name>", () => {
    const operations = {
      "invoices.void": { permission: "billing.manage" },
      "ai.tool.void": { permission: "ignored" },
    };

    expect(
      agentToolOperation("void", operations, {}, { void: "invoices.void" }),
    ).toEqual({ operation: "invoices.void", permission: "billing.manage" });
  });
});

describe("createAgentRuntime authorizeModel", () => {
  it("refuses the run before the model is called", async () => {
    for (const authorizeModel of [
      () => false,
      () => {
        throw new Error("down");
      },
    ]) {
      const check = vi.fn(authorizeModel);
      const { agent: run, model } = runtime({ authorizeModel: check });
      await expect(run.generate({ prompt: "Hi" })).rejects.toSatisfy(
        (error) =>
          error instanceof DbException &&
          error.kind === "forbidden" &&
          error.error.status === 403,
      );
      expect(model.doGenerateCalls).toHaveLength(0);
      expect(check).toHaveBeenCalledWith("openai/gpt-5", {
        userId: "u1",
        organizationId: "o2",
        actor: { kind: "agent", id: "a1" },
        act: { agent: "a1", tools: ["a"] },
      });
    }
  });

  it("checks before every model call", async () => {
    const allowed = vi.fn(() => Promise.resolve(true));
    const { agent: run, model } = runtime({ authorizeModel: allowed });
    expect((await run.generate({ prompt: "Hi" })).text).toBe("Done");
    expect(allowed).toHaveBeenCalledTimes(2);
    expect(model.doGenerateCalls).toHaveLength(2);

    let calls = 0;

    const once = vi.fn(() => {
      calls += 1;

      return calls === 1;
    });

    const refused = runtime({ authorizeModel: once });
    await expect(refused.agent.generate({ prompt: "Hi" })).rejects.toThrow(
      "openai/gpt-5",
    );
    expect(refused.model.doGenerateCalls).toHaveLength(1);
  });

  it("reads a model given as a string id", async () => {
    const check = vi.fn(() => false);

    const run = createAgentRuntime({
      agent: agent(),
      model: () => "anthropic/claude-sonnet-4.5",
      authorizeModel: check,
    });

    await expect(run.generate({ prompt: "Hi" })).rejects.toBeInstanceOf(
      DbException,
    );
    expect(check).toHaveBeenCalledWith(
      "anthropic/claude-sonnet-4.5",
      expect.anything(),
    );
  });
});

describe("createAgentRuntime gateway options", () => {
  it("attributes every call to the caller, not the model or the agent", async () => {
    const {
      agent: run,
      model,
      execute,
    } = runtime({
      gateway: {
        feature: "support",
        tags: ["team:x"],
        options: { user: "model-said", order: ["anthropic"] },
      },
    });

    await run.generate({ prompt: "Hi" });
    expect(execute).toHaveBeenCalledOnce();
    expect(model.doGenerateCalls).toHaveLength(2);

    for (const call of model.doGenerateCalls) {
      expect(call.providerOptions?.["gateway"]).toEqual({
        order: ["anthropic"],
        user: "u1",
        tags: ["org:o2", "feature:support", "agent:a1", "team:x"],
      });
    }
  });

  it("sends no user without a caller", async () => {
    const model = callingModel();

    const run = createAgentRuntime({
      agent: agent(),
      model: () => model,
      tools: toolA().tools,
      gateway: {},
    });

    await run.generate({ prompt: "Hi" });
    expect(model.doGenerateCalls[0]?.providerOptions?.["gateway"]).toEqual({
      tags: ["org:o1", "feature:agent", "agent:a1"],
    });
  });
});

describe("createAgentRuntime run context", () => {
  it("gives tools the caller as the principal and the agent as the actor", async () => {
    const approve = vi.fn(() => "approved" as const);
    const { agent: run } = runtime({ toolApproval: approve });
    await run.generate({
      prompt: "Hi",
      runtimeContext: { userId: "a1", actor: { kind: "user", id: "x" } },
    } as Parameters<typeof run.generate>[0]);

    const seen = (
      approve.mock.calls[0] as unknown as [
        { runtimeContext: Record<string, unknown> },
      ]
    )[0].runtimeContext;

    expect(seen).toMatchObject({
      userId: "u1",
      organizationId: "o2",
      actor: { kind: "agent", id: "a1" },
    });
  });
});

describe("createAgentRuntime results filter", () => {
  it("filters knowledge hits before the model sees them", async () => {
    const hit = (documentId: string): KnowledgeHit => ({
      documentId,
      index: 0,
      content: documentId,
      metadata: {},
      title: documentId,
      score: 1,
    });

    const search = vi.fn(() => AsyncResult.ok([hit("public"), hit("hidden")]));
    // SAFETY: the search tool calls only `search`.
    const knowledge = { search } as unknown as Knowledge;

    const results = vi.fn((hits: readonly KnowledgeHit[]) =>
      hits.filter((item) => item.documentId !== "hidden"),
    );

    const run = createAgentRuntime({
      agent: agent({ knowledgeScopes: [{ scope: "organization" }] }),
      model: () => callingModel(),
      knowledge: { knowledge, organizationId: "o2" },
      caller: { userId: "u1" },
      results,
    });

    const output = await run.tools["search_knowledge"]?.execute?.(
      { query: "q" },
      { toolCallId: "c1", messages: [], context: {} },
    );

    expect(output).toEqual({
      results: [{ id: "public#0", title: "public", content: "public" }],
    });
    expect(results).toHaveBeenCalledWith(expect.any(Array), {
      userId: "u1",
      organizationId: "o1",
      actor: { kind: "agent", id: "a1" },
      act: { agent: "a1", tools: ["search_knowledge"] },
      toolName: "search_knowledge",
      query: "q",
    });
  });
});

describe("createAgentRuntime tool operations", () => {
  const operations = {
    "ai.tool.a": { permission: "docs.write_all" },
  };

  it("checks the provider's permission over the tool's own", async () => {
    const authorizeTool = vi.fn(() => true);

    const { agent: run, execute } = runtime({
      operations,
      permissions: { a: "docs.write" },
      authorizeTool,
    });

    await run.generate({ prompt: "Hi" });
    expect(authorizeTool).toHaveBeenCalledWith(
      "docs.write_all",
      expect.objectContaining({
        toolName: "a",
        operation: "ai.tool.a",
        input: {},
        userId: "u1",
        actor: { kind: "agent", id: "a1" },
      }),
    );
    expect(execute).toHaveBeenCalledOnce();
  });

  it("denies when the check refuses, throws or no permission is declared", async () => {
    for (const over of [
      { permissions: { a: "docs.write" }, authorizeTool: () => false },
      {
        permissions: { a: "docs.write" },
        authorizeTool: () => Promise.reject(new Error("down")),
      },
      { authorizeTool: vi.fn(() => true) },
    ] satisfies Partial<AgentRuntimeOptions>[]) {
      const { agent: run, execute } = runtime(over);
      const result = await run.generate({ prompt: "Hi" });
      const parts = result.steps.flatMap((step) => step.content);
      expect(
        parts.filter((part) => part.type === "tool-approval-response"),
      ).toEqual([expect.objectContaining({ approved: false })]);
      expect(execute).not.toHaveBeenCalled();
    }
  });

  it("runs a public tool without a check", async () => {
    const authorizeTool = vi.fn(() => false);

    const { agent: run, execute } = runtime({
      permissions: { a: false },
      authorizeTool,
    });

    await run.generate({ prompt: "Hi" });
    expect(authorizeTool).not.toHaveBeenCalled();
    expect(execute).toHaveBeenCalledOnce();
  });

  it("asks the user before a high-risk operation runs", async () => {
    const { agent: run, execute } = runtime({
      operations: {
        "ai.tool.a": { permission: "docs.delete", meta: { risk: "high" } },
      },
      authorizeTool: () => true,
      toolApproval: () => "approved",
    });

    const result = await run.generate({ prompt: "Hi" });
    expect(result.content.map((part) => part.type)).toContain(
      "tool-approval-request",
    );
    expect(execute).not.toHaveBeenCalled();
  });
});
