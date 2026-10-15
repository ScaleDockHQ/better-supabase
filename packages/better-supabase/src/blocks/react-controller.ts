import {
  type DependencyList,
  useMemo,
  useRef,
  useState,
  useSyncExternalStore,
} from "react";

import type { Controller } from "./controller.ts";

/**
 * A controller's state and actions, rendered again when the state changes.
 * The controller is made again when `deps` change; its work starts with the
 * first subscription and stops with the last, so StrictMode's second mount
 * and an unmount need no cleanup here.
 */
export function useController<S, A>(
  create: () => Controller<S, A>,
  deps: DependencyList,
): { readonly controller: Controller<S, A>; readonly view: S & A } {
  const [held, setHeld] = useState(() => ({ deps, controller: create() }));
  let current = held;
  if (changed(held.deps, deps)) {
    // A new controller for new inputs, kept from this render on, the way
    // React stores information from previous renders.
    current = { deps, controller: create() };
    setHeld(current);
  }
  const { controller } = current;
  const snapshot = useSyncExternalStore(
    controller.subscribe,
    controller.getSnapshot,
    controller.getSnapshot,
  );
  const view = useMemo(
    () => ({ ...snapshot, ...controller.actions }),
    [snapshot, controller],
  );
  return { controller, view };
}

const changed = (before: DependencyList, after: DependencyList): boolean =>
  before.length !== after.length ||
  before.some((value, index) => !Object.is(value, after[index]));

/** A ref that always holds the latest value, for callbacks a controller calls later. */
export function useLatest<T>(value: T): { readonly current: T } {
  const latest = useRef(value);
  // oxlint-disable-next-line react/refs -- latest-ref pattern; the react peer range predates useEffectEvent.
  latest.current = value;
  return latest;
}
