import { describe, expect, it, vi } from "vitest";

import { warnIfNested } from "../../src/next/entry.ts";

const frame =
  "at cache (node_modules/next/dist/server/use-cache/use-cache-wrapper.js:1:1)";

describe("warnIfNested", () => {
  it("stays quiet for one cache wrapper frame", () => {
    const warn = vi.fn<(message: string) => void>();

    warnIfNested(warn, `Error\n${frame}\nat page`);

    expect(warn).not.toHaveBeenCalled();
  });

  it("warns once when the stack holds two", () => {
    const warn = vi.fn<(message: string) => void>();

    warnIfNested(warn, `Error\n${frame}\nat outer\n${frame}`);
    warnIfNested(warn, `Error\n${frame}\nat outer\n${frame}`);

    expect(warn).toHaveBeenCalledOnce();
    expect(warn.mock.calls[0]?.[0]).toContain("sessionHandle");
  });
});
