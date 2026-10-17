import type * as ReactModule from "react";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { useCommandSearch } from "../../../../src/blocks/search/react/index.ts";
import { webKeyboard } from "../../../../src/client/web-ports.ts";
import {
  BetterSupabaseProvider,
  type ClientLike,
} from "../../../../src/react/hooks.ts";
import { renderHook as render } from "../../../fixtures/hook-runtime.ts";

vi.mock("react", async (importOriginal) => ({
  ...(await importOriginal<typeof ReactModule>()),
  ...(await import("../../../fixtures/hook-runtime.ts")).reactHooks,
}));

const rpc = {
  handler: (_fn: string, _args: Record<string, unknown>): unknown => null,
  calls: [] as { fn: string; args: Record<string, unknown> }[],
};

const supabase = {
  schema: () => ({
    rpc: (fn: string, args: Record<string, unknown>) => {
      rpc.calls.push({ fn, args });
      try {
        return Promise.resolve({ data: rpc.handler(fn, args), error: null });
      } catch (cause) {
        return Promise.resolve({ data: null, error: cause });
      }
    },
  }),
};

// SAFETY: the hook reads only `supabase` and the keyboard port from the client.
const client = {
  supabase,
  ports: { keyboard: webKeyboard() },
} as unknown as ClientLike;

const renderHook = <R>(hook: () => R) =>
  render(hook, undefined, () => {
    BetterSupabaseProvider({ client });
  });

const hit = (subjectType: string, subjectId: string) => ({
  organizationId: "org",
  subjectType,
  subjectId,
  title: subjectId,
  url: null,
  snippet: null,
  score: 1,
});

const item = (subjectId: string) => ({
  subjectType: "note",
  subjectId,
  title: subjectId,
  url: null,
  openedAt: null,
  starredAt: null,
});

let keydown: ((event: KeyboardEvent) => void) | undefined;
const keyWindow = {
  addEventListener: vi.fn(
    (_type: string, listener: (event: KeyboardEvent) => void) => {
      keydown = listener;
    },
  ),
  removeEventListener: vi.fn(() => {
    keydown = undefined;
  }),
};

const press = (init: Partial<KeyboardEvent>) => {
  const preventDefault = vi.fn();
  keydown?.({
    key: "k",
    metaKey: false,
    ctrlKey: false,
    altKey: false,
    shiftKey: false,
    preventDefault,
    ...init,
  } as KeyboardEvent);
  return preventDefault;
};

const settle = () => vi.advanceTimersByTimeAsync(200);

beforeEach(() => {
  vi.useFakeTimers();
  vi.stubGlobal("window", keyWindow);
  rpc.calls = [];
  rpc.handler = (fn) => {
    if (fn === "search_recents") {
      return [item("r1")];
    }
    if (fn === "search_favorites") {
      return [item("f1")];
    }
    if (fn === "search") {
      return [hit("note", "n1"), hit("deal", "d1")];
    }
    return true;
  };
});

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
  keydown = undefined;
});

describe("useCommandSearch", () => {
  it("toggles on Cmd+K and Ctrl+K and shows favorites and recents", async () => {
    const view = renderHook(() =>
      useCommandSearch({ types: ["note"], listLimit: 3 }),
    );
    expect(view.result.open).toBe(false);
    expect(press({ key: "j", metaKey: true })).not.toHaveBeenCalled();
    expect(press({ metaKey: true, shiftKey: true })).not.toHaveBeenCalled();
    expect(press({ metaKey: true })).toHaveBeenCalled();
    expect(view.result.open).toBe(true);
    await settle();
    expect(view.result.groups.map((group) => group.key)).toEqual([
      "favorites",
      "recents",
    ]);
    expect(rpc.calls.map((call) => call.args)).toEqual([
      { max_results: 3, types: ["note"] },
      { max_results: 3, types: ["note"] },
    ]);
    press({ key: "K", ctrlKey: true });
    expect(view.result.open).toBe(false);
    view.unmount();
    expect(keyWindow.removeEventListener).toHaveBeenCalled();
  });

  it("debounces the query and groups the hits", async () => {
    const view = renderHook(() =>
      useCommandSearch({ organizationId: "org", limit: 5 }),
    );
    view.result.setOpen(true);
    view.result.setQuery("  rev ");
    expect(view.result.loading).toBe(true);
    expect(rpc.calls.some((call) => call.fn === "search")).toBe(false);
    await settle();
    expect(view.result.loading).toBe(false);
    expect(view.result.results).toHaveLength(2);
    expect(view.result.groups.map((group) => group.key)).toEqual([
      "note",
      "deal",
    ]);
    expect(rpc.calls.find((call) => call.fn === "search")?.args).toEqual({
      q: "rev",
      types: null,
      tenant: "org",
      max_results: 5,
    });
    view.result.setQuery("");
    expect(view.result.results).toEqual([]);
    view.unmount();
  });

  it("drops a response that a newer query overtook", async () => {
    const view = renderHook(() =>
      useCommandSearch({ shortcut: false, debounceMs: 0 }),
    );
    expect(keydown).toBeUndefined();
    rpc.handler = (fn, args) =>
      fn === "search" ? [hit("note", String(args["q"]))] : [];
    view.result.setOpen(true);
    view.result.setQuery("first");
    await vi.advanceTimersByTimeAsync(0);
    view.result.setQuery("second");
    await settle();
    expect(view.result.results.map((found) => found.subjectId)).toEqual([
      "second",
    ]);
    expect(view.result.groups).toHaveLength(1);
    view.unmount();
  });

  it("keeps the last hits and reports a failed query", async () => {
    const view = renderHook(() => useCommandSearch());
    view.result.setOpen(true);
    view.result.setQuery("rev");
    await settle();
    rpc.handler = (fn) => {
      if (fn === "search") {
        throw Object.assign(new Error("boom"), { hint: "X" });
      }
      return [];
    };
    view.result.setQuery("revenue");
    await settle();
    expect(view.result.error?.message).toBe("boom");
    expect(view.result.loading).toBe(false);
    expect(view.result.results).toHaveLength(2);
    view.unmount();
  });

  it("reports a failed recents or favorites list", async () => {
    rpc.handler = (fn) => {
      if (fn === "search_recents") {
        throw new Error("no recents");
      }
      return [item("f1")];
    };
    const recents = renderHook(() => useCommandSearch());
    recents.result.setOpen(true);
    await settle();
    expect(recents.result.error?.message).toBe("no recents");
    expect(recents.result.favorites).toHaveLength(1);
    recents.unmount();

    rpc.handler = (fn) => {
      if (fn === "search_favorites") {
        throw new Error("no favorites");
      }
      return [item("r1")];
    };
    const favorites = renderHook(() => useCommandSearch());
    favorites.result.setOpen(true);
    await settle();
    expect(favorites.result.error?.message).toBe("no favorites");
    expect(favorites.result.recents).toHaveLength(1);
    favorites.unmount();
  });

  it("records a selection and stars items", async () => {
    const view = renderHook(() => useCommandSearch());
    view.result.setOpen(true);
    view.result.setQuery("rev");
    await settle();
    await view.result.select({ ...item("n1"), score: 1 } as never);
    expect(view.result.open).toBe(false);
    expect(view.result.query).toBe("");
    await view.result.star(item("n1"));
    await view.result.star(item("n1"), false);
    expect(
      rpc.calls
        .filter(
          (call) => call.fn === "search_touch" || call.fn === "search_star",
        )
        .map((call) => call.args),
    ).toEqual([
      { subject_type: "note", subject_id: "n1" },
      { subject_type: "note", subject_id: "n1", starred: true },
      { subject_type: "note", subject_id: "n1", starred: false },
    ]);

    rpc.handler = () => {
      throw new Error("denied");
    };
    await view.result.select(item("n1"));
    expect(view.result.error?.message).toBe("denied");
    await view.result.star(item("n2"));
    expect(view.result.error?.message).toBe("denied");
    view.unmount();
  });
});
