import { getContext } from "svelte";

import type { ClientLike } from "../bindings/client.ts";
import type { BlockOptions } from "./block-env.ts";
import type { Controller } from "./controller.ts";
import type { SvelteController } from "./svelte-bind.ts";

import { CLIENT } from "../svelte/context.ts";
import { blockEnv, withEnv } from "./block-env.ts";
import { bindSvelteController } from "./svelte-bind.ts";

export type { SvelteController } from "./svelte-bind.ts";

function contextClient(): ClientLike {
  const bound = getContext<{ readonly client: ClientLike } | undefined>(CLIENT);

  if (!bound) {
    throw new Error(
      "better-supabase: call setBetterSupabase(bsb) in a parent component",
    );
  }

  return bound.client;
}

/**
 * Makes a controller once, during component setup. The store follows it from
 * mount (never during server rendering) while it has subscribers, and the
 * controller is disposed with the component.
 */
export function useBlockController<O, S, A>(
  create: (options: O) => Controller<S, A>,
  options: BlockOptions<O>,
  usesEnv = true,
): SvelteController<S, A> {
  return bindSvelteController(
    create(
      withEnv(options, usesEnv ? () => blockEnv(contextClient()) : undefined),
    ),
  );
}
