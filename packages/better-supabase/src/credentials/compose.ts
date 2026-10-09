import type {
  CredentialCapabilities,
  CredentialProvider,
  CredentialRef,
  CredentialSubject,
} from "./provider.ts";

import { type DbError, dbError } from "../core/errors.ts";
import { AsyncResult } from "../core/result.ts";
import { credentialProviderOf, credentialRefInTenant } from "./provider.ts";

const NO_CAPABILITIES: CredentialCapabilities = {
  userSubjects: false,
  authorization: false,
  revoke: false,
  inbound: false,
};

const unsupported = (provider: string, what: string): DbError =>
  dbError("unsupported", `The credential provider "${provider}" ${what}`, {
    hint: "CREDENTIAL_UNSUPPORTED",
  });

/**
 * One provider over several: each call goes to the provider whose `name`
 * is the ref's `provider`. A ref no provider handles fails with
 * `invalid_input` (`CREDENTIAL_PROVIDER_UNKNOWN`), and an optional method
 * the chosen provider lacks with `unsupported`.
 */
export function credentialRouter(
  providers: readonly CredentialProvider[],
  options: { readonly name?: string } = {},
): CredentialProvider {
  const byName = new Map<string, CredentialProvider>();
  for (const provider of providers) {
    if (byName.has(provider.name)) {
      throw new TypeError(
        `credentialRouter got two providers named "${provider.name}"`,
      );
    }
    byName.set(provider.name, credentialProviderOf(provider));
  }
  const unknown = (ref: CredentialRef): DbError =>
    dbError(
      "invalid_input",
      `No credential provider named "${ref.provider}" is configured`,
      { hint: "CREDENTIAL_PROVIDER_UNKNOWN" },
    );
  const route = <T>(
    ref: CredentialRef,
    then: (provider: CredentialProvider) => AsyncResult<T>,
  ): AsyncResult<T> => {
    const provider = byName.get(ref.provider);
    return provider === undefined
      ? AsyncResult.err(unknown(ref))
      : then(provider);
  };
  return {
    apiVersion: 1,
    name: options.name ?? "router",
    getToken: (ref, tokenOptions) =>
      route(ref, (provider) => provider.getToken(ref, tokenOptions)),
    capabilities: (ref) =>
      byName.get(ref.provider)?.capabilities(ref) ?? NO_CAPABILITIES,
    startAuthorization: (ref, startOptions) =>
      route(ref, (provider) =>
        provider.startAuthorization === undefined
          ? AsyncResult.err(
              unsupported(provider.name, "doesn't authorize accounts"),
            )
          : provider.startAuthorization(ref, startOptions),
      ),
    completeAuthorization: (ref, completeOptions) =>
      route(ref, (provider) =>
        provider.completeAuthorization === undefined
          ? AsyncResult.err(
              unsupported(provider.name, "doesn't authorize accounts"),
            )
          : provider.completeAuthorization(ref, completeOptions),
      ),
    revoke: (ref, revokeOptions) =>
      route(ref, (provider) => provider.revoke(ref, revokeOptions)),
    verifyInbound: (request, ref) =>
      route(ref, (provider) =>
        provider.verifyInbound === undefined
          ? AsyncResult.err(
              unsupported(provider.name, "doesn't verify inbound requests"),
            )
          : provider.verifyInbound(request, ref),
      ),
    set: (ref, value, setOptions) =>
      route(ref, (provider) =>
        provider.set === undefined
          ? AsyncResult.err(unsupported(provider.name, "can't store secrets"))
          : provider.set(ref, value, setOptions),
      ),
  };
}

export interface RevokeIfConfiguredOptions {
  readonly subject: CredentialSubject;
  /**
   * The tenant of the row that holds the ref, or `undefined` for an
   * app-level row. When the key is present, a ref outside that tenant is
   * left alone, so a row can never revoke another tenant's credential.
   */
  readonly tenant?: string | undefined;
}

/**
 * Revokes the credential a ref names when a provider is configured and can
 * revoke it. Resolves `false` without a provider, for a provider without
 * revocation, or for a ref outside `options.tenant`.
 */
export function revokeIfConfigured(
  provider: CredentialProvider | undefined,
  ref: CredentialRef,
  options: RevokeIfConfiguredOptions,
): AsyncResult<boolean> {
  if (provider === undefined) return AsyncResult.ok(false);
  if ("tenant" in options && !credentialRefInTenant(ref, options.tenant)) {
    return AsyncResult.ok(false);
  }
  if (!provider.capabilities(ref).revoke) return AsyncResult.ok(false);
  return provider.revoke(ref, { subject: options.subject });
}
