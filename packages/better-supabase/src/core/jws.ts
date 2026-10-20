import { fromBase64, toBase64Url } from "./base64.ts";
import { isRecord } from "./guards.ts";

// Created on first use: not every runtime has the globals at import time.
let encoderInstance: InstanceType<typeof TextEncoder> | undefined;
let decoderInstance: InstanceType<typeof TextDecoder> | undefined;

const encoder = {
  encode: (text: string): Uint8Array<ArrayBuffer> =>
    (encoderInstance ??= new TextEncoder()).encode(text),
};

const decoder = {
  decode: (bytes: Uint8Array): string =>
    (decoderInstance ??= new TextDecoder()).decode(bytes),
};

/** The key types a signing key can have. */
export type SigningAlgorithm = "Ed25519" | "ES256";

/**
 * The JWS `alg` a key signs with: `ES256`, or for an Ed25519 key `EdDSA`
 * (RFC 8037) or the fully specified `Ed25519` (RFC 9864). `RS256` and
 * `PS256` (RSA, 2048 bits or more) only verify, and only when a caller
 * lists them in `algorithms`.
 */
export type JwsAlgorithm = "EdDSA" | "Ed25519" | "ES256" | "PS256" | "RS256";

/** A public or private JSON Web Key (RFC 7517): Ed25519, P-256, or a public RSA key. */
export interface Jwk {
  readonly kty: string;
  readonly crv?: string;
  readonly x?: string;
  readonly y?: string;
  readonly n?: string;
  readonly e?: string;
  readonly d?: string;
  readonly kid?: string;
  readonly alg?: string;
  readonly use?: string;
  readonly [member: string]: unknown;
}

/** A JWK Set (RFC 7517 section 5). */
export interface Jwks {
  readonly keys: readonly Jwk[];
}

// Typed from `crypto.subtle`, because `CryptoKey` is a value only under @types/node without the DOM lib.
/** A WebCrypto key, as `crypto.subtle.importKey` returns it. */
export type SigningCryptoKey = Awaited<
  ReturnType<typeof crypto.subtle.importKey>
>;

const EC = { name: "ECDSA", namedCurve: "P-256" } as const;

/** The members WebCrypto imports, without `kid`, `alg` and other extras. */
function keyMaterial(
  jwk: Jwk,
  alg: SigningAlgorithm,
  withPrivate: boolean,
): { kty: string; crv: string; x: string; y?: string; d?: string } {
  const key = publicJwk(jwk);

  return {
    kty: key.kty,
    crv: String(key.crv),
    x: String(key.x),
    ...(alg === "ES256" ? { y: String(key.y) } : {}),
    ...(withPrivate ? { d: String(jwk.d) } : {}),
  };
}

const importParams = (alg: SigningAlgorithm) =>
  alg === "Ed25519" ? { name: "Ed25519" } : EC;

const signParams = (alg: SigningAlgorithm) =>
  alg === "Ed25519" ? { name: "Ed25519" } : { name: "ECDSA", hash: "SHA-256" };

/** A key type `verifyCompact` checks signatures with. */
type VerifyAlgorithm = SigningAlgorithm | "PS256" | "RS256";

/** The key type behind a JWS `alg`, or undefined for one this module doesn't verify. */
function keyAlgorithmOf(alg: string): VerifyAlgorithm | undefined {
  if (alg === "ES256" || alg === "RS256" || alg === "PS256") {
    return alg;
  }

  if (alg === "EdDSA" || alg === "Ed25519") {
    return "Ed25519";
  }

  return undefined;
}

/** RFC 7518 section 3.3: an RSA key for RS256 or PS256 has at least 2048 bits. */
const RSA_MIN_BYTES = 256;

function isRsaKey(jwk: Jwk): boolean {
  if (jwk.kty !== "RSA" || typeof jwk.n !== "string") {
    return false;
  }

  try {
    const modulus = fromBase64(jwk.n);
    const leadingZero = modulus[0] === 0 ? 1 : 0;

    return (
      typeof jwk.e === "string" && modulus.length - leadingZero >= RSA_MIN_BYTES
    );
  } catch {
    return false;
  }
}

/** Whether `jwk` can verify a JWS of key type `alg`. */
function verifiesWith(jwk: Jwk, alg: VerifyAlgorithm, name: string): boolean {
  if (alg === "RS256" || alg === "PS256") {
    return isRsaKey(jwk) && (jwk.alg === undefined || jwk.alg === name);
  }

  return jwkAlgorithm(jwk) === alg;
}

const RSA_PARAMS = {
  RS256: { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
  PS256: { name: "RSA-PSS", hash: "SHA-256" },
} as const;

const verifyParams = (alg: VerifyAlgorithm) => {
  switch (alg) {
    case "RS256": {
      return { name: "RSASSA-PKCS1-v1_5" };
    }

    case "PS256": {
      return { name: "RSA-PSS", saltLength: 32 };
    }

    case "Ed25519":
    case "ES256": {
      return signParams(alg);
    }

    default: {
      const exhaustive: never = alg;

      return exhaustive;
    }
  }
};

/** The key type of a JWK: `OKP`/`Ed25519` or `EC`/`P-256`. */
function jwkAlgorithm(jwk: Jwk): SigningAlgorithm | undefined {
  if (jwk.kty === "OKP" && jwk.crv === "Ed25519") {
    return "Ed25519";
  }

  if (jwk.kty === "EC" && jwk.crv === "P-256") {
    return "ES256";
  }

  return undefined;
}

/** The public members of `jwk`, without `d` and other private parts. */
export function publicJwk(jwk: Jwk): Jwk {
  const alg = jwkAlgorithm(jwk);

  if (alg === "Ed25519") {
    return { kty: "OKP", crv: "Ed25519", x: String(jwk.x) };
  }

  if (alg === "ES256") {
    return { kty: "EC", crv: "P-256", x: String(jwk.x), y: String(jwk.y) };
  }

  throw new TypeError("Only Ed25519 and P-256 keys are supported");
}

/** The RFC 7638 SHA-256 thumbprint of a key, base64url: a stable `kid`. */
export async function jwkThumbprint(jwk: Jwk): Promise<string> {
  const key = publicJwk(jwk);

  // RFC 7638: the required members only, in lexicographic order, no whitespace.
  const canonical =
    key.kty === "OKP"
      ? `{"crv":"${key.crv}","kty":"OKP","x":"${key.x}"}`
      : `{"crv":"${key.crv}","kty":"EC","x":"${key.x}","y":"${key.y}"}`;

  const digest = await crypto.subtle.digest(
    "SHA-256",
    encoder.encode(canonical),
  );

  return toBase64Url(new Uint8Array(digest));
}

/** A new key pair as JWKs, with the RFC 7638 thumbprint as `kid`. */
export async function generateSigningKey(alg: SigningAlgorithm): Promise<{
  readonly kid: string;
  readonly publicKey: Jwk;
  readonly privateKey: Jwk;
}> {
  const pair = await crypto.subtle.generateKey(importParams(alg), true, [
    "sign",
    "verify",
  ]);

  if (!("privateKey" in pair)) {
    throw new TypeError("WebCrypto returned a single key, not a key pair");
  }

  // SAFETY: exportKey("jwk") returns a JsonWebKey, which Jwk describes.
  const privateKey = (await crypto.subtle.exportKey(
    "jwk",
    pair.privateKey,
  )) as Jwk;

  const kid = await jwkThumbprint(privateKey);

  return { kid, publicKey: publicJwk(privateKey), privateKey };
}

/** Imports the private JWK of an Ed25519 or P-256 key for signing. */
export function importSigningKey(jwk: Jwk): Promise<SigningCryptoKey> {
  const alg = jwkAlgorithm(jwk);

  if (alg === undefined || typeof jwk.d !== "string") {
    throw new TypeError("A signing key is a private Ed25519 or P-256 JWK");
  }

  return crypto.subtle.importKey(
    "jwk",
    keyMaterial(jwk, alg, true),
    importParams(alg),
    false,
    ["sign"],
  );
}

/** Imports the public JWK of a key whose type `verifiesWith` already matched to `alg`. */
function importVerifyKey(
  jwk: Jwk,
  alg: VerifyAlgorithm,
): Promise<SigningCryptoKey> {
  if (alg === "RS256" || alg === "PS256") {
    return crypto.subtle.importKey(
      "jwk",
      { kty: "RSA", n: String(jwk.n), e: String(jwk.e) },
      RSA_PARAMS[alg],
      false,
      ["verify"],
    );
  }

  return crypto.subtle.importKey(
    "jwk",
    keyMaterial(jwk, alg, false),
    importParams(alg),
    false,
    ["verify"],
  );
}

/** The raw signature of `data`: 64 bytes for Ed25519, `r || s` for ES256 (as JWS needs). */
export async function signBytes(
  key: SigningCryptoKey,
  alg: SigningAlgorithm,
  data: Uint8Array,
): Promise<Uint8Array> {
  return new Uint8Array(
    // oxlint-disable-next-line unicorn/prefer-spread -- the copy must stay a Uint8Array on its own ArrayBuffer
    await crypto.subtle.sign(signParams(alg), key, data.slice()),
  );
}

/** A compact JWS (RFC 7515) over the JSON `payload`. */
export async function signCompact(
  key: SigningCryptoKey,
  alg: SigningAlgorithm,
  header: Readonly<Record<string, unknown>>,
  payload: unknown,
): Promise<string> {
  const input = `${toBase64Url(JSON.stringify(header))}.${toBase64Url(JSON.stringify(payload))}`;
  const signature = await signBytes(key, alg, encoder.encode(input));

  return `${input}.${toBase64Url(signature)}`;
}

/** What `verifyCompact` returns for a valid token. */
export interface VerifiedJws {
  readonly header: Readonly<Record<string, unknown>>;
  readonly payload: Readonly<Record<string, unknown>>;
}

export interface VerifyCompactOptions {
  /** The `alg` values accepted. Default: `EdDSA`, `Ed25519` and `ES256`. */
  readonly algorithms?: readonly JwsAlgorithm[];
  /** The `typ` header the token must carry, compared case-insensitively. */
  readonly typ?: string;
}

/** Why a token failed `verifyCompact`. */
export class JwsError extends Error {
  readonly code: string;
  constructor(code: string, message: string) {
    super(message);
    this.name = "JwsError";
    this.code = code;
  }
}

function part(text: string | undefined): Record<string, unknown> {
  if (text === undefined) {
    throw new JwsError("JWS_MALFORMED", "Not a JWS");
  }

  let value: unknown;

  try {
    value = JSON.parse(decoder.decode(fromBase64(text)));
  } catch {
    throw new JwsError("JWS_MALFORMED", "A JWS part is not base64url JSON");
  }

  if (!isRecord(value)) {
    throw new JwsError("JWS_MALFORMED", "A JWS part is not a JSON object");
  }

  return value;
}

/**
 * Verifies a compact JWS against `jwks`: the header's `kid` picks the key
 * (or the only key of the matching type when there is no `kid`). Throws a
 * `JwsError`; checks no claims, which are the caller's to read.
 */
export async function verifyCompact(
  token: string,
  jwks: Jwks,
  options: VerifyCompactOptions = {},
): Promise<VerifiedJws> {
  const pieces = token.split(".");

  if (pieces.length !== 3) {
    throw new JwsError("JWS_MALFORMED", "A compact JWS has three parts");
  }

  const header = part(pieces[0]);
  const payload = part(pieces[1]);
  const alg = typeof header["alg"] === "string" ? header["alg"] : "";
  const allowed = options.algorithms ?? ["EdDSA", "Ed25519", "ES256"];
  const keyAlg = keyAlgorithmOf(alg);

  if (keyAlg === undefined || !allowed.some((name) => name === alg)) {
    throw new JwsError("JWS_ALG", `The alg ${alg || "(none)"} is not accepted`);
  }

  if (
    options.typ !== undefined &&
    (typeof header["typ"] !== "string" ||
      header["typ"].toLowerCase() !== options.typ.toLowerCase())
  ) {
    throw new JwsError("JWS_TYP", `The typ must be ${options.typ}`);
  }

  const kid = typeof header["kid"] === "string" ? header["kid"] : undefined;

  const candidates = jwks.keys.filter(
    (jwk) =>
      verifiesWith(jwk, keyAlg, alg) && (kid === undefined || jwk.kid === kid),
  );

  const jwk = candidates.length === 1 ? candidates[0] : undefined;

  if (jwk === undefined) {
    throw new JwsError("JWS_KEY", `No key matches kid ${kid ?? "(none)"}`);
  }

  const valid = await crypto.subtle.verify(
    verifyParams(keyAlg),
    await importVerifyKey(jwk, keyAlg),
    fromBase64(pieces[2] ?? ""),
    encoder.encode(`${pieces[0]}.${pieces[1]}`),
  );

  if (!valid) {
    throw new JwsError("JWS_SIGNATURE", "The signature is invalid");
  }

  return { header, payload };
}

export interface JwksOfOptions {
  /** Keep RSA keys of 2048 bits or more too, for `RS256` and `PS256`. */
  readonly rsa?: boolean;
}

function isJwkCandidate(value: unknown): value is Jwk {
  return isRecord(value) && typeof value["kty"] === "string";
}

/** Parses a JWK Set, keeping only the Ed25519 and P-256 keys (and RSA keys with `rsa`). */
export function jwksOf(value: unknown, options: JwksOfOptions = {}): Jwks {
  const keys =
    isRecord(value) && Array.isArray(value["keys"]) ? value["keys"] : [];

  return {
    keys: keys.filter(
      (key): key is Jwk =>
        isJwkCandidate(key) &&
        (jwkAlgorithm(key) !== undefined ||
          (options.rsa === true && isRsaKey(key))),
    ),
  };
}
