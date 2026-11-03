import { jsonSchema, tool } from "ai";
import { MockLanguageModelV4 } from "ai/test";
import { describe, expect, it } from "vitest";

import type { Agent } from "../../../src/blocks/agents/index.ts";

import { createWorkflowAgentRuntime } from "../../../src/ai-sdk/workflow/index.ts";

const AT = Temporal.Instant.from("2026-01-01T00:00:00Z");

const agent: Agent = {
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
};

const echo = (name: string) =>
  tool({
    description: name,
    inputSchema: jsonSchema({ type: "object" }),
    execute: () => Promise.resolve(name),
  });

const needs = async (value: unknown): Promise<boolean> => {
  const fn = (value as { needsApproval?: unknown }).needsApproval;

  return typeof fn === "function"
    ? Boolean(await (fn as (input: unknown) => unknown)({}))
    : Boolean(fn);
};

describe("createWorkflowAgentRuntime", () => {
  it("asks for the tenant's ask tools and drops denied ones", async () => {
    const runtime = createWorkflowAgentRuntime({
      agent,
      model: () => new MockLanguageModelV4(),
      tools: { a: echo("a"), b: echo("b"), c: echo("c") },
      policies: { a: "auto", b: "ask", c: "deny" },
      toolApprovalSecret: { environmentVariable: "AI_APPROVAL_SECRET" },
    });

    expect(runtime.id).toBe("a1");
    expect(Object.keys(runtime.tools)).toEqual(["a", "b"]);
    expect(await needs(runtime.tools["a"])).toBe(false);
    expect(await needs(runtime.tools["b"])).toBe(true);
  });

  it("denies a call the app's check denies and asks when it asks", async () => {
    const runtime = createWorkflowAgentRuntime({
      agent,
      model: () => new MockLanguageModelV4(),
      tools: { a: echo("a"), b: echo("b") },
      toolApproval: ({ toolCall }) =>
        toolCall.toolName === "a"
          ? { type: "denied", reason: "nope" }
          : "user-approval",
    });

    await expect(needs(runtime.tools["a"])).rejects.toThrow("nope");
    expect(await needs(runtime.tools["b"])).toBe(true);
  });
});
