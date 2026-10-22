import { describe, expect, it, vi } from "vitest";

import type { RunResult } from "../../../src/cli/core/io.ts";

import { createDevMcp, serveLines } from "../../../src/cli/mcp/server.ts";

const okEnvelope = (data: unknown): string =>
  JSON.stringify({ $schema: "x", status: "success", data });

interface Reply {
  readonly result: {
    readonly tools: { name: string; annotations: { readOnlyHint: boolean } }[];
    readonly isError?: boolean;
    readonly content: unknown[];
    readonly structuredContent: { error: { token: string } };
  };
  readonly error?: { readonly code: number };
}

function fakeRun(result: Partial<RunResult> = {}) {
  return vi.fn((_argv: readonly string[]): Promise<RunResult> =>
    Promise.resolve({
      code: 0,
      stdout: okEnvelope({ ok: true }),
      stderr: "",
      ...result,
    }),
  );
}

async function session(
  messages: readonly unknown[],
  options: { allowWrites?: boolean; run?: ReturnType<typeof fakeRun> } = {},
) {
  const run = options.run ?? fakeRun();

  const server = createDevMcp({
    run,
    cwd: "/app",
    env: {},
    ...(options.allowWrites ? { allowWrites: true } : {}),
  });

  const lines: string[] = [];

  async function* input() {
    for (const message of messages) {
      yield typeof message === "string" ? message : JSON.stringify(message);
    }
  }

  await serveLines(input(), server, (line) => lines.push(line));

  return {
    run,
    // SAFETY: the test reads only the fields each assertion checks.
    responses: lines.map((line) => JSON.parse(line) as Reply),
  };
}

const call = (id: number, name: string, args: unknown = {}) => ({
  jsonrpc: "2.0",
  id,
  method: "tools/call",
  params: { name, arguments: args },
});

describe("better-supabase mcp", () => {
  it("answers initialize and lists only read-only tools by default", async () => {
    const { responses } = await session([
      {
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: { protocolVersion: "2025-06-18" },
      },
      { jsonrpc: "2.0", method: "notifications/initialized" },
      { jsonrpc: "2.0", id: 2, method: "tools/list" },
    ]);

    expect(responses).toHaveLength(2);
    expect(responses[0]?.result).toMatchObject({
      protocolVersion: "2025-06-18",
      serverInfo: { name: "better-supabase" },
    });

    const tools = responses[1]?.result.tools ?? [];

    expect(tools.map((tool) => tool.name)).toContain("doctor");
    expect(tools.map((tool) => tool.name)).not.toContain("gen");
    expect(tools.every((tool) => tool.annotations.readOnlyHint)).toBe(true);
  });

  it("runs a tool's command with --json and returns the envelope", async () => {
    const run = fakeRun({ stdout: okEnvelope({ blocks: ["tags"] }) });

    const { responses } = await session(
      [call(1, "blocks_list", { category: "content" })],
      { run },
    );

    expect(run).toHaveBeenCalledWith(
      ["blocks", "list", "--category", "content", "--json", "--agent", "no"],
      { cwd: "/app", env: {} },
    );
    expect(responses[0]?.result).toMatchObject({
      structuredContent: { status: "success", data: { blocks: ["tags"] } },
    });
    expect(responses[0]?.result.isError).toBeUndefined();
  });

  it("marks a failed command as a tool error", async () => {
    const run = fakeRun({ code: 1, stderr: "2 errors" });

    const { responses } = await session([call(1, "doctor")], { run });

    expect(responses[0]?.result).toMatchObject({ isError: true });
    expect(responses[0]?.result.content[1]).toEqual({
      type: "text",
      text: "2 errors",
    });
  });

  it("refuses an unknown tool and a write tool without --allow-writes", async () => {
    const { responses } = await session([call(1, "nope"), call(2, "gen")]);

    expect(responses.map((response) => response.error?.code)).toEqual([
      -32_602, -32_602,
    ]);
  });

  it("asks for consent before a write and runs it with the token", async () => {
    const run = fakeRun();

    const first = await session([call(1, "add", { blocks: ["tags"] })], {
      allowWrites: true,
      run,
    });

    const refused = first.responses[0]!.result;

    expect(refused.isError).toBe(true);
    expect(refused.structuredContent).toMatchObject({
      status: "action_required",
      error: { code: "consent_required" },
    });
    expect(run).not.toHaveBeenCalled();

    const token = refused.structuredContent.error.token;

    const wrong = await session(
      [call(1, "add", { blocks: ["comments"], confirm: token })],
      { allowWrites: true, run },
    );

    expect(wrong.responses[0]?.result.isError).toBe(true);
    expect(run).not.toHaveBeenCalled();

    await session([call(1, "add", { blocks: ["tags"], confirm: token })], {
      allowWrites: true,
      run,
    });

    expect(run).toHaveBeenCalledWith(
      ["add", "tags", "--json", "--agent", "no"],
      expect.anything(),
    );
  });

  it.each([
    ["blocks_list", {}, ["blocks", "list"]],
    ["blocks_view", { block: "tags" }, ["blocks", "view", "tags"]],
    [
      "blocks_search",
      { text: "audit log" },
      ["blocks", "search", "audit", "log"],
    ],
    ["config", {}, ["config"]],
    ["config_preset", {}, ["config", "--preset"]],
    ["blocks_installed", {}, ["blocks", "list", "--installed"]],
    ["gen_check", {}, ["gen", "--check"]],
    [
      "add_preset_dry_run",
      { preset: "crm" },
      ["add", "--preset", "crm", "--dry-run"],
    ],
  ])("runs %s as the matching command", async (name, args, argv) => {
    const run = fakeRun();

    await session([call(1, name, args)], { run });

    expect(run).toHaveBeenCalledWith(
      [...argv, "--json", "--agent", "no"],
      expect.anything(),
    );
  });

  it.each([
    ["gen", {}, ["gen"]],
    ["upgrade", {}, ["upgrade"]],
    ["add_preset", { preset: "crm" }, ["add", "--preset", "crm"]],
    [
      "add_preset",
      { preset: "crm", allow_breaking: true },
      ["add", "--preset", "crm", "--allow-breaking"],
    ],
    ["remove", { blocks: ["tags"] }, ["remove", "tags"]],
  ])("runs the write tool %s after consent", async (name, args, argv) => {
    const run = fakeRun();

    const first = await session([call(1, name, args)], {
      allowWrites: true,
      run,
    });

    const token = first.responses[0]!.result.structuredContent.error.token;

    await session([call(1, name, { ...args, confirm: token })], {
      allowWrites: true,
      run,
    });

    expect(run).toHaveBeenCalledWith(
      [...argv, "--json", "--agent", "no"],
      expect.anything(),
    );
  });

  it("returns the raw output when a command prints no envelope", async () => {
    const run = fakeRun({ stdout: "not json" });

    const { responses } = await session([call(1, "config")], { run });

    expect(responses[0]?.result.content[0]).toEqual({
      type: "text",
      text: "not json",
    });
  });

  it("answers a parse error and invalid arguments", async () => {
    const { responses } = await session([
      "{not json",
      call(2, "blocks_view", { block: 1 }),
    ]);

    expect(responses[0]?.error?.code).toBe(-32_700);
    expect(responses[1]?.result.isError).toBe(true);
  });

  it("speaks the 2026-07-28 revision when a request carries its _meta", async () => {
    const { responses } = await session([
      {
        jsonrpc: "2.0",
        id: 1,
        method: "server/discover",
        params: {
          _meta: {
            "io.modelcontextprotocol/protocolVersion": "2026-07-28",
            "io.modelcontextprotocol/clientCapabilities": {},
          },
        },
      },
    ]);

    expect(responses[0]?.result).toMatchObject({
      resultType: "complete",
      capabilities: { tools: { listChanged: false } },
    });
  });
});
