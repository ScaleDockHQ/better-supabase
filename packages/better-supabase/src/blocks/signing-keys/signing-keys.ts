import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Jwk, Jwks, SigningAlgorithm } from "../../core/jws.ts";
import type { Logger } from "../../core/logger.ts";
import type { BlockOptions } from "../shared.ts";
import type {
  KeyProvider,
  Signature,
  SigningKeyOwner,
} from "./key-provider.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { jwksOf } from "../../core/jws.ts";
import { AsyncResult } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import { applyTemporal, blockCall } from "../shared.ts";
import {
  addSigningKey,
  forgetSigningKey,
  keyProviderOf,
  ownerArgs,
  storedSigningKey,
  vaultKeyProvider,
} from "./key-provider.ts";

export interface SigningKeysOptions extends BlockOptions {
  /**
   * The JWS `alg` an Ed25519 key signs with: `EdDSA` (RFC 8037), which most
   * verifiers read, or the fully specified `Ed25519` (RFC 9864). Default:
   * `EdDSA`.
   */
  readonly ed25519Alg?: "EdDSA" | "Ed25519";
  /** How long a signer keeps the imported private key, in seconds. Default: 300. */
  readonly cacheSeconds?: number;
  /**
   * Where signers get their keys. Default: `vaultKeyProvider(options)`, the
   * private keys in Supabase Vault (ADR 0033). With `vercelKmsKeyProvider` the
   * issuer's key set, which Vercel KMS publishes, is what verifiers fetch;
   * `create`, `rotate`, `retire`, `noteExp`, `jwks`, `jwksResponse`, `remove`
   * and `purge` keep managing the Vault keys only.
   */
  readonly keys?: KeyProvider;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<SigningKeys>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
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

/** Signs with an owner's active key, through the block's `keys` provider. */
export interface Signer {
  readonly owner: SigningKeyOwner;
  /** The raw signature of `data` with the active key. */
  sign(data: Uint8Array): AsyncResult<Signature>;
  /**
   * A compact JWS over `claims`, with `alg` and `kid` from the key provider and
   * `typ: "JWT"` in the header unless `header` sets it. A custom `typ` has to
   * be `JWT` or end in `+jwt` (see `jwtType`); anything else fails with
   * `SIGNING_TYP_INVALID`. With a provider that has `noteExp` (Vault), a
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
   * `SIGNING_KEY_MISSING`. A provider whose keys live elsewhere, such as Vercel
   * KMS, ignores it.
   */
  readonly create?: SigningAlgorithm;
}

export interface SigningKeys {
  /**
   * Generates a key for the owner and makes it active; the previous key is
   * retired.
   */
  create(input: {
    owner: SigningKeyOwner;
    alg?: SigningAlgorithm | undefined;
  }): AsyncResult<CreatedSigningKey>;
  /** `create` with the active key's type, or `alg` when given. */
  rotate(input: {
    owner: SigningKeyOwner;
    alg?: SigningAlgorithm | undefined;
  }): AsyncResult<CreatedSigningKey>;
  /** Retires a key without a replacement. `false` when it was not active. */
  retire(kid: string): AsyncResult<boolean>;
  /** Keeps a key published until at least `exp`. `false` for an unknown kid. */
  noteExp(input: { kid: string; exp: Temporal.Instant }): AsyncResult<boolean>;
  /** The owner's public keys still in use, as a JWK Set. */
  jwks(input: { owner: SigningKeyOwner } & JwksOptions): AsyncResult<Jwks>;
  /** `jwks` as an `application/jwk-set+json` response with `Cache-Control`. */
  jwksResponse(
    input: { owner: SigningKeyOwner } & JwksResponseOptions,
  ): Promise<Response>;
  /** Deletes every key of the owner. */
  remove(owner: SigningKeyOwner): AsyncResult<number>;
  /** Deletes retired keys no token can still need. */
  purge(options?: JwksOptions): AsyncResult<number>;
  signer(input: { owner: SigningKeyOwner } & SignerOptions): Signer;
}

const HOUR = 3600;

const interval = (duration: Temporal.Duration | undefined): string | null =>
  duration === undefined
    ? null
    : `${String(duration.total({ unit: "seconds" }))} seconds`;

/**
 * The `signing-keys` SQL module as typed calls: keys are generated and used
 * with WebCrypto here, kept in Supabase Vault there, unless `keys` signs
 * elsewhere. Service role only.
 */
export function createSigningKeys(options: SigningKeysOptions): SigningKeys {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const keys =
    options.keys === undefined
      ? vaultKeyProvider(options)
      : keyProviderOf(options.keys);

  const noted = new Map<string, number>();

  const add = (
    owner: SigningKeyOwner,
    alg: SigningAlgorithm,
  ): AsyncResult<CreatedSigningKey> =>
    addSigningKey(call, owner, alg).map((created) => {
      forgetSigningKey(keys, { owner });

      return created;
    });

  const noteExp: SigningKeys["noteExp"] = ({ kid, exp }) =>
    call(
      "note_signing_key_exp",
      { kid, exp: exp.toString() },
      (value) => value === true,
    );

  const client: SigningKeys = {
    create: ({ owner, alg = "Ed25519" }) => add(owner, alg),
    rotate: ({ owner, alg }) =>
      alg === undefined
        ? storedSigningKey(call, owner).andThen((found) =>
            add(owner, found?.alg ?? "Ed25519"),
          )
        : add(owner, alg),
    retire: (kid) =>
      call("retire_signing_key", { kid }, (value) => {
        forgetSigningKey(keys, { kid });

        return value === true;
      }),
    noteExp,
    jwks: ({ owner, ...jwksOptions }) =>
      call(
        "signing_jwks",
        { ...ownerArgs(owner), grace: interval(jwksOptions.grace) },
        jwksOf,
      ),
    jwksResponse: async ({ owner, ...responseOptions }) => {
      const result = await client.jwks({ owner, ...responseOptions });

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
        forgetSigningKey(keys, { owner });

        return Number(value);
      }),
    purge: (purgeOptions = {}) =>
      call(
        "purge_signing_keys",
        { grace: interval(purgeOptions.grace) },
        Number,
      ),
    signer: ({ owner, create }) => ({
      owner,
      sign: (data) => keys.sign({ owner, data, create }),
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

        return keys
          .signJwt({ owner, claims, header: { typ: "JWT", ...header }, create })
          .andThen((signed) => {
            const exp = claims["exp"];

            // Noting the exp rounded up to the hour keeps the calls to one per key per hour.
            const until =
              typeof exp === "number" && Number.isFinite(exp)
                ? Math.ceil(exp / HOUR) * HOUR
                : undefined;

            const note =
              keys.noteExp !== undefined &&
              until !== undefined &&
              until > (noted.get(signed.kid) ?? 0)
                ? keys
                    .noteExp({
                      kid: signed.kid,
                      exp: temporal().Instant.fromEpochMilliseconds(
                        until * 1000,
                      ),
                    })
                    .map((known) => {
                      noted.set(signed.kid, until);

                      return known;
                    })
                : AsyncResult.ok(true);

            return note.map(() => signed.token);
          });
      },
    }),
  };

  return withBlockHooks(client, options.hooks, {
    block: "signing-keys",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
