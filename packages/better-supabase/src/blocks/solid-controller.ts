import { type Accessor, from, onCleanup, onMount } from "solid-js";

import type { Controller } from "./controller.ts";

import { useContext } from "../solid/context.ts";
import { blockEnv, type BlockOptions, withEnv } from "./block-env.ts";

/** A block controller in a Solid component: `state` follows the controller. */
export interface SolidController<S, A> {
  readonly state: Accessor<S>;
  readonly actions: A;
  readonly controller: Controller<S, A>;
}

/**
 * Makes a controller once and reads it through `from`. Its work starts on
 * mount (never during server rendering), and the controller is disposed
 * with the owner.
 */
export function useBlockController<O, S, A>(
  create: (options: O) => Controller<S, A>,
  options: BlockOptions<O>,
  usesEnv = true,
): SolidController<S, A> {
  const controller = create(
    withEnv(options, usesEnv ? () => blockEnv(useContext().client) : undefined),
  );
  // The object form, because a setter treats a function value as an
  // updater; the server build of `from` ignores the initial value.
  const state = from<S>(
    {
      subscribe: (next) => {
        next(controller.getSnapshot());
        let stop: (() => void) | undefined;
        onMount(() => {
          stop = controller.subscribe(() => {
            next(controller.getSnapshot());
          });
          next(controller.getSnapshot());
        });
        return () => stop?.();
      },
    },
    controller.getSnapshot(),
  );
  onCleanup(() => {
    controller.dispose();
  });
  return { state, actions: controller.actions, controller };
}
