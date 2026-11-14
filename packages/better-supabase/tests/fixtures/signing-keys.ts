import type {
  BlockTransport,
  VercelKmsModule,
} from "../../src/blocks/signing-keys/index.ts";
import type { Jwks } from "../../src/core/jws.ts";

import {
  generateSigningKey,
  importSigningKey,
  signBytes,
  signCompact,
} from "../../src/core/jws.ts";

interface Row {
  owner: string;
  kid: string;
  alg: string;
  publicJwk: Record<string, unknown>;
  privateJwk: string;
  state: "active" | "retired";
}

export interface SigningKeysStore extends BlockTransport {
  readonly rows: Row[];
  readonly calls: [string, Record<string, unknown>][];
}

/** The signing-keys module in memory. */
export function signingKeysStore(): SigningKeysStore {
  const rows: Row[] = [];
  const calls: [string, Record<string, unknown>][] = [];

  const owner = (args: Record<string, unknown>) =>
    `${String(args["owner_type"])}:${String(args["owner_id"])}`;

  const fns: Record<string, (args: Record<string, unknown>) => unknown> = {
    add_signing_key(args) {
      const previous = rows.find(
        (row) => row.owner === owner(args) && row.state === "active",
      );

      if (previous) {
        previous.state = "retired";
      }

      rows.push({
        owner: owner(args),
        kid: String(args["kid"]),
        alg: String(args["alg"]),
        // SAFETY: the client sends the public JWK as an object.
        publicJwk: args["public_jwk"] as Record<string, unknown>,
        privateJwk: String(args["private_jwk"]),
        state: "active",
      });

      return {
        kid: args["kid"],
        alg: args["alg"],
        retired: previous?.kid ?? null,
      };
    },
    signing_key(args) {
      const row = rows.find(
        (item) => item.owner === owner(args) && item.state === "active",
      );

      return row
        ? { kid: row.kid, alg: row.alg, privateKey: row.privateJwk }
        : null;
    },
    signing_jwks(args) {
      return {
        keys: rows
          .filter((row) => row.owner === owner(args))
          .map((row) => ({ ...row.publicJwk, kid: row.kid, use: "sig" })),
      };
    },
    note_signing_key_exp: (args) => rows.some((row) => row.kid === args["kid"]),
    retire_signing_key(args) {
      const row = rows.find(
        (item) => item.kid === args["kid"] && item.state === "active",
      );

      if (row) {
        row.state = "retired";
      }

      return row !== undefined;
    },
    delete_signing_keys: () => 0,
    purge_signing_keys: () => 0,
  };

  return {
    rows,
    calls,
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push([fn, args]);
      const handler = fns[fn];

      if (!handler) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }

      return Promise.resolve(handler(args));
    },
  };
}

/** A `VercelKmsError` as `@vercel/kms` throws it. */
export class FakeKmsError extends Error {
  readonly status: number;
  readonly code: string;
  readonly metadata: Record<string, unknown>;

  constructor(status: number, code = "kms_error", metadata = {}) {
    super(`KMS answered ${String(status)}`);
    this.name = "VercelKmsError";
    this.status = status;
    this.code = code;
    this.metadata = metadata;
  }
}

export interface FakeKms {
  readonly kms: VercelKmsModule;
  /** The options of every call, in order. */
  readonly calls: readonly object[];
  /** The public key, as Vercel KMS publishes it for the issuer. */
  readonly jwks: Jwks;
  readonly kid: string;
  /** Makes every later call throw `error`. */
  fail(error: unknown): void;
}

/**
 * `@vercel/kms` in memory: one Ed25519 key that signs with WebCrypto and
 * reports `algorithm`.
 */
export async function fakeKms(algorithm = "EdDSA"): Promise<FakeKms> {
  const generated = await generateSigningKey("Ed25519");
  const key = await importSigningKey(generated.privateKey);
  const calls: object[] = [];
  let failure: unknown;

  const jwks: Jwks = { keys: [{ ...generated.publicKey, kid: generated.kid }] };

  const answer = <T>(options: object, value: () => Promise<T>) => {
    calls.push(options);

    if (failure !== undefined) {
      return Promise.reject(failure);
    }

    return value();
  };

  const kms = {
    signMessage: (options) =>
      answer(options, async () => ({
        signature: await signBytes(key, "Ed25519", options.message),
        keyId: generated.kid,
        algorithm,
        fingerprint: "SHA256:fake",
      })),
    signJWT: (options) =>
      answer(options, async () => ({
        token: await signCompact(
          key,
          "Ed25519",
          { ...options.headers, alg: algorithm, kid: generated.kid },
          options.ttl === null
            ? { ...options.claims }
            : { ...options.claims, exp: 1_900_000_000 + (options.ttl ?? 300) },
        ),
        keyId: generated.kid,
        algorithm,
        fingerprint: "SHA256:fake",
      })),
  } satisfies VercelKmsModule;

  return {
    kms,
    calls,
    jwks,
    kid: generated.kid,
    fail(error: unknown) {
      failure = error;
    },
  };
}
