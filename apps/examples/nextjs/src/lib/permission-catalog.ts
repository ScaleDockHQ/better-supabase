import { permissionCatalog } from "better-supabase/claims";

import { permissionKeys } from "./supabase/permission-scopes";

/**
 * Catalog keys an early migration inserted that no block or table checks any
 * more. The access token hook hashes every row of
 * `better_supabase.permissions`, so the catalog the app reads the bitset claim
 * over must list them too. A key missing here changes the hash, and every read
 * falls back to `my_permissions()`.
 */
const LEGACY_KEYS = [
  "comments.create",
  "comments.moderate",
  "comments.read",
  "customers.read",
  "customers.write",
  "organization.read",
  "reports.read",
] as const;

/**
 * The catalog `permissionsOf` and `permissionsAuthorizer` read the
 * `permissions` claim over.
 */
export const catalog = permissionCatalog([...permissionKeys, ...LEGACY_KEYS]);
