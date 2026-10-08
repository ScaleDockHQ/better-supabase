import { type Tool, tool, jsonSchema } from "ai";
import { MockLanguageModelV4 } from "ai/test";
import { describe, expect, it, vi } from "vitest";

import type { Job } from "../../../src/blocks/jobs/queue.ts";
import type {
  Memory,
  MemoryCommand,
  MemoryRecord,
} from "../../../src/blocks/memory/index.ts";

import {
  type ExtractMemoriesPayload,
  anthropicMemory,
  extractMemories,
  memoryTool,
  recallTool,
  withMemory,
} from "../../../src/ai-sdk/memory/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult, err, ok } from "../../../src/core/result.ts";
import { SPEC_PINS } from "../../../src/core/spec-pins.ts";

const okResult = <T>(value: T) => AsyncResult.from(async () => ok(value));
const failed = (message: string) =>
  AsyncResult.from(async () => err(dbError("forbidden", message)));

const options = { toolCallId: "c1", messages: [], context: {} };

function fakeMemory(over: Partial<Record<string, unknown>> = {}) {
  const run = vi.fn((_org: string, command: MemoryCommand) =>
    command.command === "delete" ? failed("no such file") : okResult("done"),
  );
  const search = vi.fn(() =>
    okResult([{ id: "m1", content: "Likes tea", score: 1, similarity: 0.9 }]),
  );
  const saveExtracted = vi.fn(
    (
      _org: string,
      facts: readonly string[],
    ): ReturnType<Memory["saveExtracted"]> =>
      okResult(
        facts.map((fact) => ({ content: fact }) as unknown as MemoryRecord),
      ),
  );
  const memory = {
    run,
    archival: { search },
    render: () => okResult("<memories></memories>"),
    saveExtracted,
    ...over,
  };
  // SAFETY: the adapters call only these members.
  return { memory: memory as unknown as Memory, run, search, saveExtracted };
}

describe("memoryTool", () => {
  it("runs commands and returns failures as text", async () => {
    const { memory, run } = fakeMemory();
    const ns = { scope: "agent" as const, agentId: "a1" };
    const memoryCommands = memoryTool(memory, "org", ns);
    expect(memoryCommands.description).toContain("/memories");
    expect(
      await memoryCommands.execute?.(
        { command: "view", path: "/memories" },
        options,
      ),
    ).toBe("done");
    expect(run).toHaveBeenCalledWith(
      "org",
      { command: "view", path: "/memories" },
      ns,
    );
    expect(
      await memoryCommands.execute?.(
        { command: "delete", path: "/memories/x" },
        options,
      ),
    ).toBe("Error: no such file");
  });
});

describe("anthropicMemory", () => {
  it("backs the provider's pinned memory tool with the block", async () => {
    const { memory } = fakeMemory();
    let execute: ((input: MemoryCommand) => Promise<string>) | undefined;
    const provided: Tool = tool({
      inputSchema: jsonSchema<MemoryCommand>({}),
      execute: (input) => execute?.(input) ?? Promise.resolve(""),
    });
    const tools = {
      memory_20250818: vi.fn((opts: { execute: typeof execute & {} }) => {
        execute = opts.execute;
        return provided;
      }),
    };
    expect(anthropicMemory(tools, memory, "org")).toBe(provided);
    expect(tools.memory_20250818).toHaveBeenCalledOnce();
    expect(SPEC_PINS.anthropicMemoryTool).toBe("20250818");
    expect(await execute?.({ command: "view", path: "/memories" })).toBe(
      "done",
    );
  });
});

describe("recallTool", () => {
  it("searches archival memory", async () => {
    const { memory, search } = fakeMemory();
    const recall = recallTool(memory, "org", undefined, { k: 2 });
    expect(recall.description).toContain("remember");
    const signal = new AbortController().signal;
    expect(
      await recall.execute?.(
        { query: "drinks" },
        { ...options, abortSignal: signal },
      ),
    ).toEqual({ memories: [{ id: "m1", content: "Likes tea" }] });
    expect(search).toHaveBeenCalledWith("org", "drinks", undefined, {
      k: 2,
      signal,
    });
    await recallTool(memory, "org", undefined, { description: "d" }).execute?.(
      { query: "q" },
      options,
    );
    expect(search).toHaveBeenLastCalledWith("org", "q", undefined, { k: 5 });

    const { memory: failing } = fakeMemory({
      archival: { search: () => failed("denied") },
    });
    await expect(
      recallTool(failing, "org").execute?.({ query: "q" }, options),
    ).rejects.toThrow("denied");
  });
});

describe("withMemory", () => {
  it("appends core memory to the instructions", async () => {
    const { memory } = fakeMemory();
    expect(await withMemory("Be brief.", memory, "org")).toContain(
      "Be brief.\n\nWhat you remember",
    );
    const empty = fakeMemory({ render: () => okResult("") }).memory;
    expect(await withMemory("Be brief.", empty, "org")).toBe("Be brief.");
    const broken = fakeMemory({ render: () => failed("x") }).memory;
    expect(await withMemory("Be brief.", broken, "org")).toBe("Be brief.");
  });
});

function factModel(facts: readonly string[]) {
  return new MockLanguageModelV4({
    doGenerate: async () => ({
      content: [{ type: "text", text: JSON.stringify({ elements: facts }) }],
      finishReason: { unified: "stop", raw: "stop" },
      usage: {
        inputTokens: { total: 5, noCache: 5, cacheRead: 0, cacheWrite: 0 },
        outputTokens: { total: 5, text: 5, reasoning: 0 },
      },
      warnings: [],
    }),
  });
}

describe("extractMemories", () => {
  // SAFETY: the handler never reads the job.
  const job = {} as Job<ExtractMemoriesPayload>;

  it("saves the facts the model finds for the owner", async () => {
    const { memory, saveExtracted } = fakeMemory();
    const handler = extractMemories({
      model: factModel(["Likes tea", "Works at Acme", "Third"]),
      memory,
      maxFacts: 2,
    });
    const saved = await handler(
      {
        organization_id: "org",
        owner_id: "u1",
        text: "I like tea and work at Acme",
        source_message_id: "m9",
        scope: "agent",
        agent_id: "a1",
      },
      job,
      new AbortController().signal,
    );
    expect(saved).toBe(2);
    expect(saveExtracted).toHaveBeenCalledWith(
      "org",
      ["Likes tea", "Works at Acme"],
      { ownerId: "u1", scope: "agent", agentId: "a1" },
      { sourceMessageId: "m9" },
    );
  });

  it("throws when saving fails", async () => {
    const { memory } = fakeMemory({ saveExtracted: () => failed("db down") });
    const handler = extractMemories({
      model: factModel([]),
      memory,
      instructions: "Find facts.",
    });
    await expect(
      handler(
        { organization_id: "org", owner_id: "u1", text: "hi" },
        job,
        new AbortController().signal,
      ),
    ).rejects.toThrow("db down");
  });
});
