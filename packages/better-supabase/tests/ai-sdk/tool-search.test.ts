import { describe, expect, it } from "vitest";

import { toolSearchFrom } from "../../src/ai-sdk/tool-search.ts";
import { dbError } from "../../src/core/errors.ts";
import { err, ok } from "../../src/core/result.ts";

describe("toolSearchFrom", () => {
  it("builds a search tool over the catalog", async () => {
    let asked: unknown;

    const tool = toolSearchFrom({
      maxResults: 2,
      catalog: {
        search: async (query, options) => {
          asked = { query, ...options };

          return ok([{ name: "a" }, { name: "b" }]);
        },
      },
    });

    expect(tool).toBeDefined();
    expect(asked).toBeUndefined();
  });

  it("searches the catalog and throws its error", async () => {
    const good = toolSearchFrom({
      maxResults: 2,
      catalog: { search: async () => ok([{ name: "a" }]) },
    });

    const bad = toolSearchFrom({
      catalog: { search: async () => err(dbError("network", "down")) },
    });

    const find = (tool: object): unknown => {
      // SAFETY: the SDK stores the search function under a symbol key.
      const bag = tool as Record<symbol, unknown>;

      return Object.getOwnPropertySymbols(tool)
        .map((symbol) => bag[symbol])
        .find((value) => typeof value === "function");
    };

    const run = async (tool: object): Promise<unknown> => {
      const search = find(tool);

      if (typeof search !== "function") {
        throw new TypeError("no search function");
      }

      return search({ query: "q" });
    };

    await expect(run(good)).resolves.toEqual(["a"]);
    await expect(run(bad)).rejects.toThrow(/down/);
  });

  it("accepts an error-returning catalog", () => {
    const tool = toolSearchFrom({
      catalog: { search: async () => err(dbError("network", "down")) },
    });

    expect(tool).toBeDefined();
  });
});
