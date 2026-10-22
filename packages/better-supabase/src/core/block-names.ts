import type { BlockTransportMiddleware } from "./block-hooks.ts";
import type { EntityNames, EntityRename } from "./entity-naming.ts";

import { defineTransportMiddleware } from "./block-hooks.ts";
import { composeNames, entityNames, tenantNames } from "./entity-naming.ts";

// The block columns that carry the tenant concept in their default name.
// `blocks.memberships.names.organization` refuses a name that would make one of
// them collide with a column a block already has, so the map back is
// unambiguous.
const TENANT_COLUMNS = ["organization_id", "active_organization_id"] as const;

// Values the caller owns: extra columns and free-form metadata keep the keys
// they were given in both directions.
const OPAQUE_KEYS: ReadonlySet<string> = new Set(["fields", "metadata"]);

// A grid edit names the column it changes (`{ field: "projectId" }`), so the
// value under `field` is a key too.
const KEY_VALUES: ReadonlySet<string> = new Set(["field"]);

/**
 * How the SQL names a block's functions and payload keys: the tenant's name
 * (`blocks.memberships.names.organization`), the block's renamed entities
 * (`blocks.<name>.entities`) and the `blocks.<name>.functions` maps, merged.
 * `better-supabase gen` writes it to each block's `names` in
 * `blocks.generated.ts`.
 */
export interface BlockNaming {
  /** `blocks.memberships.names.organization`, such as `workspace`. */
  readonly tenant?: string;
  /** Function name to the name the SQL writes it under. */
  readonly functions?: Readonly<Record<string, string>>;
  /** The block's own entities the config renames, such as `work_item` to `task`. */
  readonly entities?: readonly EntityRename[];
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  const prototype: unknown = Object.getPrototypeOf(value);

  return prototype === Object.prototype || prototype === null;
}

function renameEntry(
  key: string,
  value: unknown,
  rename: (key: string) => string,
): unknown {
  if (OPAQUE_KEYS.has(key)) {
    return value;
  }

  if (KEY_VALUES.has(key) && typeof value === "string") {
    return rename(value);
  }

  return renameKeys(value, rename);
}

/**
 * `value` with every key of every plain object in it passed through `rename`,
 * and the column a `field` names, leaving the values under `fields` and
 * `metadata` alone.
 */
export function renameKeys(
  value: unknown,
  rename: (key: string) => string,
): unknown {
  if (Array.isArray(value)) {
    return value.map((each) => renameKeys(each, rename));
  }

  if (!isPlainObject(value)) {
    return value;
  }

  return Object.fromEntries(
    Object.entries(value).map(([key, each]) => [
      rename(key),
      renameEntry(key, each, rename),
    ]),
  );
}

/** The arguments with the keys nested inside them renamed; parameter names stay. */
function renameArgs(
  args: Readonly<Record<string, unknown>>,
  entities: EntityNames,
): Readonly<Record<string, unknown>> {
  return Object.fromEntries(
    Object.entries(args).map(([key, value]) => [
      key,
      renameEntry(key, value, (each) => entities.rename(each)),
    ]),
  );
}

/**
 * Transport middleware that calls each block function by the name the SQL wrote
 * it under and translates the payload keys: `create_organization` becomes
 * `create_workspace` with `tenant: "workspace"`, `list_work_items` becomes
 * `list_tasks` with `work_item` renamed to `task`, then `functions` renames
 * single functions. Keys inside the arguments (`projectId`) go out renamed, and
 * the keys of the result come back by their default names, so the block's
 * client reads what it always has. Wrap a block's transport with it when the
 * config sets `blocks.<name>.entities` or `blocks.<name>.functions`;
 * `defineBlocks` does it from `blocks.generated.ts`.
 */
export function blockNames(naming: BlockNaming): BlockTransportMiddleware {
  const tenant = tenantNames(naming.tenant);
  const entities = entityNames(naming.entities);
  const names = composeNames(tenant, entities);
  const functions = naming.functions ?? {};

  const rename = (fn: string): string => {
    const renamed = names.rename(fn);

    return functions[fn] ?? functions[renamed] ?? renamed;
  };

  const columns = new Map(
    TENANT_COLUMNS.map((column) => [tenant.rename(column), column]),
  );

  // A row a function returns whole (`to_jsonb(row)`) carries the renamed
  // tenant columns and entity keys; the clients read them by their default
  // names.
  const restore = (key: string): string =>
    columns.get(key) ?? entities.reverse(key);

  return defineTransportMiddleware({
    name: "block-names",
    call: async (request, next) => {
      const result = await next({
        ...request,
        fn: rename(request.fn),
        ...(entities.renamed
          ? { args: renameArgs(request.args, entities) }
          : {}),
      });

      return names.renamed ? renameKeys(result, restore) : result;
    },
  });
}
