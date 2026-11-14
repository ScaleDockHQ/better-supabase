import type {
  Jwk,
  JwsAlgorithm,
  SigningAlgorithm,
  SigningCryptoKey,
} from "../../core/jws.ts";
import type { BlockCall, BlockOptions } from "../shared.ts";

import { dbError } from "../../core/errors.ts";
import {
  generateSigningKey,
  importSigningKey,
  signBytes,
  signCompact,
} from "../../core/jws.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  errorText,
  isRecord,
  portOf,
  recordOf,
  run,
  textOf,
} from "../shared.ts";

/** Who a key belongs to: an organization, an app, a stream. */
export interface SigningKeyOwner {
  /** Lowercase letters, digits, `-` and `_`, such as `organization`. */
  readonly type: string;
  readonly id: string;
}

/** What `sign` returns. */
export interface Signature {
  readonly kid: string;
  readonly alg: JwsAlgorithm;
  readonly signature: Uint8Array;
}

/** What `KeyProvider.signJwt` returns: the compact JWS and the key behind it. */
export interface SignedJwt {
  readonly token: string;
  readonly kid: string;
  readonly alg: JwsAlgorithm;
}

/**
 * Where an owner's private keys live and how they sign. The default,
 * `vaultKeyProvider`, keeps them in Supabase Vault (ADR 0033);
 * `vercelKmsKeyProvider` signs in Vercel KMS, so the private key never leaves
 * it. Check a provider of your own with `testKeyProvider` from
 * `better-supabase/testing`.
 */
export interface KeyProvider {
  readonly apiVersion: 1;
  /** Names the provider in errors and conformance reports, such as `vault`. */
  readonly name: string;
  /**
   * The raw signature of `data` with the owner's active key. `create` names the
   * key type to generate when the owner has none; a provider whose keys are
   * managed elsewhere ignores it.
   */
  sign(input: {
    owner: SigningKeyOwner;
    data: Uint8Array;
    create?: SigningAlgorithm | undefined;
  }): AsyncResult<Signature>;
  /**
   * A compact JWS over `claims`. The provider sets `alg` and `kid` in the
   * header; `header` carries the rest (`typ` and the app's members).
   */
  signJwt(input: {
    owner: SigningKeyOwner;
    claims: Readonly<Record<string, unknown>>;
    header: Readonly<Record<string, unknown>>;
    create?: SigningAlgorithm | undefined;
  }): AsyncResult<SignedJwt>;
  /**
   * Keeps the key `kid` published until at least `exp`, for a provider whose
   * key set would otherwise drop a key that a valid token still needs. The
   * signer calls it for a numeric `exp`, rounded up to the hour. `false` for an
   * unknown kid.
   */
  noteExp?(input: { kid: string; exp: Temporal.Instant }): AsyncResult<boolean>;
}

/**
 * Returns `provider` after checking its `apiVersion`, so a provider built for
 * another contract fails at construction.
 */
export function keyProviderOf(provider: KeyProvider): KeyProvider {
  portOf(`keys "${provider.name}"`, "key provider", provider);

  return provider;
}

/** The `signing-keys` options the Vault provider reads. */
export interface VaultKeyProviderOptions extends Pick<
  BlockOptions,
  "transport" | "schema" | "mappers" | "temporal"
> {
  /**
   * The JWS `alg` an Ed25519 key signs with: `EdDSA` (RFC 8037), which most
   * verifiers read, or the fully specified `Ed25519` (RFC 9864). Default:
   * `EdDSA`.
   */
  readonly ed25519Alg?: "EdDSA" | "Ed25519";
  /** How long the provider keeps an imported private key, in seconds. Default: 300. */
  readonly cacheSeconds?: number;
}

const ALGORITHMS = ["Ed25519", "ES256"] as const;

interface ActiveKey {
  readonly kid: string;
  readonly alg: SigningAlgorithm;
  readonly key: SigningCryptoKey;
  readonly at: number;
}

/** The key a block change makes stale: one owner's, or every copy of a kid. */
export type ForgetTarget =
  | { readonly owner: SigningKeyOwner }
  | { readonly kid: string };

const forgetters = new WeakMap<KeyProvider, (target: ForgetTarget) => void>();

/**
 * Drops the cached private key a Vault provider holds for `target`, after the
 * block changed the owner's keys. Does nothing for any other provider.
 */
export function forgetSigningKey(
  provider: KeyProvider,
  target: ForgetTarget,
): void {
  forgetters.get(provider)?.(target);
}

const ownerKey = (owner: SigningKeyOwner): string =>
  `${owner.type}:${owner.id}`;

export const ownerArgs = (
  owner: SigningKeyOwner,
): { owner_type: string; owner_id: string } => ({
  owner_type: owner.type,
  owner_id: owner.id,
});

/** Generates a key and stores it with `add_signing_key`. */
export function addSigningKey(
  call: BlockCall,
  owner: SigningKeyOwner,
  alg: SigningAlgorithm,
): AsyncResult<{
  readonly kid: string;
  readonly alg: SigningAlgorithm;
  readonly publicKey: Jwk;
  readonly retired: string | null;
}> {
  return run(() => generateSigningKey(alg)).andThen((generated) =>
    call(
      "add_signing_key",
      {
        ...ownerArgs(owner),
        kid: generated.kid,
        alg,
        public_jwk: generated.publicKey,
        private_jwk: JSON.stringify(generated.privateKey),
      },
      (value) => {
        const row = recordOf(value, "add_signing_key");

        return {
          kid: generated.kid,
          alg,
          publicKey: generated.publicKey,
          retired: typeof row["retired"] === "string" ? row["retired"] : null,
        };
      },
    ),
  );
}

/** The owner's active key from `signing_key`, private JWK included. */
export function storedSigningKey(
  call: BlockCall,
  owner: SigningKeyOwner,
): AsyncResult<{
  readonly kid: string;
  readonly alg: SigningAlgorithm;
  readonly privateKey: string;
} | null> {
  return call("signing_key", ownerArgs(owner), (value) => {
    if (value === null || value === undefined) {
      return null;
    }

    const row = recordOf(value, "signing_key");

    return {
      kid: textOf(row["kid"]),
      alg: enumOrThrow(row["alg"], ALGORITHMS, "signing key alg"),
      privateKey: textOf(row["privateKey"]),
    };
  });
}

/**
 * Keys in Supabase Vault, signed with WebCrypto here (ADR 0033): the default
 * provider of `createSigningKeys`. It reads the active private key with
 * `signing_key`, keeps it for `cacheSeconds`, and notes each `exp` with
 * `note_signing_key_exp`.
 */
export function vaultKeyProvider(
  options: VaultKeyProviderOptions,
): KeyProvider {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const ed25519Alg = options.ed25519Alg ?? "EdDSA";
  const cacheMs = (options.cacheSeconds ?? 300) * 1000;
  const keys = new Map<string, ActiveKey>();

  const jwsAlg = (alg: SigningAlgorithm): JwsAlgorithm =>
    alg === "Ed25519" ? ed25519Alg : "ES256";

  const active = (
    owner: SigningKeyOwner,
    create: SigningAlgorithm | undefined,
  ): AsyncResult<ActiveKey> => {
    const cacheKey = ownerKey(owner);
    const cached = keys.get(cacheKey);

    if (cached && Date.now() - cached.at < cacheMs) {
      return AsyncResult.ok(cached);
    }

    return storedSigningKey(call, owner).andThen((found) => {
      if (found) {
        return run(async () => {
          const parsed: unknown = JSON.parse(found.privateKey);

          if (!isRecord(parsed) || typeof parsed["kty"] !== "string") {
            throw new TypeError("The stored signing key is not a JWK");
          }

          // SAFETY: parsed is an object with a string kty; importSigningKey checks the rest.
          const key = await importSigningKey(parsed as Jwk);
          const entry = { kid: found.kid, alg: found.alg, key, at: Date.now() };
          keys.set(cacheKey, entry);

          return entry;
        });
      }

      if (create === undefined) {
        return AsyncResult.err(
          dbError("not_found", `${cacheKey} has no signing key`, {
            hint: "SIGNING_KEY_MISSING",
          }),
        );
      }

      return addSigningKey(call, owner, create).andThen(() => {
        keys.delete(cacheKey);

        return active(owner, undefined);
      });
    });
  };

  const provider: KeyProvider = {
    apiVersion: 1,
    name: "vault",
    sign: ({ owner, data, create }) =>
      active(owner, create).andThen((key) =>
        run(async () => ({
          kid: key.kid,
          alg: jwsAlg(key.alg),
          signature: await signBytes(key.key, key.alg, data),
        })),
      ),
    signJwt: ({ owner, claims, header, create }) =>
      active(owner, create).andThen((key) =>
        run(async () => ({
          token: await signCompact(
            key.key,
            key.alg,
            { alg: jwsAlg(key.alg), kid: key.kid, ...header },
            claims,
          ),
          kid: key.kid,
          alg: jwsAlg(key.alg),
        })),
      ),
    noteExp: ({ kid, exp }) =>
      call(
        "note_signing_key_exp",
        { kid, exp: exp.toString() },
        (value) => value === true,
      ),
  };

  forgetters.set(provider, (target) => {
    if ("owner" in target) {
      keys.delete(ownerKey(target.owner));

      return;
    }

    for (const [owner, entry] of keys) {
      if (entry.kid === target.kid) {
        keys.delete(owner);
      }
    }
  });

  return provider;
}

/**
 * What `signMessage` and `signJWT` of `@vercel/kms` take besides their own
 * members.
 */
interface VercelKmsRequest {
  issuerId: string;
  token?: string;
  region?: string;
  baseUrl?: string;
}

/**
 * The part of `@vercel/kms` the provider calls, typed structurally; pass
 * `import * as kms from "@vercel/kms"`.
 */
export interface VercelKmsModule {
  signMessage(
    options: VercelKmsRequest & { message: Uint8Array },
  ): Promise<{ signature: Uint8Array; keyId: string; algorithm: string }>;
  signJWT(
    options: VercelKmsRequest & {
      claims?: Record<string, unknown>;
      headers?: Record<string, unknown>;
      ttl?: number | null;
    },
  ): Promise<{ token: string; keyId: string; algorithm: string }>;
}

export interface VercelKmsKeyProviderOptions {
  /**
   * The KMS issuer that signs for an owner, such as `iss_...`, or a function
   * that picks one per owner.
   */
  readonly issuer: string | ((owner: SigningKeyOwner) => string);
  /**
   * The Vercel OIDC token to authenticate with, or a function that returns one
   * per call. Default: the function's own token, which `@vercel/kms` fetches.
   */
  readonly token?: string | (() => string | Promise<string>);
  /** The regional KMS API host, such as `sfo1`. Default: `VERCEL_REGION`. */
  readonly region?: string;
  /** The KMS API base URL; takes precedence over `region`. */
  readonly baseUrl?: string;
}

const JWS_ALGORITHMS: readonly JwsAlgorithm[] = [
  "EdDSA",
  "Ed25519",
  "ES256",
  "PS256",
  "RS256",
];

const jwsAlgorithmOf = (algorithm: string): JwsAlgorithm | undefined =>
  JWS_ALGORITHMS.find((name) => name === algorithm);

const kmsError = (cause: unknown) => {
  const message = `Vercel KMS: ${errorText(cause)}`;

  if (!isRecord(cause) || typeof cause["status"] !== "number") {
    return dbError("network", message);
  }

  const extra =
    typeof cause["code"] === "string" ? { code: cause["code"] } : {};

  const metadata = isRecord(cause["metadata"]) ? cause["metadata"] : {};
  const retryAfter = metadata["retryAfter"] ?? metadata["retry_after"];

  switch (cause["status"]) {
    case 404: {
      return dbError("not_found", message, {
        ...extra,
        hint: "SIGNING_KEY_MISSING",
      });
    }

    case 401:
    case 403: {
      return dbError("forbidden", message, extra);
    }

    case 429: {
      return dbError("rate_limited", message, {
        ...extra,
        ...(typeof retryAfter === "number" && Number.isFinite(retryAfter)
          ? { retryAfter }
          : {}),
      });
    }

    default: {
      return dbError("network", message, extra);
    }
  }
};

/**
 * Signs with a Vercel KMS issuer's managed key, so the private key never leaves
 * Vercel KMS. `create` is ignored: an issuer holds its own keys, and Vercel KMS
 * publishes their JWK Set. `signJwt` passes `ttl: null`, so the claims' own
 * `exp` decides the lifetime and KMS adds none. Failures are `DbError`s: a 404
 * is `not_found` with the hint `SIGNING_KEY_MISSING`, 401 and 403 `forbidden`,
 * 429 `rate_limited`, anything else `network`.
 */
export function vercelKmsKeyProvider(
  kms: VercelKmsModule,
  options: VercelKmsKeyProviderOptions,
): KeyProvider {
  const request = async (owner: SigningKeyOwner): Promise<VercelKmsRequest> => {
    const token =
      typeof options.token === "function"
        ? await options.token()
        : options.token;

    return {
      issuerId:
        typeof options.issuer === "function"
          ? options.issuer(owner)
          : options.issuer,
      ...(token === undefined ? {} : { token }),
      ...(options.region === undefined ? {} : { region: options.region }),
      ...(options.baseUrl === undefined ? {} : { baseUrl: options.baseUrl }),
    };
  };

  const signed = <R extends { keyId: string; algorithm: string }>(
    sign: () => Promise<R>,
  ) =>
    AsyncResult.from(async () => {
      let result: R;

      try {
        result = await sign();
      } catch (cause) {
        return err(kmsError(cause));
      }

      const alg = jwsAlgorithmOf(result.algorithm);

      return alg === undefined
        ? err(
            dbError(
              "unexpected",
              `Vercel KMS signed with ${result.algorithm}, which is not a JWS alg this signer supports`,
              { hint: "SIGNING_ALG_UNSUPPORTED" },
            ),
          )
        : ok({ result, kid: result.keyId, alg });
    });

  return {
    apiVersion: 1,
    name: "vercel-kms",
    sign: ({ owner, data }) =>
      signed(async () =>
        kms.signMessage({ ...(await request(owner)), message: data }),
      ).map(({ result, kid, alg }) => ({
        kid,
        alg,
        signature: result.signature,
      })),
    signJwt: ({ owner, claims, header }) =>
      signed(async () =>
        kms.signJWT({
          ...(await request(owner)),
          claims: { ...claims },
          headers: { ...header },
          ttl: null,
        }),
      ).map(({ result, kid, alg }) => ({ token: result.token, kid, alg })),
  };
}
