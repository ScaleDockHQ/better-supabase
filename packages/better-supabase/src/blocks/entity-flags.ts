import type { BlockMethodHooks } from "../core/block-hooks.ts";
import type { DbError } from "../core/errors.ts";
import type { BlockEntities } from "./entity-surface.ts";

import { dbError } from "../core/errors.ts";

/**
 * Whether the feature flag `key` is on. Takes the flags block's evaluation, an
 * OpenFeature client or any lookup the app has; a throw counts as off.
 */
export type EntityFlagCheck = (key: string) => boolean | Promise<boolean>;

type AnyHooks = BlockMethodHooks<unknown[], unknown>;

/**
 * The hooks that apply the `flag` an entity declares (ADR 0922), by method
 * name: each method in the entity's `methods` returns `not_found` while its
 * flag is off. A method two entities list needs both flags on.
 */
export function entityFlagHooks(
  entities: BlockEntities,
  isEnabled: EntityFlagCheck,
): Readonly<Record<string, AnyHooks>> {
  const flags = new Map<string, Map<string, string>>();

  for (const [entity, surface] of Object.entries(entities)) {
    if (surface.flag === undefined) {
      continue;
    }

    for (const method of surface.methods ?? []) {
      const byFlag = flags.get(method) ?? new Map<string, string>();

      byFlag.set(surface.flag, entity);
      flags.set(method, byFlag);
    }
  }

  const hooks: Record<string, AnyHooks> = {};

  for (const [method, byFlag] of flags) {
    hooks[method] = {
      before: async (): Promise<DbError | void> => {
        for (const [key, entity] of byFlag) {
          const on = await Promise.resolve()
            .then(() => isEnabled(key))
            .catch(() => false);

          if (!on) {
            return dbError("not_found", `${entity} is not available`);
          }
        }
      },
    };
  }

  return hooks;
}
