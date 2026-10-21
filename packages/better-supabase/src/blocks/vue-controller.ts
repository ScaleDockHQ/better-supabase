import type { BlockOptions } from "./block-env.ts";
import type { Controller } from "./controller.ts";
import type { VueController } from "./vue-bind.ts";

import { useContext } from "../vue/context.ts";
import { blockEnv, withEnv } from "./block-env.ts";
import { bindVueController } from "./vue-bind.ts";

export type { VueController } from "./vue-bind.ts";

/**
 * Makes a controller once and keeps `state` current. Its work starts on mount
 * (at once in an effect scope, never during server rendering), and the
 * controller is disposed with the component or scope.
 */
export function useBlockController<O, S, A>(
  create: (options: O) => Controller<S, A>,
  options: BlockOptions<O>,
  usesEnv = true,
): VueController<S, A> {
  return bindVueController(
    create(
      withEnv(
        options,
        usesEnv ? () => blockEnv(useContext().client) : undefined,
      ),
    ),
  );
}
