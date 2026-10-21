import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import {
  generateSigningKey,
  importSigningKey,
  type Jwk,
  type Jwks,
  jwksOf,
  type JwsAlgorithm,
  signBytes,
  signCompact,
  type SigningAlgorithm,
  type SigningCryptoKey,
} from "../../core/jws.ts";
import { AsyncResult } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  applyTemporal,
  blockCall,
  type BlockOptions,
  enumOrThrow,
  isRecord,
  recordOf,
  run,
  textOf,
} from "../shared.ts";

const ALGORITHMS = ["Ed25519", "ES256"] as const;

export interface SigningKeysOptions extends BlockOptions {
  /**
   * The JWS `alg` an Ed25519 key signs with: `EdDSA` (RFC 8037), which most
   * verifiers read, or the fully specified `Ed25519` (RFC 9864). Default:
   * `EdDSA`.
   */
  readonly ed25519Alg?: "EdDSA" | "Ed25519";
  /** How long a signer keeps the imported private key, in seconds. Default: 300. */
  readonly cacheSeconds?: number;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<SigningKeys>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

/** Who a key belongs to: an organization, an app, a stream. */
export interface SigningKeyOwner {
  /** Lowercase letters, digits, `-` and `_`, such as `organization`. */
  readonly type: string;
  readonly id: string;
}

/**
 * The owner of the platform's own keys, for a single authorization server that
 * signs for every tenant. A key per tenant uses `{ type, id }` of the tenant
 * instead, such as `{ type: "environment", id: environment.id }`.
 */
export const PLATFORM_OWNER: SigningKeyOwner = {
  type: "platform",
  id: "default",
};

const TYPE_NAME = /^[a-z0-9][a-z0-9-]{0,62}$/;

// RFC 8725 section 3.11: a typ that names the kind of token, as a media type
// subtype with the +jwt suffix (`at+jwt`, `vnd.acme.invite+jwt`).
const JWT_TYPE = /^(?:JWT|[a-z0-9][a-z0-9.-]{0,126}\+jwt)$/i;

/**
 * The `typ` header for a token kind of your own: `jwtType("invite")` is
 * `vnd.invite+jwt`. Sign with `{ typ }` and verify with `verifyCompact(..., {
 * typ })` so a token of one kind can't be replayed as another (RFC 8725 section
 * 3.11). Throws a `TypeError` for a name outside lower-case letters, digits and
 * `-`.
 */
export function jwtType(name: string): string {
  if (!TYPE_NAME.test(name)) {
    throw new TypeError(
      `jwtType name must be lower-case letters, digits and "-", got ${JSON.stringify(name)}`,
    );
  }

  return `vnd.${name}+jwt`;
}

/** What `create` and `rotate` return. The private key never leaves Vault again. */
export interface CreatedSigningKey {
  readonly kid: string;
  readonly alg: SigningAlgorithm;
  readonly publicKey: Jwk;
  /**
   * The kid the new key replaced, which stays in the JWKS until its tokens
   * expire.
   */
  readonly retired: string | null;
}

/** What `sign` returns. */
export interface Signature {
  readonly kid: string;
  readonly alg: JwsAlgorithm;
  readonly signature: Uint8Array;
}

/** Signs with an owner's active key. */
export interface Signer {
  readonly owner: SigningKeyOwner;
  /** The raw signature of `data` with the active key. */
  sign(data: Uint8Array): AsyncResult<Signature>;
  /**
   * A compact JWS over `claims`, with `alg`, `kid` and `typ: "JWT"` in the
   * header unless `header` sets them. A custom `typ` has to be `JWT` or end in
   * `+jwt` (see `jwtType`); anything else fails with `SIGNING_TYP_INVALID`. A
   * numeric `exp` keeps the key in the JWKS until then
   * (`note_signing_key_exp`), so a rotation can't strand the token.
   */
  signJwt(
    claims: Readonly<Record<string, unknown>>,
    header?: Readonly<Record<string, unknown>>,
  ): AsyncResult<string>;
}

export interface JwksOptions {
  /**
   * How long a retired key stays published past its last `exp`. Default:
   * `blocks.signing-keys.options.jwksGrace`.
   */
  readonly grace?: Temporal.Duration;
}

export interface JwksResponseOptions extends JwksOptions {
  /** The `Cache-Control` max-age, in seconds. Default: 300. */
  readonly maxAge?: number;
}

export interface SignerOptions {
  /**
   * Creates a key of this type when the owner has none, instead of failing with
   * `SIGNING_KEY_MISSING`.
   */
  readonly create?: SigningAlgorithm;
}

export interface SigningKeys {
  /**
   * Generates a key for the owner and makes it active; the previous key is
   * retired.
   */
  create(
    owner: SigningKeyOwner,
    alg?: SigningAlgorithm,
  ): AsyncResult<CreatedSigningKey>;
  /** `create` with the active key's type, or `alg` when given. */
  rotate(
    owner: SigningKeyOwner,
    alg?: SigningAlgorithm,
  ): AsyncResult<CreatedSigningKey>;
  /** Retires a key without a replacement. `false` when it was not active. */
  retire(kid: string): AsyncResult<boolean>;
  /** Keeps a key published until at least `exp`. `false` for an unknown kid. */
  noteExp(kid: string, exp: Temporal.Instant): AsyncResult<boolean>;
  /** The owner's public keys still in use, as a JWK Set. */
  jwks(owner: SigningKeyOwner, options?: JwksOptions): AsyncResult<Jwks>;
  /** `jwks` as an `application/jwk-set+json` response with `Cache-Control`. */
  jwksResponse(
    owner: SigningKeyOwner,
    options?: JwksResponseOptions,
  ): Promise<Response>;
  /** Deletes every key of the owner. */
  remove(owner: SigningKeyOwner): AsyncResult<number>;
  /** Deletes retired keys no token can still need. */
  purge(options?: JwksOptions): AsyncResult<number>;
  signer(owner: SigningKeyOwner, options?: SignerOptions): Signer;
}

interface ActiveKey {
  readonly kid: string;
  readonly alg: SigningAlgorithm;
  readonly key: SigningCryptoKey;
  readonly at: number;
}

const HOUR = 3600;

const interval = (duration: Temporal.Duration | undefined): string | null =>
  duration === undefined
    ? null
    : `${String(duration.total({ unit: "seconds" }))} seconds`;

const ownerArgs = (owner: SigningKeyOwner) => ({
  owner_type: owner.type,
  owner_id: owner.id,
});

/**
 * The `signing-keys` SQL module as typed calls: keys are generated and used
 * with WebCrypto here, kept in Supabase Vault there. Service role only.
 */
export function createSigningKeys(options: SigningKeysOptions): SigningKeys {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const ed25519Alg = options.ed25519Alg ?? "EdDSA";
  const cacheMs = (options.cacheSeconds ?? 300) * 1000;
  const keys = new Map<string, ActiveKey>();
  const noted = new Map<string, number>();

  const jwsAlg = (alg: SigningAlgorithm): JwsAlgorithm =>
    alg === "Ed25519" ? ed25519Alg : "ES256";

  const add = (
    owner: SigningKeyOwner,
    alg: SigningAlgorithm,
  ): AsyncResult<CreatedSigningKey> =>
    run(() => generateSigningKey(alg)).andThen((generated) =>
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
          keys.delete(`${owner.type}:${owner.id}`);

          return {
            kid: generated.kid,
            alg,
            publicKey: generated.publicKey,
            retired: typeof row["retired"] === "string" ? row["retired"] : null,
          };
        },
      ),
    );

  const stored = (
    owner: SigningKeyOwner,
  ): AsyncResult<{
    readonly kid: string;
    readonly alg: SigningAlgorithm;
    readonly privateKey: string;
  } | null> =>
    call("signing_key", ownerArgs(owner), (value) => {
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

  const active = (
    owner: SigningKeyOwner,
    create: SigningAlgorithm | undefined,
  ): AsyncResult<ActiveKey> => {
    const cacheKey = `${owner.type}:${owner.id}`;
    const cached = keys.get(cacheKey);

    if (cached && Date.now() - cached.at < cacheMs) {
      return AsyncResult.ok(cached);
    }

    return stored(owner).andThen((found) => {
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

      return add(owner, create).andThen(() => active(owner, undefined));
    });
  };

  const noteExp: SigningKeys["noteExp"] = (kid, exp) =>
    call(
      "note_signing_key_exp",
      { kid, exp: exp.toString() },
      (value) => value === true,
    );

  const client: SigningKeys = {
    create: (owner, alg = "Ed25519") => add(owner, alg),
    rotate: (owner, alg) =>
      alg === undefined
        ? stored(owner).andThen((found) => add(owner, found?.alg ?? "Ed25519"))
        : add(owner, alg),
    retire: (kid) =>
      call("retire_signing_key", { kid }, (value) => {
        for (const [owner, entry] of keys) {
          if (entry.kid === kid) {
            keys.delete(owner);
          }
        }

        return value === true;
      }),
    noteExp,
    jwks: (owner, jwksOptions = {}) =>
      call(
        "signing_jwks",
        { ...ownerArgs(owner), grace: interval(jwksOptions.grace) },
        jwksOf,
      ),
    jwksResponse: async (owner, responseOptions = {}) => {
      const result = await client.jwks(owner, responseOptions);

      if (!result.ok) {
        return Response.json(
          { title: "The key set is unavailable", status: 503 },
          {
            status: 503,
            headers: { "content-type": "application/problem+json" },
          },
        );
      }

      return Response.json(result.data, {
        headers: {
          "content-type": "application/jwk-set+json",
          "cache-control": `public, max-age=${String(responseOptions.maxAge ?? 300)}`,
        },
      });
    },
    remove: (owner) =>
      call("delete_signing_keys", ownerArgs(owner), (value) => {
        keys.delete(`${owner.type}:${owner.id}`);

        return Number(value);
      }),
    purge: (purgeOptions = {}) =>
      call(
        "purge_signing_keys",
        { grace: interval(purgeOptions.grace) },
        Number,
      ),
    signer: (owner, signerOptions = {}) => ({
      owner,
      sign: (data) =>
        active(owner, signerOptions.create).andThen((key) =>
          run(async () => ({
            kid: key.kid,
            alg: jwsAlg(key.alg),
            signature: await signBytes(key.key, key.alg, data),
          })),
        ),
      signJwt: (claims, header = {}) => {
        const typ = header["typ"];

        if (
          typ !== undefined &&
          (typeof typ !== "string" || !JWT_TYPE.test(typ))
        ) {
          return AsyncResult.err(
            dbError("invalid_input", "The typ header is not a JWT media type", {
              hint: "SIGNING_TYP_INVALID",
            }),
          );
        }

        return active(owner, signerOptions.create).andThen((key) => {
          const exp = claims["exp"];

          // Noting the exp rounded up to the hour keeps the calls to one per key per hour.
          const until =
            typeof exp === "number" && Number.isFinite(exp)
              ? Math.ceil(exp / HOUR) * HOUR
              : undefined;

          const note =
            until !== undefined && until > (noted.get(key.kid) ?? 0)
              ? noteExp(
                  key.kid,
                  temporal().Instant.fromEpochMilliseconds(until * 1000),
                ).map((known) => {
                  noted.set(key.kid, until);

                  return known;
                })
              : AsyncResult.ok(true);

          return note.andThen(() =>
            run(() =>
              signCompact(
                key.key,
                key.alg,
                { alg: jwsAlg(key.alg), kid: key.kid, typ: "JWT", ...header },
                claims,
              ),
            ),
          );
        });
      },
    }),
  };

  return withBlockHooks(client, options.hooks, {
    block: "signing-keys",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
