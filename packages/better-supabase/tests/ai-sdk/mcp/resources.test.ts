import { describe, expect, it } from "vitest";

import type { McpResourceClient } from "../../../src/ai-sdk/mcp/resources.ts";

import {
  mcpPromptMessages,
  mcpPrompts,
  mcpResourceTools,
} from "../../../src/ai-sdk/mcp/resources.ts";

const client = (): McpResourceClient =>
  // SAFETY: a minimal fake of the four methods under test.
  ({
    listResources: async (options?: { params?: { cursor?: string } }) =>
      options?.params?.cursor === undefined
        ? { resources: [{ uri: "file:///a.md", name: "a" }], nextCursor: "p2" }
        : { resources: [{ uri: "file:///b.bin", name: "b" }] },
    readResource: async ({ uri }: { uri: string }) => ({
      contents:
        uri === "file:///a.md"
          ? [{ uri, text: "x".repeat(10) }]
          : [{ uri, blob: "AAAA" }],
    }),
    listPrompts: async () => ({
      prompts: [
        { name: "review", arguments: [{ name: "file", required: true }] },
      ],
    }),
    getPrompt: async () => ({
      messages: [
        { role: "user", content: { type: "text", text: "Review it" } },
        {
          role: "assistant",
          content: { type: "resource_link", uri: "file:///a.md", name: "a" },
        },
      ],
    }),
  }) as unknown as McpResourceClient;

const call = (
  tools: ReturnType<typeof mcpResourceTools>,
  name: string,
  input: unknown,
) =>
  tools[name]?.execute?.(
    input as never,
    { toolCallId: "c", messages: [], context: undefined } as never,
  );

describe("mcpResourceTools", () => {
  it("lists every page", async () => {
    const tools = mcpResourceTools(client());

    expect(await call(tools, "list_resources", {})).toEqual({
      resources: [
        { uri: "file:///a.md", name: "a" },
        { uri: "file:///b.bin", name: "b" },
      ],
    });
  });

  it("reads a listed resource, truncated, and reports binary by size", async () => {
    const tools = mcpResourceTools(client(), { maxChars: 4 });

    expect(await call(tools, "read_resource", { uri: "file:///a.md" })).toEqual(
      { contents: [{ uri: "file:///a.md", text: "xxxx", truncated: true }] },
    );
    expect(
      await call(tools, "read_resource", { uri: "file:///b.bin" }),
    ).toEqual({ contents: [{ uri: "file:///b.bin", binary: true, bytes: 3 }] });
  });

  it("refuses a URI the server never listed", async () => {
    const tools = mcpResourceTools(client(), { prefix: "gh_" });

    expect(
      await call(tools, "gh_read_resource", { uri: "http://169.254.169.254" }),
    ).toEqual({ error: "This resource is not offered by the server." });
  });
});

describe("mcp prompts", () => {
  it("lists prompts with their arguments", async () => {
    const listed = await mcpPrompts(client());

    expect(listed.ok && listed.data).toEqual([
      { name: "review", arguments: [{ name: "file", required: true }] },
    ]);
  });

  it("returns model messages", async () => {
    const messages = await mcpPromptMessages(client(), "review", { file: "a" });

    expect(messages.ok && messages.data).toEqual([
      { role: "user", content: [{ type: "text", text: "Review it" }] },
      {
        role: "assistant",
        content: [{ type: "text", text: "[resource file:///a.md]" }],
      },
    ]);
  });

  it("returns an error result when the server fails", async () => {
    const failing = {
      getPrompt: async () => {
        throw new Error("boom");
      },
    };

    const result = await mcpPromptMessages(failing, "x");

    expect(result.ok).toBe(false);
  });
});
