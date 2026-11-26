import { refresh } from "next/cache.js";

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
