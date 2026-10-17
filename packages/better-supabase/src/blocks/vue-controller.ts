import {
  getCurrentScope,
  onScopeDispose,
  type ShallowRef,
  shallowRef,
} from "vue";

import type { Controller } from "./controller.ts";

import { onClient, useContext } from "../vue/context.ts";
import { blockEnv, type BlockOptions, withEnv } from "./block-env.ts";

/** A block controller in a Vue component: `state` follows the controller. */
export interface VueController<S, A> {
  readonly state: Readonly<ShallowRef<S>>;
  readonly actions: A;
  readonly controller: Controller<S, A>;
}

/**
 * Makes a controller once and keeps `state` current. Its work starts on
 * mount (at once in an effect scope, never during server rendering), and the
 * controller is disposed with the component or scope.
 */
export function useBlockController<O, S, A>(
  create: (options: O) => Controller<S, A>,
  options: BlockOptions<O>,
  usesEnv = true,
): VueController<S, A> {
  const controller = create(
    withEnv(options, usesEnv ? () => blockEnv(useContext().client) : undefined),
  );

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
