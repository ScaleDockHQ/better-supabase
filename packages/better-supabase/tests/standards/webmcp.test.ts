import { describe, expect, it } from "vitest";

import type { ModelContextLike } from "../../src/webmcp/index.ts";

import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import { blockAction, registerWebMcpTools } from "../../src/webmcp/index.ts";

type Tool = Parameters<ModelContextLike["registerTool"]>[0];

function fake() {
  const tools: Tool[] = [];
  const signals: (AbortSignal | undefined)[] = [];

  const modelContext: ModelContextLike = {
    registerTool: (tool, options) => {
      tools.push(tool);
      signals.push(options?.signal);
    },
  };

  return { modelContext, tools, signals };
}

const action = (name: string, permission: string | null) =>
  blockAction({
    name,
    description: "Does a thing",
    inputSchema: { type: "object", properties: {} },
    permission,
    readOnly: true,
    call: (input: { n?: number }) =>
      Promise.resolve(
        input.n === undefined
          ? { ok: false, data: null, error: { message: "n is required" } }
          : { ok: true, data: { n: input.n }, error: null },
      ),
  });

describe("WebMCP draft report 2026-09-30", () => {
  it("is pinned to the report behind registerTool and its annotations", () => {
    expect(SPEC_PINS.webmcp).toBe("CG-2026-09-30");
  });

  it("registers permitted actions with annotations and an abort signal", async () => {
    const { modelContext, tools, signals } = fake();

    const registration = await registerWebMcpTools(
      [
        action("read_a", "a.read"),
        action("read_b", "b.read"),
        action("open", null),
      ],
      { modelContext, can: (permission) => permission === "a.read" },
    );

    expect(registration.registered).toEqual(["read_a", "open"]);
    expect(registration.skipped).toEqual([
      { name: "read_b", reason: "denied" },
    ]);
    expect(tools[0]?.annotations).toEqual({
      readOnlyHint: true,
      untrustedContentHint: false,
      consequentialHint: false,
    });

    registration.unregister();

    expect(signals[0]?.aborted).toBe(true);
  });

  it("checks the permission again on every call", async () => {
    const { modelContext, tools } = fake();
    let allowed = true;

    await registerWebMcpTools([action("read_a", "a.read")], {
      modelContext,
      can: () => allowed,
    });

    await expect(tools[0]?.execute({ n: 1 })).resolves.toEqual({ n: 1 });

    allowed = false;

    await expect(tools[0]?.execute({ n: 1 })).rejects.toThrow("a.read");
  });

  it("rejects with the error message of a failed Result", async () => {
    const { modelContext, tools } = fake();

    await registerWebMcpTools([action("read_a", null)], {
      modelContext,
      can: () => true,
    });

    await expect(tools[0]?.execute({})).rejects.toThrow("n is required");
  });

  it("skips names the draft rejects and reports a missing model context", async () => {
    const { modelContext } = fake();

    const invalid = await registerWebMcpTools([action("not valid!", null)], {
      modelContext,
      can: () => true,
    });

    expect(invalid.skipped).toEqual([
      { name: "not valid!", reason: "invalid-name" },
    ]);

    const none = await registerWebMcpTools([action("ok_name", null)], {
      can: () => true,
    });

    expect(none.skipped).toEqual([
      { name: "ok_name", reason: "no-model-context" },
    ]);
  });
});
