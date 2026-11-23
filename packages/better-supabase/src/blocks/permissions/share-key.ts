import type { ShareKeyHook } from "../../core/contracts/authorization-hooks.ts";

import { keysFromClaims } from "../../auth/permissions.ts";
import { AUTHZ_VERSION_CLAIM } from "../../core/claim-names.ts";
import { DEFAULT_CLAIMS } from "../../core/claims.ts";
import { permissionMatches } from "./permissions-controller.ts";

export interface PermissionsShareKeyOptions {
  /** `config.claims.permissions`, when renamed. Defaults to `permissions`. */
  readonly claim?: string;
  /** The provider's `tokenHook.truncatedClaim`. Defaults to `<claim>_truncated`. */
  readonly truncatedClaim?: string;
}

interface VersionReader {
  get(userId: string): PromiseLike<number | undefined> | number | undefined;
}

const readsVersions = (value: unknown): value is VersionReader =>
  typeof value === "object" &&
  value !== null &&
  "get" in value &&
  typeof value.get === "function";

/**
 * `AuthorizationHooks.shareKey` over the permissions block: the keys of
 * `permissions` the caller's `permissions` claim grants in the tenant. It
 * answers `null`, so the entry stays per user, when the claim can't show them
 * (no entry for the tenant, or the hook marked it truncated), when the token's
 * `authz_ver` is behind the version the server's version cache holds, and when
 * the caller holds none of them.
 *
 * ```ts
 * defineAuthorizationHooks({
 *   apiVersion: 1,
 *   name: "app",
 *   shareKey: permissionsShareKey(),
 * });
 * ```
 */
export function permissionsShareKey(
  options: PermissionsShareKeyOptions = {},
): ShareKeyHook {
  const claim = options.claim ?? DEFAULT_CLAIMS.permissions;

  return async (_authorizer, permissions, { subject, context, runtime }) => {
    const claims = subject.properties?.["claims"];
    const { tenant } = context;

    if (
      typeof tenant !== "string" ||
      subject.type !== "user" ||
      typeof claims !== "object" ||
      claims === null ||
      Array.isArray(claims)
    ) {
      return null;
    }

    // SAFETY: a plain object, checked above.
    const record = claims as Readonly<Record<string, unknown>>;
    const keys = keysFromClaims(record, tenant, claim, options.truncatedClaim);

    if (keys === undefined) {
      return null;
    }

    const { versions } = runtime ?? {};

    if (readsVersions(versions)) {
      const live = await versions.get(subject.id);
      const token = record[AUTHZ_VERSION_CLAIM];

      if (live !== undefined && (typeof token !== "number" || token < live)) {
        return null;
      }
    }

    const held = permissions.filter((wanted) =>
      keys.some((granted) => permissionMatches(granted, wanted)),
    );

    return held.length === 0 ? null : held.join(",");
  };
}
