import type { Readable } from "svelte/store";

import { onDestroy, onMount } from "svelte";
import { readable } from "svelte/store";

import type { Controller } from "./controller.ts";

/**
 * A block controller in a Svelte component: a readable store of its state, with
 * its actions.
 */
export interface SvelteController<S, A> extends Readable<S> {
  readonly actions: A;
  readonly controller: Controller<S, A>;
}

/**
 * Wraps a controller made during component setup. The store follows it from
 * mount (never during server rendering) while it has subscribers, and the
 * controller is disposed with the component.
 */
export function bindSvelteController<S, A>(
  controller: Controller<S, A>,
): SvelteController<S, A> {
  let mounted = false;
  let pending: (() => void) | undefined;

  const store = readable(controller.getSnapshot(), (set) => {
    let stop: (() => void) | undefined;

    const start = (): void => {
      stop = controller.subscribe(() => {
        set(controller.getSnapshot());
      });
      set(controller.getSnapshot());
    };

    if (mounted) {
      start();
    } else {
      pending = start;
    }

    return () => {
      pending = undefined;
      stop?.();
    };
  });

  onMount(() => {
    mounted = true;
    pending?.();
    pending = undefined;
  });
  onDestroy(() => {
    controller.dispose();
  });

  return {
    subscribe: store.subscribe,
    actions: controller.actions,
    controller,
  };
}
