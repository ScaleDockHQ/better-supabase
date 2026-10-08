import type * as ReactModule from "react";

import { beforeEach, describe, expect, it, vi } from "vitest";

import { useSessionChange } from "../../src/next/client/index.ts";

const mocks = vi.hoisted(() => ({
  push: vi.fn<(href: string) => void>(),
  refresh: vi.fn<() => void>(),
}));

vi.mock("next/navigation.js", () => ({
  useRouter: () => ({ push: mocks.push, refresh: mocks.refresh }),
}));

vi.mock("react", async (original) => ({
  ...(await original<typeof ReactModule>()),
  useCallback: <T>(fn: T): T => fn,
}));

describe("useSessionChange", () => {
  beforeEach(() => {
    mocks.push.mockClear();
    mocks.refresh.mockClear();
  });

  it("expires the cache, navigates, then refreshes", async () => {
    const changed = vi.fn(async () => undefined);
    const go = useSessionChange(changed);
    await go("/login");
    expect(changed).toHaveBeenCalledOnce();
    expect(mocks.push).toHaveBeenCalledWith("/login");
    expect(mocks.refresh).toHaveBeenCalledOnce();
  });

  it("refreshes without navigating when no href is passed", async () => {
    const go = useSessionChange(async () => undefined);
    await go();
    expect(mocks.push).not.toHaveBeenCalled();
    expect(mocks.refresh).toHaveBeenCalledOnce();
  });

  it("uses a passed router for locale-aware push", async () => {
    const push = vi.fn<(href: string) => void>();
    const refresh = vi.fn<() => void>();
    const go = useSessionChange(async () => undefined, { push, refresh });
    await go("/nl");
    expect(push).toHaveBeenCalledWith("/nl");
    expect(refresh).toHaveBeenCalledOnce();
    expect(mocks.push).not.toHaveBeenCalled();
  });

  it("refreshes the token before the change when asked", async () => {
    const order: string[] = [];
    const refreshSession = vi.fn(async () => {
      order.push("token");
      return { error: null };
    });
    const go = useSessionChange(
      async () => {
        order.push("changed");
      },
      undefined,
      { refreshToken: { auth: { refreshSession } } },
    );
    await go("/en");
    expect(order).toEqual(["token", "changed"]);
    expect(mocks.refresh).toHaveBeenCalledOnce();

    const failing = useSessionChange(async () => undefined, undefined, {
      refreshToken: {
        auth: { refreshSession: async () => ({ error: new Error("expired") }) },
      },
    });
    await expect(failing()).rejects.toThrow("expired");
  });
});
