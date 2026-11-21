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
  archivedAt: undefined,
};

const echo = (name: string) =>
  tool({
    description: name,
    inputSchema: jsonSchema({ type: "object" }),
    execute: () => Promise.resolve(name),
  });

/** The agent's `toolApproval`, which `WorkflowAgent` keeps private. */
const approvalOf = (runtime: object): unknown =>
  (runtime as { toolApproval?: unknown }).toolApproval;

describe("createWorkflowAgentRuntime", () => {
  it("asks for the tenant's ask tools through toolApproval and drops denied ones", () => {
    const runtime = createWorkflowAgentRuntime({
      agent,
      model: () => new MockLanguageModelV4(),
      tools: { a: echo("a"), b: echo("b"), c: echo("c") },
      policies: { a: "auto", b: "ask", c: "deny" },
      toolApprovalSecret: { environmentVariable: "AI_APPROVAL_SECRET" },
    });

    expect(runtime.id).toBe("a1");
    expect(Object.keys(runtime.tools)).toEqual(["a", "b"]);
    expect(runtime.tools["b"]).not.toHaveProperty("needsApproval");
    expect(approvalOf(runtime)).toEqual({ b: "user-approval" });
  });

  it("passes the app's check, composed with the permission check, as toolApproval", async () => {
    const runtime = createWorkflowAgentRuntime({
      agent,
      model: () => new MockLanguageModelV4(),
      tools: { a: echo("a"), b: echo("b") },
      toolApproval: ({ toolCall }) =>
        toolCall.toolName === "a"
          ? { type: "denied", reason: "nope" }
          : "user-approval",
    });

    const check = approvalOf(runtime) as (options: unknown) => Promise<unknown>;

    expect(typeof check).toBe("function");
    expect(
      await check({ toolCall: { toolName: "a", input: {} } }),
    ).toMatchObject({ type: "denied", reason: "nope" });
    expect(await check({ toolCall: { toolName: "b", input: {} } })).toBe(
      "user-approval",
    );
  });
});
