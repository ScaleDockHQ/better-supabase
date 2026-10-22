/**
 * The caller's permission keys in one tenant, as `my_permissions` returned
 * them. It is plain data, so a Server Component can pass it to the client.
 */
export interface PermissionSet {
  /** The organization the keys hold in. */
  readonly tenant: string;
  /**
   * The keys the caller holds. Keys loaded without a list keep their wildcards
   * (`*`, `invoices.*`) as the access model grants them.
   */
  readonly keys: readonly string[];
}

/** `{ edit: "customers.write" }` as `{ canEdit: boolean }`. */
export type PermissionFlags<M extends Readonly<Record<string, string>>> = {
  readonly [N in keyof M & string as `can${Capitalize<N>}`]: boolean;
};

/**
 * Whether a granted key covers a wanted one: the same rule as the SQL
 * `permission_matches`, where `*` grants every key and `prefix.*` every key
 * under `prefix`.
 */
export function permissionMatches(granted: string, wanted: string): boolean {
  return (
    granted === "*" ||
    granted === wanted ||
    (granted.endsWith(".*") && wanted.startsWith(granted.slice(0, -1)))
  );
}

/**
 * Whether `set` holds `key`. UX only: RLS and the SQL functions check the key
 * again.
 *
 * ```ts
 * if (can(permissionSet, permissions.customers.write)) showEditButton();
 * ```
 */
export function can(
  set: PermissionSet | null | undefined,
  key: string,
): boolean {
  return set?.keys.some((granted) => permissionMatches(granted, key)) ?? false;
}

/**
 * One `can<Name>` boolean per entry of `flags`, for a payload query that
 * returns data and what the caller may do with it.
 *
 * ```ts
 * permissionFlags(set, { edit: permissions.customers.write });
 * // { canEdit: true }
 * ```
 */
export function permissionFlags<
  const M extends Readonly<Record<string, string>>,
>(set: PermissionSet | null | undefined, flags: M): PermissionFlags<M> {
  // SAFETY: one `can<Name>` entry per key of `flags`, as `PermissionFlags`
  // maps them.
  return Object.fromEntries(
    Object.entries(flags).map(([name, key]) => [
      `can${name.charAt(0).toUpperCase()}${name.slice(1)}`,
      can(set, key),
    ]),
  ) as PermissionFlags<M>;
}
