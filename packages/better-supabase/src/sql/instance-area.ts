import type { ResolvedInstance } from "../config/instances.ts";
import type { EntityNames } from "../core/entity-naming.ts";
import type { BlockSqlNames } from "./context.ts";
import type { ResolvedNames } from "./resolved-names.ts";

import { instancePrefix } from "../config/instances.ts";

/**
 * Moves a key in `block`'s permission area to the area of the instance that
 * installs it under another name: `tasks.read` becomes `tickets.read`.
 */
export function instanceArea(
  block: string,
  instance: string | undefined,
  key: string,
): string {
  const area = `${instancePrefix(block)}.`;

  return instance === undefined || !key.startsWith(area)
    ? key
    : `${instancePrefix(instance)}.${key.slice(area.length)}`;
}

/** `entities` for `instance`, with `block`'s permission area renamed too. */
export function instanceEntityNames(
  block: string,
  instance: string,
  entities: EntityNames,
): EntityNames {
  return {
    ...entities,
    renamed: true,
    rename: (key: string) =>
      instanceArea(block, instance, entities.rename(key)),
  };
}

/**
 * Throws when `instance` installs `module` next to another instance without
 * renaming its primary entity and every entity that is a record type: their
 * permission keys, event types and record types would be the other instance's.
 */
export function checkInstanceEntities(
  instance: string,
  module: string,
  names: BlockSqlNames,
  resolved: ResolvedNames,
  instances: Readonly<Record<string, ResolvedInstance>> = {},
): void {
  const siblings = Object.values(instances).filter(
    (each) => each.block === module && each.name !== instance,
  );

  if (siblings.length === 0) {
    return;
  }

  const unrenamed = Object.values(resolved.entities).filter((entity) => {
    const spec = names.entities?.[entity.key];

    return (
      !entity.global &&
      (spec?.primary === true || spec?.subject !== undefined) &&
      entity.to.singular === entity.from.singular
    );
  });

  if (unrenamed.length > 0) {
    throw new TypeError(
      `blocks.${instance}: "${module}" is installed more than once, so this instance renames ${unrenamed.map((entity) => `"${entity.key}"`).join(" and ")} in blocks.${instance}.entities.`,
    );
  }
}
