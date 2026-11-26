import { refresh } from "next/cache.js";

import type { DbError } from "../core/errors.ts";

import { tableTags } from "../server/cache-tags.ts";

/** What a successful `bsb.action` changes, from its options. */
export interface ActionEffects {
  readonly invalidates?: readonly string[] | undefined;
  readonly tags?:
    | ((scope: {
        readonly tenant: string | undefined;
        readonly input: never;
        readonly data: unknown;
      }) => readonly string[])
    | undefined;
  readonly refresh?: boolean | undefined;
}

/**
 * Expires the tags a successful action names (`invalidates` tables and the
 * `tags` it computes from the tenant, input and data), then refreshes the
 * client router when `refresh` is set, so the page shows the write.
 */
export function applyActionEffects(
  effects: ActionEffects,
  scope: {
    readonly tenant: string | undefined;
    readonly input: unknown;
    readonly data: unknown;
  },
  expire: (tags: readonly string[]) => void,
): void {
  if (effects.invalidates) {
    expire(
      effects.invalidates.flatMap((table) => tableTags(table, { tenant: "*" })),
    );
  }

  if (effects.tags) {
    // SAFETY: `input` is the validated input the action's own `tags` is typed to take.
    expire(effects.tags({ ...scope, input: scope.input as never }));
  }

  if (effects.refresh) {
    refresh();
  }
}

/**
 * An outcome after the action's own `result` and the app's `envelope`, which
 * adds fields to it.
 */
export async function finishOutcome<O extends object>(
  outcome: O,
  own: ((outcome: never) => unknown) | undefined,
  envelope: ((outcome: never) => unknown) | undefined,
): Promise<O> {
  // SAFETY: `result` keeps the outcome's shape, as ActionOptions.result documents.
  const mapped = ((await own?.(outcome as never)) ?? outcome) as O;

  // SAFETY: the envelope takes the outcome `mapped` is.
  const extra = await envelope?.(mapped as never);

  return extra === undefined ? mapped : { ...mapped, ...extra };
}

/**
 * What `NextActions.from` made of a handler's value, as the result shape
 * `settle` reads; the value itself when `from` does not know it.
 */
export function adoptValue(
  from: ((value: unknown) => object | undefined) | undefined,
  value: unknown,
): unknown {
  const adopted = from?.(value);

  return adopted === undefined
    ? value
    : { error: null, data: null, ...adopted };
}

/** The first error a guard returns, in order; later guards do not run. */
export async function firstRefusal<A extends readonly unknown[]>(
  guards: readonly (
    | ((...args: A) => DbError | undefined | Promise<DbError | undefined>)
    | undefined
  )[],
  ...args: A
): Promise<DbError | undefined> {
  for (const run of guards) {
    const refused = await run?.(...args);

    if (refused) {
      return refused;
    }
  }

  return undefined;
}
