import { afterEach, describe, expect, it, vi } from "vitest";

import { refreshOnVisible } from "../../src/client/visible-refresh.ts";

interface FakeDocument {
  visibilityState: string;
  addEventListener(type: "visibilitychange", listener: () => void): void;
  removeEventListener(type: "visibilitychange", listener: () => void): void;
}

afterEach(() => {
  Reflect.deleteProperty(globalThis, "document");
});

function install(doc: FakeDocument): Map<string, () => void> {
  const listeners = new Map<string, () => void>();

  doc.addEventListener = (_type, listener) => {
    listeners.set("visibilitychange", listener);
  };

  doc.removeEventListener = (_type, listener) => {
    if (listeners.get("visibilitychange") === listener) {
      listeners.delete("visibilitychange");
    }
  };

  Object.defineProperty(globalThis, "document", {
    configurable: true,
    value: doc,
  });

  return listeners;
}

describe("refreshOnVisible", () => {
  it("does nothing when the page has no document", () => {
    const refresh = vi.fn(async () => undefined);

    const stop = refreshOnVisible({
      auth: {
        getSession: async () => ({ data: { session: null } }),
        refreshSession: refresh,
      },
    });

    stop();
    expect(refresh).not.toHaveBeenCalled();
  });

  it("ignores a document that cannot listen", () => {
    Object.defineProperty(globalThis, "document", {
      configurable: true,
      value: { visibilityState: "visible" },
    });

    const refresh = vi.fn(async () => undefined);

    const stop = refreshOnVisible({
      auth: {
        getSession: async () => ({ data: { session: null } }),
        refreshSession: refresh,
      },
    });

    stop();
    expect(refresh).not.toHaveBeenCalled();
  });

  it("refreshes a visible tab whose token is inside the leeway", async () => {
    const doc: FakeDocument = {
      visibilityState: "hidden",
      addEventListener: () => undefined,
      removeEventListener: () => undefined,
    };

    const listeners = install(doc);
    const now = Math.floor(Date.now() / 1000);
    const refresh = vi.fn(async () => undefined);

    const getSession = vi
      .fn<
        () => Promise<{ data: { session: { expires_at?: number } | null } }>
      >()
      .mockResolvedValueOnce({ data: { session: { expires_at: now + 10 } } })
      .mockResolvedValueOnce({ data: { session: { expires_at: now + 3600 } } })
      .mockResolvedValueOnce({ data: { session: null } })
      .mockResolvedValueOnce({ data: { session: {} } });

    const stop = refreshOnVisible(
      { auth: { getSession, refreshSession: refresh } },
      60,
    );

    listeners.get("visibilitychange")?.();
    doc.visibilityState = "visible";
    listeners.get("visibilitychange")?.();
    listeners.get("visibilitychange")?.();
    listeners.get("visibilitychange")?.();
    listeners.get("visibilitychange")?.();
    await Promise.resolve();
    await Promise.resolve();

    expect(refresh).toHaveBeenCalledOnce();
    stop();
    expect(listeners.size).toBe(0);
  });
});
