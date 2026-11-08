import { describe, expect, it, vi } from "vitest";

import { awaitStage } from "../../src/next/entry.ts";

vi.mock(import("next/cache.js"), () => ({
  cacheLife: vi.fn(),
  cacheTag: vi.fn(),
  updateTag: vi.fn(),
  revalidateTag: vi.fn(),
  io: () => Promise.resolve(),
  // SAFETY: a Next.js build without Partial Prefetching has no gates.
  navigation: undefined as never,
  prefetch: undefined as never,
}));

describe("awaitStage without the gates", () => {
  it("skips the stage and warns once", async () => {
    const warn = vi.fn<(message: string) => void>();

    await awaitStage("navigation", warn);
    await awaitStage("prefetch", warn);
    await awaitStage(undefined, warn);

    expect(warn).toHaveBeenCalledOnce();
    expect(warn.mock.calls[0]?.[0]).toContain("does nothing");
  });

  it("stays quiet outside development", async () => {
    await expect(awaitStage("navigation")).resolves.toBeUndefined();
  });
});
