import type { EntitySurface } from "./entity-surface.ts";

/**
 * The fixed verbs of a generated permission key (ADR 0799). A key is
 * `<block>.<entity>.<verb>`; a verb outside this list is a named domain verb
 * (`approve`, `publish`, `close`) in snake case.
 */
export const PERMISSION_VERBS: readonly string[] = [
  "read",
  "create",
  "update",
  "archive",
  "delete",
  "export",
  "import",
  "manage",
];

const SEGMENT = /^[a-z][a-z0-9_]*$/;

/** A block name as the first part of a key: `api-keys` is `api_keys`. */
export const permissionArea = (block: string): string =>
  block.replaceAll("-", "_");

/**
 * Why `key` can't be the key `verb` checks on `entity` of `block`, or
 * `undefined` when it can. A three-part key must be exactly
 * `<block>.<entity>.<verb>`. A two-part key is the pre-0.47 form
 * (`<area>.<verb>`), accepted only when `legacy` lists it, so a manifest can
 * name the key a module already checks without renaming it.
 */
export function permissionKeyProblem(
  block: string,
  entity: string,
  verb: string,
  key: string,
  legacy: ReadonlySet<string>,
): string | undefined {
  if (!SEGMENT.test(verb)) {
    return `the verb "${verb}" must be snake_case`;
  }

  const parts = key.split(".");

  if (parts.length === 2 && legacy.has(key)) {
    return undefined;
  }

  if (parts.length !== 3 || !parts.every((part) => SEGMENT.test(part))) {
    return `"${key}" must be <block>.<entity>.<verb> in snake_case`;
  }

  const expected = `${permissionArea(block)}.${entity}.${verb}`;

  return key === expected
    ? undefined
    : `"${key}" must be "${expected}" (<block>.<entity>.<verb>)`;
}

/** One declared permission: the key `verb` checks on `entity`. */
export interface DeclaredPermission {
  readonly entity: string;
  readonly verb: string;
  readonly key: string;
}

/** The permissions a block's entities declare, in declaration order. */
export function declaredPermissions(
  entities: Readonly<Record<string, EntitySurface>> | undefined,
): readonly DeclaredPermission[] {
  return Object.entries(entities ?? {}).flatMap(([entity, surface]) =>
    Object.entries(surface.permissions ?? {}).map(([verb, key]) => ({
      entity,
      verb,
      key,
    })),
  );
}
