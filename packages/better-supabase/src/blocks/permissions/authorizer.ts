import type {
  AuthorizationOutcome,
  AuthorizationRequest,
  Authorizer,
  AuthorizerRuntime,
  RequestMemo,
} from "../../core/authorizer.ts";

import { keysFromClaims } from "../../auth/permissions.ts";
import { DEFAULT_CLAIMS } from "../../core/claims.ts";
import { permissionMatches } from "./permissions-controller.ts";

/** The generated `permissions` map: permission keys by owner and action. */
export type PermissionMap<Key extends string = string> = Readonly<
  Record<string, Readonly<Record<string, Key>>>
>;

export interface PermissionsAuthorizerOptions<Key extends string> {
  /**
   * The generated `permissions` map from `lib/supabase/blocks.generated.ts`.
   * `forOperation` reads it, so `permissions: true` on a resource checks the
   * table's `read`, `write`, `create`, `update` or `delete` key.
   */
  readonly permissions: PermissionMap<Key>;
  /**
   * The caller's keys in a tenant when the token can't answer (no claim, no
   * entry for the tenant, or the hook marked it truncated), for example
   * `my_permissions` through the request's client. Runs once per subject and
   * tenant in a request scope. Without it, those requests are denied.
   */
  readonly load?: (
    request: AuthorizationRequest<Key>,
  ) => Promise<readonly string[] | undefined>;
  /** `config.claims.permissions`, when renamed. Defaults to `permissions`. */
  readonly claim?: string;
  /**
   * The claim the hook sets to `true` when it left keys out: the provider's
   * `tokenHook.truncatedClaim`. Defaults to `<claim>_truncated`.
   */
  readonly truncatedClaim?: string;
}

const OPERATION_ACTIONS: Readonly<Record<string, readonly string[]>> = {
  list: ["read"],
  get: ["read"],
  create: ["create", "write"],
  update: ["update", "write"],
  delete: ["delete", "manage", "write"],
};

/**
 * An `Authorizer` over the permissions block. It decides from the verified
 * `permissions` claim the access token hook writes (`permission_claims()`), and
 * asks `load` only when the token can't answer. RLS and `can()` check the key
 * again in the database; anything but a clear grant is `denied`.
 *
 * ```ts
 * createNext(betterSupabase, {
 *   authorizer: permissionsAuthorizer({
 *     permissions,
 *     load: async () => (await getPermissions()).keys,
 *   }),
 * });
 * ```
 */
export function permissionsAuthorizer<Key extends string>(
  options: PermissionsAuthorizerOptions<Key>,
): Authorizer<Key> {
  const claim = options.claim ?? DEFAULT_CLAIMS.permissions;

  const keysFor = async (
    request: AuthorizationRequest<Key>,
    runtime: AuthorizerRuntime | undefined,
  ): Promise<readonly string[] | undefined> => {
    const tenant = request.context["tenant"];

    if (typeof tenant !== "string" || request.subject.type === "anon") {
      return undefined;
    }

    const fromToken = claimedKeys(
      request.subject.properties,
      tenant,
      claim,
      options.truncatedClaim,
    );

    if (fromToken !== undefined || options.load === undefined) {
      return fromToken;
    }

    const { load } = options;
    const run = (): Promise<readonly string[] | undefined> => load(request);

    return runtime?.memo
      ? runtime.memo.once(`permissions:${request.subject.id}:${tenant}`, run)
      : run();
  };

  const decide = (
    request: AuthorizationRequest<Key>,
    keys: readonly string[] | undefined,
  ): AuthorizationOutcome => {
    const wanted: string = request.action;

    if (keys?.some((granted) => permissionMatches(granted, wanted))) {
      return { outcome: "granted" };
    }

    return {
      outcome: "denied",
      reason:
        keys === undefined
          ? `Permission ${wanted} is required, and the token can't show it`
          : `Permission ${wanted} is required`,
    };
  };

  return {
    apiVersion: 1,
    name: "permissions",
    key: (ref) => ref,
    forOperation: (table, operation) => {
      const owner =
        options.permissions[table] ??
        options.permissions[table.replaceAll("_", "-")];

      const action = OPERATION_ACTIONS[operation]?.find(
        (name) => owner?.[name] !== undefined,
      );

      return action === undefined ? undefined : owner?.[action];
    },
    evaluate: async (request, runtime) =>
      decide(request, await keysFor(request, runtime)),
    evaluations: (requests, runtime) => {
      const batch = new Map<string, Promise<unknown>>();

      const memo: RequestMemo = runtime?.memo ?? {
        once: <T>(key: string, load: () => Promise<T>): Promise<T> => {
          let pending = batch.get(key);

          if (pending === undefined) {
            pending = load();
            batch.set(key, pending);
          }

          // SAFETY: each key stores the promise of the load that made it.
          return pending as Promise<T>;
        },
      };

      return Promise.all(
        requests.map(async (request) =>
          decide(request, await keysFor(request, { ...runtime, memo })),
        ),
      );
    },
  };
}

function claimedKeys(
  properties: Readonly<Record<string, unknown>> | undefined,
  tenant: string,
  claim: string,
  marker: string | undefined,
): readonly string[] | undefined {
  const claims = properties?.["claims"];

  return isRecord(claims)
    ? keysFromClaims(claims, tenant, claim, marker)
    : undefined;
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
