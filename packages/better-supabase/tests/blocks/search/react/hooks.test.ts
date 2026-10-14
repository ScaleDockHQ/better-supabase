import type * as ReactModule from "react";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import {
  type CommandSearchState,
  useCommandSearch,
} from "../../../../src/blocks/search/react/index.ts";
import {
  BetterSupabaseProvider,
  type ClientLike,
} from "../../../../src/react/hooks.ts";

/**
 * A synchronous hook runtime standing in for React's dispatcher: effects run
 * after each render, and state updates render again.
 */
const runtime = vi.hoisted(() => {
  interface Slot {
    value?: unknown;
    deps?: readonly unknown[] | undefined;
    cleanup?: (() => void) | undefined;
    setter?: (next: unknown) => void;
  }
  const state = {
    slots: [] as Slot[],
    index: 0,
    pending: [] as (() => void)[],
    provided: new Map<object, unknown>(),
    rendering: false,
    flushing: false,
    dirty: false,
    render: (() => undefined) as () => void,
  };
  const slot = (): Slot => {
    const index = state.index;
    state.index += 1;
    return (state.slots[index] ??= {});
  };
  const changed = (
    before: readonly unknown[] | undefined,
    after: readonly unknown[] | undefined,
  ): boolean =>
    before === undefined ||
    after === undefined ||
    before.length !== after.length ||
    before.some((value, index) => !Object.is(value, after[index]));
  const schedule = (): void => {
    if (state.rendering || state.flushing) state.dirty = true;
    else state.render();
  };
  return { state, slot, changed, schedule };
});

vi.mock("react", async (importOriginal) => {
  const actual = await importOriginal<typeof ReactModule>();
  const { state, slot, changed, schedule } = runtime;
  return {
    ...actual,
    createElement: (
      type: unknown,
      props: { value?: unknown } | null,
      ...children: unknown[]
    ) => {
      // A context object is its own provider in React 19.
      if (typeof type === "object" && type !== null && "Consumer" in type)
        state.provided.set(type, props?.value);
      return { type, props, children };
    },
    useContext: (context: object) => state.provided.get(context) ?? null,
    useState: (initial: unknown) => {
      const cell = slot();
      if (!cell.setter) {
        cell.value = typeof initial === "function" ? initial() : initial;
        cell.setter = (next) => {
          const value = typeof next === "function" ? next(cell.value) : next;
          if (Object.is(value, cell.value)) return;
          cell.value = value;
          schedule();
        };
      }
      return [cell.value, cell.setter];
    },
    useRef: (initial: unknown) => {
      const cell = slot();
      if (!("value" in cell)) cell.value = { current: initial };
      return cell.value;
    },
    useMemo: (factory: () => unknown, deps: readonly unknown[]) => {
      const cell = slot();
      if (changed(cell.deps, deps)) {
        cell.value = factory();
        cell.deps = deps;
      }
      return cell.value;
    },
    useCallback: (fn: unknown, deps: readonly unknown[]) => {
      const cell = slot();
      if (changed(cell.deps, deps)) {
        cell.value = fn;
        cell.deps = deps;
      }
      return cell.value;
    },
    useEffect: (
      effect: () => (() => void) | undefined,
      deps?: readonly unknown[],
    ) => {
      const cell = slot();
      if (!changed(cell.deps, deps)) return;
      cell.deps = deps;
      state.pending.push(() => {
        cell.cleanup?.();
        const cleanup = effect();
        cell.cleanup = typeof cleanup === "function" ? cleanup : undefined;
      });
    },
  };
});

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

const client = { supabase } as unknown as ClientLike;

function renderHook(hook: () => CommandSearchState): {
  readonly result: CommandSearchState;
  unmount: () => void;
} {
  const { state } = runtime;
  state.slots = [];
  state.provided = new Map();
  let current: CommandSearchState | undefined;
  state.render = () => {
    do {
      state.dirty = false;
      state.rendering = true;
      state.index = 0;
      try {
        BetterSupabaseProvider({ client });
        current = hook();
      } finally {
        state.rendering = false;
      }
      state.flushing = true;
      try {
        for (const effect of state.pending.splice(0)) effect();
      } finally {
        state.flushing = false;
      }
      // Effects set `dirty` through state updates, which control flow can't see.
    } while ((state as { dirty: boolean }).dirty);
  };
  state.render();
  return {
    get result(): CommandSearchState {
      return current!;
    },
    unmount() {
      for (const cell of state.slots) cell.cleanup?.();
      state.slots = [];
      state.render = () => undefined;
    },
  };
}

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
    if (fn === "search_recents") return [item("r1")];
    if (fn === "search_favorites") return [item("f1")];
    if (fn === "search") return [hit("note", "n1"), hit("deal", "d1")];
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
      if (fn === "search")
        throw Object.assign(new Error("boom"), { hint: "X" });
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
      if (fn === "search_recents") throw new Error("no recents");
      return [item("f1")];
    };
    const recents = renderHook(() => useCommandSearch());
    recents.result.setOpen(true);
    await settle();
    expect(recents.result.error?.message).toBe("no recents");
    expect(recents.result.favorites).toHaveLength(1);
    recents.unmount();

    rpc.handler = (fn) => {
      if (fn === "search_favorites") throw new Error("no favorites");
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
