import type { Jwk, JwsAlgorithm } from "../core/jws.ts";

import { toBase64Url } from "../core/base64.ts";
import { importSigningKey, jwkAlgorithm, signBytes } from "../core/jws.ts";

/** A stable code on a failed verification or request, for `switch` and logs. */
export class CredentialError extends Error {
  readonly code: string;
  constructor(code: string, message: string) {
    super(message);
    this.name = "CredentialError";
    this.code = code;
  }
}

/**
 * Signs with one key. The `signing-keys` block's `Signer` becomes one through
 * `signerFromSigningKeys`; a holder key becomes one through `signerFromJwk`.
 */
export interface CredentialSigner {
  readonly alg: JwsAlgorithm;
  readonly kid?: string;
  /** The raw JWS signature: 64 bytes for Ed25519, `r || s` for ES256. */
  sign(data: Uint8Array): PromiseLike<Uint8Array>;
}

/** What the `signing-keys` block's `Signer.sign` resolves to once unwrapped. */
interface SigningKeysSignature {
  readonly kid: string;
  readonly alg: JwsAlgorithm;
  readonly signature: Uint8Array;
}

/** The part of the `signing-keys` `Signer` that `signerFromSigningKeys` uses. */
export interface SigningKeysSigner {
  sign(data: Uint8Array): { orThrow(): Promise<SigningKeysSignature> };
}

/**
 * Adapts the `signing-keys` block's `Signer`. A first signature over empty
 * bytes learns the active key's `kid` and `alg` for the JWS header; every later
 * signature has to come from that same key, or it throws, so a rotation between
 * header and signature never writes a token no key verifies.
 */
export async function signerFromSigningKeys(
  signer: SigningKeysSigner,
): Promise<CredentialSigner> {
  const probe = await signer.sign(new Uint8Array()).orThrow();

  return {
    alg: probe.alg,
    kid: probe.kid,
    async sign(data) {
      const signed = await signer.sign(data).orThrow();

      if (signed.kid !== probe.kid) {
        throw new CredentialError(
          "CREDENTIAL_KEY_ROTATED",
          "The signing key rotated while a credential was being signed",
        );
      }

      return signed.signature;
    },
  };
}

/** A signer over a private Ed25519 or P-256 JWK, such as a holder's key. */
export async function signerFromJwk(
  jwk: Jwk,
  kid?: string,
): Promise<CredentialSigner> {
  const alg = jwkAlgorithm(jwk);

  if (alg === undefined) {
    throw new TypeError("A signing key is a private Ed25519 or P-256 JWK");
  }

  const key = await importSigningKey(jwk);

  return {
    alg: alg === "ES256" ? "ES256" : "EdDSA",
    ...(kid === undefined ? {} : { kid }),
    sign: (data) => signBytes(key, alg, data),
  };
}

let encoder: InstanceType<typeof TextEncoder> | undefined;

function utf8(text: string): Uint8Array<ArrayBuffer> {
  return (encoder ??= new TextEncoder()).encode(text);
}

/** Base64url of the SHA-256 digest of the ASCII or UTF-8 `text`. */
export async function sha256Url(text: string): Promise<string> {
  return toBase64Url(
    new Uint8Array(await crypto.subtle.digest("SHA-256", utf8(text))),
  );
}

/** `bytes` random bytes as base64url. */
export function randomUrl(bytes = 16): string {
  return toBase64Url(crypto.getRandomValues(new Uint8Array(bytes)));
}

/** Seconds since the epoch of `instant`, or of now. */
export function epochSeconds(instant?: Temporal.Instant): number {
  return Math.floor(
    (instant ?? Temporal.Now.instant()).epochMilliseconds / 1000,
  );
}

/** A compact JWS over `payload`, signed by `signer`. */
export async function signJws(
  signer: CredentialSigner,
  header: Readonly<Record<string, unknown>>,
  payload: unknown,
): Promise<string> {
  const input = `${toBase64Url(
    JSON.stringify({
      ...header,
      alg: signer.alg,
      ...(signer.kid === undefined ? {} : { kid: signer.kid }),
    }),
  )}.${toBase64Url(JSON.stringify(payload))}`;

  return `${input}.${toBase64Url(await signer.sign(utf8(input)))}`;
}
