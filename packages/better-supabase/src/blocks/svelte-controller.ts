import { getContext, onDestroy, onMount } from "svelte";
import { readable, type Readable } from "svelte/store";

import type { ClientLike } from "../bindings/client.ts";
import type { Controller } from "./controller.ts";

import { CLIENT } from "../svelte/context.ts";
import { blockEnv, type BlockOptions, withEnv } from "./block-env.ts";

/** A block controller in a Svelte component: a readable store of its state, with its actions. */
export interface SvelteController<S, A> extends Readable<S> {
  readonly actions: A;
  readonly controller: Controller<S, A>;
}

function contextClient(): ClientLike {
  const bound = getContext<{ readonly client: ClientLike } | undefined>(CLIENT);

  if (!bound) {
    throw new Error(
      "better-supabase: call setBetterSupabase(bs) in a parent component",
    );
  }

  return bound.client;
}

/**
 * Makes a controller once, during component setup. The store follows it
 * from mount (never during server rendering) while it has subscribers, and
 * the controller is disposed with the component.
 */
export function useBlockController<O, S, A>(
  create: (options: O) => Controller<S, A>,
  options: BlockOptions<O>,
  usesEnv = true,
): SvelteController<S, A> {
  const controller = create(
    withEnv(options, usesEnv ? () => blockEnv(contextClient()) : undefined),
  );

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
