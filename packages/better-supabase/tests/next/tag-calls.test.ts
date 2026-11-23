import { describe, expect, it, vi } from "vitest";

const next = vi.hoisted(() => ({
  updateTag: vi.fn<(tag: string) => undefined>(),
  revalidateTag: vi.fn<(tag: string, profile: unknown) => undefined>(),
}));

vi.mock(import("next/cache.js"), () => next);

const { invalidateAll, onTagCalls } = await import("../../src/next/cache.ts");

describe("invalidateAll", () => {
  it("reports one call per tag it expired", () => {
    const calls: number[] = [];
    const off = onTagCalls((count) => calls.push(count));

    invalidateAll(["a", "b", "c"]);
    off();
    invalidateAll(["d"]);

    expect(next.updateTag).toHaveBeenCalledTimes(4);
    expect(calls).toEqual([3]);
  });

  it("counts the revalidateTag calls outside a Server Action", () => {
    const calls: number[] = [];
    const off = onTagCalls((count) => calls.push(count));

    next.updateTag.mockImplementationOnce(() => {
      throw new Error("not in an action");
    });
    invalidateAll(["a", "b"]);
    off();

    expect(next.revalidateTag).toHaveBeenCalledTimes(2);
    expect(calls).toEqual([2]);
  });

  it("reports nothing outside a request", () => {
    const calls: number[] = [];
    const off = onTagCalls((count) => calls.push(count));

    const fail = (): never => {
      throw new Error("outside a request");
    };

    next.updateTag.mockImplementationOnce(fail);
    next.revalidateTag.mockImplementationOnce(fail);
    invalidateAll(["a"]);
    off();

    expect(calls).toEqual([]);
  });

  it("keeps invalidating when a listener throws", () => {
    const off = onTagCalls(() => {
      throw new Error("listener");
    });

    expect(() => {
      invalidateAll(["a"]);
    }).not.toThrow();
    off();
  });
});
