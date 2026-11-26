import { describe, expect, it, vi } from "vitest";

import { applyActionEffects } from "../../src/next/action-effects.ts";

const mocks = vi.hoisted(() => ({ refresh: vi.fn<() => void>() }));

vi.mock(import("next/cache.js"), () => ({ refresh: mocks.refresh }));

describe("applyActionEffects", () => {
  it("expires the table tags, the computed tags, then refreshes", () => {
    const expire = vi.fn<(tags: readonly string[]) => void>();
    mocks.refresh.mockClear();

    applyActionEffects(
      {
        invalidates: ["customers"],
        tags: ({ tenant, data }) => [`agenda:${tenant}:${String(data)}`],
        refresh: true,
      },
      { tenant: "org-1", input: {}, data: "a1" },
      expire,
    );

    expect(expire.mock.calls[0]?.[0]).toContain("bsb:customers@*");
    expect(expire).toHaveBeenNthCalledWith(2, ["agenda:org-1:a1"]);
    expect(mocks.refresh).toHaveBeenCalledOnce();
  });

  it("does nothing without options", () => {
    const expire = vi.fn<(tags: readonly string[]) => void>();
    mocks.refresh.mockClear();
    applyActionEffects({}, { tenant: undefined, input: {}, data: 1 }, expire);

    expect(expire).not.toHaveBeenCalled();
    expect(mocks.refresh).not.toHaveBeenCalled();
  });
});
