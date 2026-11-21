import { generateText, jsonSchema, tool } from "ai";
import { MockLanguageModelV4 } from "ai/test";
import { describe, expect, it } from "vitest";

import {
  tenantContextSchema,
  tenantToolsContext,
} from "../../src/ai-sdk/tool-context.ts";

const USAGE = {
  inputTokens: { total: 1, noCache: 1, cacheRead: 0, cacheWrite: 0 },
  outputTokens: { total: 1, text: 1, reasoning: 0 },
};

describe("tenantToolsContext", () => {
  const seen: unknown[] = [];

  const lookup = tool({
    description: "Finds a record",
    inputSchema: jsonSchema<{ id: string }>({
      type: "object",
      properties: { id: { type: "string" } },
    }),
    contextSchema: tenantContextSchema,
    execute: ({ id }, { context }) => {
      seen.push(context);

      return { id, organizationId: context.organizationId };
    },
  });

  const plain = tool({
    description: "No context",
    inputSchema: jsonSchema<Record<string, never>>({
      type: "object",
      properties: {},
    }),
    execute: () => "ok",
  });

  it("fills only the tools that declare the tenant schema", () => {
    const tenant = { organizationId: "org-1", userId: "user-1" };

    expect(tenantToolsContext({ lookup, plain }, tenant)).toEqual({
      lookup: tenant,
    });
  });

  it("reaches execute through generateText", async () => {
    let step = 0;

    const model = new MockLanguageModelV4({
      doGenerate: async () => {
        step += 1;

        return step === 1
          ? {
              content: [
                {
                  type: "tool-call" as const,
                  toolCallId: "c1",
                  toolName: "lookup",
                  input: JSON.stringify({ id: "r1" }),
                },
              ],
              finishReason: { unified: "tool-calls" as const, raw: undefined },
              usage: USAGE,
              warnings: [],
            }
          : {
              content: [{ type: "text" as const, text: "done" }],
              finishReason: { unified: "stop" as const, raw: undefined },
              usage: USAGE,
              warnings: [],
            };
      },
    });

    const tools = { lookup };
    const tenant = { organizationId: "org-9", userId: "user-9" };

    await generateText({
      model,
      tools,
      toolsContext: tenantToolsContext(tools, tenant),
      prompt: "find r1",
      stopWhen: () => step >= 2,
    });

    expect(seen).toContainEqual(tenant);
  });

  it("rejects a context without an organization", async () => {
    const outcome = await tenantContextSchema["~standard"].validate({
      userId: "u",
    });

    expect(outcome.issues).toBeDefined();
  });
});
