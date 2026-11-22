import type { MemoryProvider, MemoryToolsContext } from "eve/memory";

import { describe, expect, it } from "vitest";

import type { Knowledge } from "../../src/blocks/knowledge/index.ts";
import type { Memory } from "../../src/blocks/memory/index.ts";
import type { EveMemoryToolsContext } from "../../src/eve/index.ts";

import { supabaseMemory } from "../../src/eve/index.ts";

// Only the types are under test: the provider is built but never called.
// SAFETY: stubs, no method is called.
const memory = {} as Memory;

// SAFETY: stubs, no method is called.
const knowledge = {} as Knowledge;
const asOurs = (context: MemoryToolsContext): EveMemoryToolsContext => context;

describe("named memory scopes against eve's own types", () => {
  it("builds a provider eve accepts, with every scope form", () => {
    const provider: MemoryProvider = supabaseMemory({
      memory,
      knowledge,
      scopes: [
        "user",
        { scope: "organization", write: true },
        {
          scope: "record",
          subject: (ctx) => {
            const key: string = ctx.memory.scope.key;

            return key === "" ? undefined : { type: "contact", id: key };
          },
        },
      ],
    });

    expect(provider).toBeDefined();
  });

  it("reads the fields from eve's tools context that the provider uses", () => {
    expect(asOurs).toBeTypeOf("function");
  });
});
