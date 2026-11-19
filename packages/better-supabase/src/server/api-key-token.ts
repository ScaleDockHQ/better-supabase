import type { AuthState } from "../auth/resolve.ts";
import type { Jwk, SigningCryptoKey } from "../core/jws.ts";

import { importSigningKey, jwkAlgorithm, signCompact } from "../core/jws.ts";

/** What `apiKeyTokenSigner` signs with. */
export interface ApiKeyTokenSignerOptions {
  /**
   * The private P-256 JWK of a signing key the Supabase project trusts, such as
   * one imported as a standby key, so PostgREST verifies the token.
   */
  readonly key: Jwk;
  /** The token's `iss`. Defaults to none. */
  readonly issuer?: string;
  /** How long a token lives, in seconds. Default: 60. */
  readonly ttlSeconds?: number;
}

/**
 * `ServerOptions.apiKeyToken` that signs an ES256 JWT for the key's claims
 * (`sub`, `role`, `aud`, `api_key` and the provider claims), valid for
 * `ttlSeconds`. Throws a `TypeError` for a key that is not a private P-256
 * JWK.
 */
export function apiKeyTokenSigner(
  options: ApiKeyTokenSignerOptions,
): (auth: Extract<AuthState, { readonly kind: "apiKey" }>) => Promise<string> {
  const { key } = options;

  if (jwkAlgorithm(key) !== "ES256" || typeof key.d !== "string") {
    throw new TypeError(
      "apiKeyTokenSigner needs the private P-256 JWK of a key the project trusts",
    );
  }

  const ttl = options.ttlSeconds ?? 60;
  let imported: Promise<SigningCryptoKey> | undefined;

  const header = {
    alg: "ES256",
    typ: "JWT",
    ...(key.kid === undefined ? {} : { kid: key.kid }),
  };

  return async (auth) => {
    const now = Math.floor(Date.now() / 1000);

    return signCompact(
      await (imported ??= importSigningKey(key)),
      "ES256",
      header,
      {
        ...auth.claims,
        ...(options.issuer === undefined ? {} : { iss: options.issuer }),
        iat: now,
        exp: now + ttl,
      },
    );
  };
}
