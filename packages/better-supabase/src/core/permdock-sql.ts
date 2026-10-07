import { sqlIdent, sqlString } from "./template.ts";

const SCOPE = /^[a-z][a-z0-9_]*$/;
/** PermDock's default `rls.schema`, a schema the Data API does not expose. */
export const PERMDOCK_SCHEMA = "permdock";
/** PermDock splits a key with row conditions into `key#1`, `key#2`, ...: those need its own policies. */
const SPLIT_KEY = /#\d+$/;

/**
 * The part of PermDock's `permissions.catalog.json` the Storage and Realtime
 * builders read: `import catalog from './permissions.catalog.json'`.
 */
export interface PermdockCatalog {
  readonly permissions: readonly {
    readonly key: string;
    readonly rowConditions?: boolean;
    /**
     * The entry's `scope`. In current catalogs it is the OAuth scope
     * (`invoice:read`); the tenancy scopes are on `grants`.
     */
    readonly scope?: string;
  }[];
  /** The tenancy scopes each permission is granted at, from `grants[].scope`. */
  readonly grants?: readonly {
    readonly permission: string;
    readonly scope: string;
  }[];
  /** The catalog's tenancy scope names, from `scopes[].name`. */
  readonly scopes?: readonly string[];
}

/**
 * What PermDock's catalog says about a key: `scope-only` (`rowConditions:
 * false`), `row-conditions` (`true`), `no-flag` (an entry without a boolean
 * flag, from an older `permdock catalog`) or `missing`. Only `scope-only` is
 * safe for the SQL helpers.
 */
export type PermdockKeyStatus =
  | "scope-only"
  | "row-conditions"
  | "no-flag"
  | "missing";

export function permdockKeyStatus(
  catalog: PermdockCatalog,
  key: string,
): PermdockKeyStatus {
  const entry = catalog.permissions.find(
    (permission) => permission.key === key,
  );
  if (!entry) return "missing";
  if (entry.rowConditions === true) return "row-conditions";
  if (entry.rowConditions === false) return "scope-only";
  return "no-flag";
}

const REGENERATE =
  "Regenerate permissions.catalog.json with a current `permdock catalog`, which writes rowConditions for every permission.";

interface PermdockTarget {
  readonly scope: string;
  readonly schema?: string;
}

/**
 * The SQL condition for one PermDock permission key. `id` is the text
 * expression holding the scope id; it is compared as text, so a malformed
 * path never raises a cast error.
 *
 * The helpers check role and scope, not a permission's row conditions, so
 * the condition is only correct for permissions whose grants have none
 * beyond the scope. `#n` keys are refused. With a catalog, only keys it marks
 * `rowConditions: false` are accepted: `true`, a missing flag and a key the
 * catalog doesn't list are refused.
 */
export function permdockCheck(
  where: string,
  target: PermdockTarget,
  key: string,
  id: string | undefined,
  catalog?: PermdockCatalog,
): string {
  if (key === "")
    throw new TypeError(`${where}: a PermDock permission key is empty`);
  if (SPLIT_KEY.test(key)) {
    throw new TypeError(
      `${where}: "${key}" is one part of a permission PermDock splits by row condition. Use PermDock's generated policies for it.`,
    );
  }
  if (catalog) {
    const status = permdockKeyStatus(catalog, key);
    switch (status) {
      case "scope-only":
        break;
      case "row-conditions":
        throw new TypeError(
          `${where}: "${key}" has row conditions in PermDock's catalog (rowConditions: true), which the SQL helpers don't check. Use PermDock's generated policies for it.`,
        );
      case "no-flag":
        throw new TypeError(
          `${where}: "${key}" has no rowConditions flag in PermDock's catalog, so whether the SQL helpers check it fully is unknown. ${REGENERATE}`,
        );
      case "missing":
        throw new TypeError(
          `${where}: "${key}" is not in PermDock's catalog. ${REGENERATE}`,
        );
      default: {
        const unreachable: never = status;
        return unreachable;
      }
    }
  }
  const schema = sqlIdent(target.schema ?? PERMDOCK_SCHEMA);
  if (target.scope === "global")
    return `(select ${schema}.permdock_has(${sqlString(key)}))`;
  if (!SCOPE.test(target.scope))
    throw new TypeError(`${where}: invalid PermDock scope "${target.scope}"`);
  if (id === undefined)
    throw new TypeError(`${where}: scope "${target.scope}" needs a segment`);
  return `${id} in (select t.id::text from ${schema}.${sqlIdent(`permitted_${target.scope}_ids`)}(${sqlString(key)}) as t(id))`;
}

/** The keys a bucket or topic PermDock policy names. */
export function permdockKeys(policy: { readonly permdock: object }): string[] {
  return Object.values(policy.permdock).filter(
    (key): key is string => typeof key === "string",
  );
}
