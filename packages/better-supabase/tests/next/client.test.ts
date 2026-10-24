import type * as ReactModule from "react";

import { beforeEach, describe, expect, it, vi } from "vitest";

import {
  useSessionChange,
  useSessionWatch,
} from "../../src/next/client/index.ts";

const mocks = vi.hoisted(() => ({
  push: vi.fn<(href: string) => void>(),
  refresh: vi.fn<() => void>(),
}));

vi.mock("next/navigation.js", () => ({
  useRouter: () => ({ push: mocks.push, refresh: mocks.refresh }),
}));

const effects = vi.hoisted(() => ({
  cleanups: [] as (() => void)[],
  states: [] as unknown[],
}));

vi.mock("react", async (original) => ({
  ...(await original<typeof ReactModule>()),
  useCallback: <T>(fn: T): T => fn,
  useRef: <T>(current: T) => ({ current }),
  useState: <T>(initial: T) => [
    initial,
    (next: T) => {
      effects.states.push(next);
    },
  ],
  useEffect: (effect: () => (() => void) | undefined) => {
    const cleanup = effect();

    if (cleanup) {
      effects.cleanups.push(cleanup);
    }
  },
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

describe("useSessionWatch", () => {
  const active = (fingerprint: string) => ({
    status: "active",
    userId: "u1",
    fingerprint,
    expiresAt: null,
    support: null,
  });

  const flush = () =>
    new Promise((resolve) => {
      setTimeout(resolve, 0);
    });

  beforeEach(() => {
    mocks.refresh.mockClear();
    effects.cleanups.length = 0;
    effects.states.length = 0;
  });

  it("refreshes the router when the claims change and reports each answer", async () => {
    const fetch = vi.fn(async () => Response.json(active("f2")));

    useSessionWatch({
      fetch,
      fingerprint: "f1",
      intervalMs: 0,
      channel: false,
    });
    await flush();

    expect(mocks.refresh).toHaveBeenCalledOnce();
    expect(effects.states).toEqual([active("f2")]);

    for (const cleanup of effects.cleanups) {
      cleanup();
    }
  });

  it("hands changes to onChange and stays off when disabled", async () => {
    const onChange = vi.fn();

    const fetch = vi.fn(async () =>
      Response.json({ ...active("x"), status: "ended", fingerprint: null }),
    );

    useSessionWatch({
      fetch,
      onChange,
      fingerprint: "f1",
      intervalMs: 0,
      channel: false,
    });
    await flush();

    expect(onChange).toHaveBeenCalledWith(
      expect.objectContaining({ reason: "ended", source: "check" }),
    );
    expect(mocks.refresh).not.toHaveBeenCalled();

    useSessionWatch({ fetch, enabled: false });
    expect(fetch).toHaveBeenCalledOnce();

    for (const cleanup of effects.cleanups) {
      cleanup();
    }
  });
});
