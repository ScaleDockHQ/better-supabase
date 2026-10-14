import { describe, expect, it } from "vitest";

import {
  operationMeta,
  operationPermission,
} from "../../src/core/operations.ts";

const operations = {
  "mcp.tool.search_posts": {
    permission: "posts.read",
    meta: { risk: "low" as const, effects: ["read" as const] },
  },
  "ai.tool.empty": { permission: "" },
};

describe("operationPermission", () => {
  it("prefers the provider's entry, then the module's own key", () => {
    expect(operationPermission(operations, "mcp.tool.search_posts", "x")).toBe(
      "posts.read",
    );
    expect(
      operationPermission(operations, "mcp.tool.other", "posts.write"),
    ).toBe("posts.write");
    expect(
      operationPermission(undefined, "mcp.tool.other", "posts.write"),
    ).toBe("posts.write");
    expect(operationPermission(operations, "ai.tool.empty")).toBeUndefined();
  });

  it("ignores inherited names", () => {
    expect(operationPermission(operations, "toString", "kept")).toBe("kept");
    expect(operationMeta(operations, "constructor")).toBeUndefined();
  });

  it("reads meta from the provider's entry only", () => {
    expect(operationMeta(operations, "mcp.tool.search_posts")).toEqual({
      risk: "low",
      effects: ["read"],
    });
    expect(operationMeta(undefined, "mcp.tool.search_posts")).toBeUndefined();
  });
});
