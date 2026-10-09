import type { AuthState } from "../auth/resolve.ts";
import type { AsyncResult } from "../core/result.ts";

import { type DbError, dbError } from "../core/errors.ts";

/**
 * Names a credential without holding it. Tables store this as a
 * `credential_ref jsonb` column; `provider` picks the `CredentialProvider`
 * and the other keys are that provider's.
 */
export type CredentialRef = {
  readonly provider: string;
  /**
   * The tenant that owns the credential. A provider resolves, sets and
   * revokes a ref with `tenant` only inside that tenant's namespace, so a
   * tenant admin who picks a ref can never name another tenant's or the
   * app's secret.
   */
  readonly tenant?: string;
} & Readonly<Record<string, unknown>>;

/** `ref` bound to `tenant`'s namespace. */
export function tenantCredentialRef<R extends CredentialRef>(
  tenant: string,
  ref: R,
): R & { readonly tenant: string } {
  return { ...ref, tenant };
}

/**
 * Whether `ref` belongs to `tenant`: its `tenant` is exactly that tenant.
 * Without a tenant (an app-level row), only a ref without one belongs.
 */
export function credentialRefInTenant(
  ref: CredentialRef,
  tenant: string | undefined,
): boolean {
  const owner: unknown = ref.tenant;
  return tenant === undefined
    ? owner === undefined
    : typeof owner === "string" && owner === tenant;
}

/** The error for a ref that names a credential outside the row's tenant. */
export function foreignCredentialRef(tenant: string | undefined): DbError {
  return dbError(
    "forbidden",
    tenant === undefined
      ? "An app-level credential_ref can't name a tenant's credential"
      : `The credential_ref names a credential outside tenant "${tenant}"`,
    { hint: "CREDENTIAL_REF_FOREIGN" },
  );
}

/** Whose credential to use: the app's own, or one a user connected. */
export type CredentialSubject =
  | { readonly type: "app" }
  | { readonly type: "user"; readonly id: string; readonly issuer?: string };

export interface GetTokenOptions {
  readonly subject: CredentialSubject;
  readonly scopes?: readonly string[];
  readonly installationId?: string;
  readonly signal?: AbortSignal;
}

export interface CredentialToken {
  readonly token: string;
  /** Unset when the provider doesn't know when the token expires. */
  readonly expiresAt?: Temporal.Instant;
  /** Headers that authenticate a request with this token. */
  readonly headers: Readonly<Record<string, string>>;
}

export interface CredentialCapabilities {
  /** The ref holds one credential per user subject. */
  readonly userSubjects: boolean;
  /** `startAuthorization` can send the user to connect the account. */
  readonly authorization: boolean;
  readonly revoke: boolean;
  /** `verifyInbound` can check requests the third party sends. */
  readonly inbound: boolean;
}

export interface StartAuthorizationOptions {
  readonly subject: CredentialSubject;
  readonly redirectUri: string;
  readonly scopes?: readonly string[];
  readonly state?: string;
}

export interface CompleteAuthorizationOptions {
  readonly subject: CredentialSubject;
  /** The callback request, or its URL, that carries the code and state. */
  readonly callback: Request | URL | string;
}

/**
 * Resolves `CredentialRef`s to tokens. Versioned: a breaking change to this
 * contract ships a new `apiVersion`. Errors are `DbError`s: `invalid_input`
 * for a ref the provider doesn't handle, `not_found` when no credential is
 * stored, `forbidden` when the subject may not use it.
 */
export interface CredentialProvider {
  readonly apiVersion: 1;
  readonly name: string;
  getToken(
    ref: CredentialRef,
    options: GetTokenOptions,
  ): AsyncResult<CredentialToken>;
  capabilities(ref: CredentialRef): CredentialCapabilities;
  /** The URL to send the user to; only when `capabilities(ref).authorization`. */
  startAuthorization?(
    ref: CredentialRef,
    options: StartAuthorizationOptions,
  ): AsyncResult<{ readonly url: string }>;
  completeAuthorization?(
    ref: CredentialRef,
    options: CompleteAuthorizationOptions,
  ): AsyncResult<void>;
  /** Forgets the stored credential; `false` when there was none. */
  revoke(
    ref: CredentialRef,
    options: { readonly subject: CredentialSubject },
  ): AsyncResult<boolean>;
  /** Checks a request the third party sent (a webhook) against the ref's secret. */
  verifyInbound?(request: Request, ref: CredentialRef): AsyncResult<boolean>;
}

/** Checks the provider's `apiVersion` before the server uses it. */
export function credentialProviderOf(
  provider: CredentialProvider,
): CredentialProvider {
  const version: unknown = provider.apiVersion;
  if (version !== 1) {
    throw new TypeError(
      `credentials "${provider.name}" targets credential provider API ${String(version)}; this better-supabase supports 1. Upgrade better-supabase or use a release of the provider for API 1.`,
    );
  }
  return provider;
}

/**
 * The subject for a request: the user behind a session or a user-bound API
 * key, the app for the service role, and `undefined` for anyone else.
 */
export function subjectFor(context: {
  readonly auth: AuthState;
}): CredentialSubject | undefined {
  const { auth } = context;
  switch (auth.kind) {
    case "user": {
      const issuer = auth.claims.iss;
      return typeof issuer === "string" && issuer.length > 0
        ? { type: "user", id: auth.claims.sub, issuer }
        : { type: "user", id: auth.claims.sub };
    }
    case "apiKey": {
      return auth.userId === undefined
        ? undefined
        : { type: "user", id: auth.userId };
    }
    case "service": {
      return { type: "app" };
    }
    case "anon":
    case "invalid": {
      return undefined;
    }
    default: {
      const unreachable: never = auth;
      return unreachable;
    }
  }
}
