import { fromBase64, toBase64Url } from "./base64.ts";
import { isRecord } from "./guards.ts";

const encoder = /* @__PURE__ */ new TextEncoder();
const decoder = /* @__PURE__ */ new TextDecoder();

/** The key types a signing key can have. */
export type SigningAlgorithm = "Ed25519" | "ES256";

/**
 * The JWS `alg` a key signs with: `ES256`, or for an Ed25519 key `EdDSA`
 * (RFC 8037) or the fully specified `Ed25519` (RFC 9864).
 */
export type JwsAlgorithm = "EdDSA" | "Ed25519" | "ES256";

/** A public or private JSON Web Key (RFC 7517) of an Ed25519 or P-256 key. */
export interface Jwk {
  readonly kty: string;
  readonly crv?: string;
  readonly x?: string;
  readonly y?: string;
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

/** The key type behind a JWS `alg`, or undefined for one this module doesn't verify. */
function keyAlgorithmOf(alg: string): SigningAlgorithm | undefined {
  if (alg === "ES256") return "ES256";
  if (alg === "EdDSA" || alg === "Ed25519") return "Ed25519";
  return undefined;
}

/** The key type of a JWK: `OKP`/`Ed25519` or `EC`/`P-256`. */
function jwkAlgorithm(jwk: Jwk): SigningAlgorithm | undefined {
  if (jwk.kty === "OKP" && jwk.crv === "Ed25519") return "Ed25519";
  if (jwk.kty === "EC" && jwk.crv === "P-256") return "ES256";
  return undefined;
}

/** The public members of `jwk`, without `d` and other private parts. */
export function publicJwk(jwk: Jwk): Jwk {
  const alg = jwkAlgorithm(jwk);
  if (alg === "Ed25519")
    return { kty: "OKP", crv: "Ed25519", x: String(jwk.x) };
  if (alg === "ES256")
    return { kty: "EC", crv: "P-256", x: String(jwk.x), y: String(jwk.y) };
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

/** Imports the public JWK of a key whose type `jwkAlgorithm` already gave as `alg`. */
function importVerifyKey(
  jwk: Jwk,
  alg: SigningAlgorithm,
): Promise<SigningCryptoKey> {
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
  if (text === undefined) throw new JwsError("JWS_MALFORMED", "Not a JWS");
  let value: unknown;
  try {
    value = JSON.parse(decoder.decode(fromBase64(text)));
  } catch {
    throw new JwsError("JWS_MALFORMED", "A JWS part is not base64url JSON");
  }
  if (!isRecord(value))
    throw new JwsError("JWS_MALFORMED", "A JWS part is not a JSON object");
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
  if (pieces.length !== 3)
    throw new JwsError("JWS_MALFORMED", "A compact JWS has three parts");
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
      jwkAlgorithm(jwk) === keyAlg && (kid === undefined || jwk.kid === kid),
  );
  const jwk = candidates.length === 1 ? candidates[0] : undefined;
  if (jwk === undefined) {
    throw new JwsError("JWS_KEY", `No key matches kid ${kid ?? "(none)"}`);
  }
  const valid = await crypto.subtle.verify(
    signParams(keyAlg),
    await importVerifyKey(jwk, keyAlg),
    fromBase64(pieces[2] ?? ""),
    encoder.encode(`${pieces[0]}.${pieces[1]}`),
  );
  if (!valid) throw new JwsError("JWS_SIGNATURE", "The signature is invalid");
  return { header, payload };
}

/** Parses a JWK Set, keeping only the Ed25519 and P-256 keys. */
export function jwksOf(value: unknown): Jwks {
  const keys =
    isRecord(value) && Array.isArray(value["keys"]) ? value["keys"] : [];
  return {
    keys: keys.filter(
      (key): key is Jwk =>
        isRecord(key) &&
        typeof key["kty"] === "string" &&
        // SAFETY: kty is a string, so key is a JWK candidate for jwkAlgorithm.
        jwkAlgorithm(key as Jwk) !== undefined,
    ),
  };
}
