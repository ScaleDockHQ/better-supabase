import type { BlockOptions } from "./block-env.ts";
import type { Controller } from "./controller.ts";
import type { SolidController } from "./solid-bind.ts";

import { useContext } from "../solid/context.ts";
import { blockEnv, withEnv } from "./block-env.ts";
import { bindSolidController } from "./solid-bind.ts";

export type { SolidController } from "./solid-bind.ts";

/**
 * Makes a controller once and reads it through `from`. Its work starts on mount
 * (never during server rendering), and the controller is disposed with the
 * owner.
 */
export function useBlockController<O, S, A>(
  create: (options: O) => Controller<S, A>,
  options: BlockOptions<O>,
  usesEnv = true,
): SolidController<S, A> {
  return bindSolidController(
    create(
      withEnv(
        options,
        usesEnv ? () => blockEnv(useContext().client) : undefined,
      ),
    ),
  );
}
