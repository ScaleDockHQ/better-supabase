import { describe, expect, it } from "vitest";

import { createMemory } from "../../../src/blocks/memory/index.ts";
import { dbError } from "../../../src/core/errors.ts";

describe("createMemory hooks", () => {
  it("runs top-level hooks and each group's hooks", async () => {
    const seen: string[] = [];
    const memory = createMemory({
      transport: {
        call: (_schema, fn) => {
          seen.push(fn);
          return Promise.resolve(fn === "memory_view" ? null : 0);
        },
      },
      hooks: {
        render: {
          before: () => dbError("forbidden", "No rendering here"),
        },
        core: {
          view: {
            after: (result, [organizationId]) => {
              seen.push(`after view ${organizationId} ${String(result.ok)}`);
            },
          },
        },
      },
    });
    const rendered = await memory.render("o1");
    expect(rendered.ok).toBe(false);
    expect(await memory.core.view("o1").orThrow()).toBeUndefined();
    expect(seen).toEqual(["memory_view", "after view o1 true"]);
  });
});
