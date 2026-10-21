import type { ShallowRef } from "vue";

import { getCurrentScope, onScopeDispose, shallowRef } from "vue";

import type { Controller } from "./controller.ts";

import { onClient } from "../vue/context.ts";

/** A block controller in a Vue component: `state` follows the controller. */
export interface VueController<S, A> {
  readonly state: Readonly<ShallowRef<S>>;
  readonly actions: A;
  readonly controller: Controller<S, A>;
}

/**
 * Keeps `state` current from mount (at once in an effect scope, never during
 * server rendering), and disposes the controller with the component or scope.
 */
export function bindVueController<S, A>(
  controller: Controller<S, A>,
): VueController<S, A> {
  const state = shallowRef(controller.getSnapshot());
  let unsubscribe: (() => void) | undefined;
  onClient(() => {
    const sync = (): void => {
      state.value = controller.getSnapshot();
    };

    unsubscribe = controller.subscribe(sync);
    sync();
  });

  if (getCurrentScope()) {
    onScopeDispose(() => {
      unsubscribe?.();
      controller.dispose();
    });
  }

  return { state, actions: controller.actions, controller };
}
