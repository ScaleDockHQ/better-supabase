/**
 * A synchronous stand-in for React's dispatcher, for hooks built on
 * `useState`, `useRef`, `useMemo`, `useCallback`, `useEffect` and
 * `useSyncExternalStore`. No renderer is
 * installed: effects run after each render, and a state update renders again.
 * A test spreads `reactHooks` into its `vi.mock("react")` factory. This module
 * imports nothing from React, so the factory can load it.
 */

type Deps = readonly unknown[];

interface Slot {
  value?: unknown;
  deps?: Deps | undefined;
  cleanup?: (() => void) | undefined;
  setter?: (next: unknown) => void;
  subscribe?: unknown;
}

const state = {
  slots: [] as Slot[],
  index: 0,
  pending: [] as (() => void)[],
  provided: new Map<object, unknown>(),
  busy: false,
  dirty: false,
  render: (): void => undefined,
};

const slot = (): Slot => {
  const index = state.index;
  state.index += 1;

  return (state.slots[index] ??= {});
};

const changed = (before: Deps | undefined, after: Deps | undefined): boolean =>
  before === undefined ||
  after === undefined ||
  before.length !== after.length ||
  before.some((value, index) => !Object.is(value, after[index]));

const schedule = (): void => {
  if (state.busy) {
    state.dirty = true;
  } else {
    state.render();
  }
};

export interface ReactHooks {
  createElement(
    type: unknown,
    props: { readonly value?: unknown } | null,
    ...children: unknown[]
  ): unknown;
  useContext(context: object): unknown;
  useState(initial: unknown): [unknown, (next: unknown) => void];
  useMemo(factory: () => unknown, deps: Deps): unknown;
  useCallback(fn: unknown, deps: Deps): unknown;
  useEffect(effect: () => (() => void) | undefined, deps?: Deps): void;
  useRef(initial: unknown): { current: unknown };
  useSyncExternalStore(
    subscribe: (listener: () => void) => () => void,
    getSnapshot: () => unknown,
  ): unknown;
}

export const reactHooks: ReactHooks = {
  createElement(type, props, ...children) {
    // A context object is its own provider in React 19.
    if (typeof type === "object" && type !== null && "Consumer" in type) {
      state.provided.set(type, props?.value);
    }

    return { type, props, children };
  },
  useContext: (context) => state.provided.get(context) ?? null,
  useState(initial) {
    const cell = slot();

    const setter =
      cell.setter ??
      ((next: unknown) => {
        const value = typeof next === "function" ? next(cell.value) : next;

        if (Object.is(value, cell.value)) {
          return;
        }

        cell.value = value;
        schedule();
      });

    if (!cell.setter) {
      cell.value = typeof initial === "function" ? initial() : initial;
      cell.setter = setter;
    }

    return [cell.value, setter];
  },
  useMemo(factory, deps) {
    const cell = slot();

    if (changed(cell.deps, deps)) {
      cell.value = factory();
      cell.deps = deps;
    }

    return cell.value;
  },
  useCallback(fn, deps) {
    const cell = slot();

    if (changed(cell.deps, deps)) {
      cell.value = fn;
      cell.deps = deps;
    }

    return cell.value;
  },
  useEffect(effect, deps) {
    const cell = slot();

    if (!changed(cell.deps, deps)) {
      return;
    }

    cell.deps = deps;
    state.pending.push(() => {
      cell.cleanup?.();
      const cleanup = effect();
      cell.cleanup = typeof cleanup === "function" ? cleanup : undefined;
    });
  },
  useRef(initial) {
    const cell = slot();

    if (!("value" in cell)) {
      cell.value = { current: initial };
    }

    // SAFETY: the branch above stored a ref object in this slot.
    return cell.value as { current: unknown };
  },
  useSyncExternalStore(subscribe, getSnapshot) {
    const cell = slot();

    if (cell.subscribe !== subscribe) {
      cell.cleanup?.();
      cell.subscribe = subscribe;
      cell.cleanup = subscribe(() => {
        if (!Object.is(getSnapshot(), cell.value)) {
          schedule();
        }
      });
    }

    cell.value = getSnapshot();

    return cell.value;
  },
};

export interface RenderedHook<P, R> {
  readonly result: R;
  rerender(next: P): void;
  unmount(): void;
}

/**
 * Renders `hook` with `initial`; `result` is the latest render's value.
 * `before` runs first in every render, for a provider the hook reads.
 */
export function renderHook<P, R>(
  hook: (props: P) => R,
  initial: P,
  before?: () => void,
): RenderedHook<P, R> {
  state.slots = [];
  state.provided = new Map();
  let props = initial;
  let result: R | undefined;
  // State updates inside effects set `dirty`, which control flow can't see.
  const dirty = (): boolean => state.dirty;
  state.render = () => {
    do {
      state.dirty = false;
      state.busy = true;

      try {
        state.index = 0;
        before?.();
        result = hook(props);

        for (const effect of state.pending.splice(0)) {
          effect();
        }
      } finally {
        state.busy = false;
      }
    } while (dirty());
  };

  state.render();

  return {
    get result(): R {
      // SAFETY: the first render above assigned it.
      return result as R;
    },
    rerender(next: P): void {
      props = next;
      state.render();
    },
    unmount(): void {
      for (const cell of state.slots) {
        cell.cleanup?.();
      }

      state.slots = [];
      state.render = () => undefined;
    },
  };
}
