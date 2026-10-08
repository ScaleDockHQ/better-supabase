import { asSchema } from "ai";
import { describe, expect, it, vi } from "vitest";

import type { Memory } from "../../src/blocks/memory/index.ts";

import { anthropicMemory, memoryTool } from "../../src/ai-sdk/memory/index.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

/**
 * The commands of Anthropic's memory tool at the pinned version and the
 * fields each one requires, from its documentation.
 */
const COMMANDS: Record<string, readonly string[]> = {
  view: ["path"],
  create: ["path", "file_text"],
  str_replace: ["path", "old_str"],
  insert: ["path", "insert_line", "insert_text"],
  delete: ["path"],
  rename: ["old_path", "new_path"],
};

interface Variant {
  readonly properties: Record<string, { readonly const?: string }>;
  readonly required: readonly string[];
}

// SAFETY: the run is never reached; the test reads the schema only.
const memory = {} as Memory;

describe(`Anthropic memory tool ${SPEC_PINS.anthropicMemoryTool}`, () => {
  it("memoryTool accepts every command with the documented fields", async () => {
    const schema = await asSchema(memoryTool(memory, "org").inputSchema)
      .jsonSchema;
    // SAFETY: the tool's schema is a `oneOf` of object variants.
    const variants = (schema as { oneOf: Variant[] }).oneOf;
    const commands = Object.fromEntries(
      variants.map((variant) => [
        variant.properties["command"]?.const,
        variant.required.filter((field) => field !== "command"),
      ]),
    );
    expect(commands).toEqual(COMMANDS);
  });

  it("anthropicMemory asks the provider for the pinned tool version", () => {
    const memory_20250818 = vi.fn(() => ({}) as never);
    anthropicMemory({ memory_20250818 }, memory, "org");
    expect(SPEC_PINS.anthropicMemoryTool).toBe("20250818");
    expect(memory_20250818).toHaveBeenCalledOnce();
  });
});
