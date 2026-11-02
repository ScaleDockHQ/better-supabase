import type { Jwk, Jwks } from "../core/jws.ts";
import type { CredentialSigner } from "./shared.ts";

import { base64ToText, decodeJwtHeader, toBase64Url } from "../core/base64.ts";
import { isList, isRecord } from "../core/guards.ts";
import { JwsError, verifyCompact } from "../core/jws.ts";
import {
  CredentialError,
  epochSeconds,
  randomUrl,
  sha256Url,
  signJws,
} from "./shared.ts";

/** The JWS `typ` of an SD-JWT VC (draft-ietf-oauth-sd-jwt-vc). */
export const SD_JWT_VC_TYP = "dc+sd-jwt";

/** The JWS `typ` of a key binding JWT (RFC 9901 section 4.3). */
export const KEY_BINDING_TYP = "kb+jwt";

const RESERVED = new Set([
  "_sd",
  "_sd_alg",
  "iss",
  "iat",
  "nbf",
  "exp",
  "vct",
  "sub",
  "cnf",
  "status",
  "...",
]);

/** Where a credential's revocation bit lives (Token Status List `status_list`). */
export interface StatusReference {
  readonly idx: number;
  readonly uri: string;
}

export interface IssueSdJwtOptions {
  readonly signer: CredentialSigner;
  /** The `iss` claim: the issuer identifier URL. */
  readonly issuer: string;
  /**
   * The credential type, such as
   * `https://example.com/credentials/qualification`.
   */
  readonly vct: string;
  /** The claims, without the registered ones this function sets. */
  readonly claims: Readonly<Record<string, unknown>>;
  /** The top-level claim names a holder discloses one by one. */
  readonly disclosable?: readonly string[];
  /** How many decoy digests to add, to hide how many claims are selective. */
  readonly decoys?: number;
  /** The holder's public key, written as `cnf.jwk` for key binding. */
  readonly holderKey?: Jwk;
  readonly subject?: string;
  readonly status?: StatusReference;
  readonly issuedAt?: Temporal.Instant;
  readonly notBefore?: Temporal.Instant;
  readonly expiresAt?: Temporal.Instant;
}

const digestOf = (disclosure: string): Promise<string> => sha256Url(disclosure);

/**
 * An SD-JWT VC (RFC 9901) in its combined issuance format,
 * `<jwt>~<disclosure>~...~`. Each name in `disclosable` becomes a salted
 * disclosure and a digest in `_sd`, hashed with SHA-256.
 */
export async function issueSdJwt(options: IssueSdJwtOptions): Promise<string> {
  const disclosable = new Set(options.disclosable);
  const plain: Record<string, unknown> = {};
  const disclosures: string[] = [];
  const digests: string[] = [];

  for (const name of Object.keys(options.claims)) {
    if (RESERVED.has(name)) {
      throw new TypeError(`The claim ${name} is set by issueSdJwt`);
    }
  }

  for (const name of disclosable) {
    if (!(name in options.claims)) {
      throw new TypeError(`The disclosable claim ${name} is not in claims`);
    }
  }

  for (const [name, value] of Object.entries(options.claims)) {
    if (disclosable.has(name)) {
      const disclosure = toBase64Url(
        JSON.stringify([randomUrl(16), name, value]),
      );

      disclosures.push(disclosure);
      digests.push(await digestOf(disclosure));
    } else {
      plain[name] = value;
    }
  }

  for (let count = 0; count < (options.decoys ?? 0); count += 1) {
    digests.push(await digestOf(randomUrl(16)));
  }

  // The digests are sorted so their order says nothing about the claims.
  digests.sort();

  const payload: Record<string, unknown> = {
    iss: options.issuer,
    iat: epochSeconds(options.issuedAt),
    ...(options.notBefore === undefined
      ? {}
      : { nbf: epochSeconds(options.notBefore) }),
    ...(options.expiresAt === undefined
      ? {}
      : { exp: epochSeconds(options.expiresAt) }),
    vct: options.vct,
    ...(options.subject === undefined ? {} : { sub: options.subject }),
    ...(options.holderKey === undefined
      ? {}
      : { cnf: { jwk: options.holderKey } }),
    ...(options.status === undefined
      ? {}
      : { status: { status_list: options.status } }),
    ...plain,
    ...(digests.length > 0 ? { _sd: digests, _sd_alg: "sha-256" } : {}),
  };

  const jwt = await signJws(options.signer, { typ: SD_JWT_VC_TYP }, payload);

  return `${[jwt, ...disclosures].join("~")}~`;
}

/** One disclosure of an SD-JWT, decoded. */
export interface Disclosure {
  readonly encoded: string;
  readonly salt: string;
  readonly name: string;
  readonly value: unknown;
}

/** An SD-JWT split into its parts; nothing is verified. */
export interface ParsedSdJwt {
  readonly jwt: string;
  readonly disclosures: readonly Disclosure[];
  /** The key binding JWT of a presentation. */
  readonly keyBinding?: string;
}

function decodeDisclosure(encoded: string): Disclosure {
  let parsed: unknown;

  try {
    parsed = JSON.parse(base64ToText(encoded));
  } catch {
    throw new CredentialError(
      "SD_JWT_DISCLOSURE",
      "A disclosure is not base64url JSON",
    );
  }

  if (
    !isList(parsed) ||
    parsed.length !== 3 ||
    typeof parsed[0] !== "string" ||
    typeof parsed[1] !== "string"
  ) {
    throw new CredentialError(
      "SD_JWT_DISCLOSURE",
      "A disclosure is a [salt, name, value] array",
    );
  }

  if (RESERVED.has(parsed[1])) {
    throw new CredentialError(
      "SD_JWT_DISCLOSURE",
      `A disclosure cannot name ${parsed[1]}`,
    );
  }

  return { encoded, salt: parsed[0], name: parsed[1], value: parsed[2] };
}

/** Splits `<jwt>~<disclosure>~...~[<kb-jwt>]` without checking any signature. */
export function parseSdJwt(token: string): ParsedSdJwt {
  const parts = token.split("~");

  if (parts.length < 2 || !parts[0]) {
    throw new CredentialError(
      "SD_JWT_MALFORMED",
      "An SD-JWT is a JWT followed by ~ and its disclosures",
    );
  }

  const last = parts.at(-1);

  return {
    jwt: parts[0],
    disclosures: parts.slice(1, -1).map(decodeDisclosure),
    ...(last ? { keyBinding: last } : {}),
  };
}

export interface KeyBindingOptions {
  /** The holder's key; its public half is the credential's `cnf.jwk`. */
  readonly signer: CredentialSigner;
  /** The verifier's client identifier, as the presentation request sent it. */
  readonly audience: string;
  readonly nonce: string;
  readonly issuedAt?: Temporal.Instant;
}

export interface PresentSdJwtOptions {
  /** The disclosable claim names to reveal; the others stay hidden. */
  readonly reveal: readonly string[];
  readonly keyBinding?: KeyBindingOptions;
}

/**
 * A presentation of an issued SD-JWT: only the disclosures named in `reveal`,
 * and with `keyBinding` a `kb+jwt` over the presentation's hash.
 */
export async function presentSdJwt(
  token: string,
  options: PresentSdJwtOptions,
): Promise<string> {
  const parsed = parseSdJwt(token);
  const reveal = new Set(options.reveal);

  const kept = parsed.disclosures
    .filter((item) => reveal.has(item.name))
    .map((item) => item.encoded);

  const presentation = `${[parsed.jwt, ...kept].join("~")}~`;

  if (options.keyBinding === undefined) {
    return presentation;
  }

  const binding = await signJws(
    options.keyBinding.signer,
    { typ: KEY_BINDING_TYP },
    {
      iat: epochSeconds(options.keyBinding.issuedAt),
      aud: options.keyBinding.audience,
      nonce: options.keyBinding.nonce,
      sd_hash: await sha256Url(presentation),
    },
  );

  return presentation + binding;
}

export interface VerifySdJwtOptions {
  /** The issuer's keys. */
  readonly jwks: Jwks;
  readonly now?: Temporal.Instant;
  /** Seconds of clock skew allowed on `exp`, `nbf` and the key binding `iat`. */
  readonly leewaySeconds?: number;
  /** Fails unless the credential has this `vct`. */
  readonly vct?: string;
  /** Fails unless a valid key binding JWT is there. */
  readonly requireKeyBinding?: boolean;
  /** The `aud` the key binding JWT must carry. */
  readonly audience?: string;
  /** The `nonce` the key binding JWT must carry. */
  readonly nonce?: string;
}

export interface VerifiedSdJwt {
  readonly header: Readonly<Record<string, unknown>>;
  /** The signed payload, with `_sd` as the issuer wrote it. */
  readonly payload: Readonly<Record<string, unknown>>;
  /** The payload with every disclosed claim restored and `_sd` removed. */
  readonly claims: Readonly<Record<string, unknown>>;
  /** The names of the claims the presentation discloses. */
  readonly disclosed: readonly string[];
  readonly keyBound: boolean;
}

const bindingKey = (
  payload: Readonly<Record<string, unknown>>,
): Jwk | undefined => {
  const cnf = payload["cnf"];

  if (isRecord(cnf) && isRecord(cnf["jwk"])) {
    // SAFETY: cnf.jwk is a JSON object; verifyCompact checks the members it uses.
    return cnf["jwk"] as Jwk;
  }

  return undefined;
};

/**
 * Verifies the issuer signature, the digests and, when present, the key
 * binding.
 */
export async function verifySdJwt(
  token: string,
  options: VerifySdJwtOptions,
): Promise<VerifiedSdJwt> {
  const parsed = parseSdJwt(token);
  const leeway = options.leewaySeconds ?? 0;
  const now = epochSeconds(options.now);

  let header: Readonly<Record<string, unknown>>;
  let payload: Readonly<Record<string, unknown>>;

  try {
    ({ header, payload } = await verifyCompact(parsed.jwt, options.jwks, {
      typ: SD_JWT_VC_TYP,
    }));
  } catch (error) {
    throw error instanceof JwsError
      ? new CredentialError(error.code, error.message)
      : error;
  }

  if (typeof payload["iss"] !== "string") {
    throw new CredentialError("SD_JWT_CLAIMS", "The iss claim is missing");
  }

  if (typeof payload["vct"] !== "string") {
    throw new CredentialError("SD_JWT_CLAIMS", "The vct claim is missing");
  }

  if (options.vct !== undefined && payload["vct"] !== options.vct) {
    throw new CredentialError("SD_JWT_VCT", "The credential type differs");
  }

  if (typeof payload["exp"] === "number" && payload["exp"] + leeway <= now) {
    throw new CredentialError("SD_JWT_EXPIRED", "The credential has expired");
  }

  if (typeof payload["nbf"] === "number" && payload["nbf"] - leeway > now) {
    throw new CredentialError(
      "SD_JWT_NOT_YET",
      "The credential is not valid yet",
    );
  }

  if (payload["_sd_alg"] !== undefined && payload["_sd_alg"] !== "sha-256") {
    throw new CredentialError(
      "SD_JWT_ALG",
      "Only the sha-256 digest algorithm is supported",
    );
  }

  const listed = payload["_sd"];

  if (
    listed !== undefined &&
    !(isList(listed) && listed.every((item) => typeof item === "string"))
  ) {
    throw new CredentialError("SD_JWT_CLAIMS", "_sd is a list of digests");
  }

  const digests = new Set<string>(listed);
  const claims: Record<string, unknown> = {};

  for (const [name, value] of Object.entries(payload)) {
    if (name !== "_sd" && name !== "_sd_alg") {
      claims[name] = value;
    }
  }

  const seen = new Set<string>();

  for (const disclosure of parsed.disclosures) {
    const digest = await digestOf(disclosure.encoded);

    if (!digests.has(digest)) {
      throw new CredentialError(
        "SD_JWT_DISCLOSURE",
        `The disclosure of ${disclosure.name} matches no digest`,
      );
    }

    if (seen.has(digest) || disclosure.name in claims) {
      throw new CredentialError(
        "SD_JWT_DISCLOSURE",
        `The claim ${disclosure.name} is disclosed twice`,
      );
    }

    seen.add(digest);
    claims[disclosure.name] = disclosure.value;
  }

  const holderKey = bindingKey(payload);
  let keyBound = false;

  if (parsed.keyBinding !== undefined) {
    if (holderKey === undefined) {
      throw new CredentialError(
        "SD_JWT_KEY_BINDING",
        "The credential has no cnf.jwk to verify the key binding with",
      );
    }

    let binding: Readonly<Record<string, unknown>>;

    try {
      // cnf.jwk is the only key that may verify the binding, whatever kid it names.
      const kid = decodeJwtHeader(parsed.keyBinding)?.["kid"];

      ({ payload: binding } = await verifyCompact(
        parsed.keyBinding,
        {
          keys: [{ ...holderKey, ...(typeof kid === "string" ? { kid } : {}) }],
        },
        { typ: KEY_BINDING_TYP },
      ));
    } catch (error) {
      throw error instanceof JwsError
        ? new CredentialError("SD_JWT_KEY_BINDING", error.message)
        : error;
    }

    const presentation = token.slice(
      0,
      token.length - parsed.keyBinding.length,
    );

    if (binding["sd_hash"] !== (await sha256Url(presentation))) {
      throw new CredentialError(
        "SD_JWT_KEY_BINDING",
        "sd_hash does not match the presentation",
      );
    }

    if (options.audience !== undefined && binding["aud"] !== options.audience) {
      throw new CredentialError("SD_JWT_KEY_BINDING", "The audience differs");
    }

    if (options.nonce !== undefined && binding["nonce"] !== options.nonce) {
      throw new CredentialError("SD_JWT_KEY_BINDING", "The nonce differs");
    }

    if (typeof binding["iat"] !== "number" || binding["iat"] - leeway > now) {
      throw new CredentialError(
        "SD_JWT_KEY_BINDING",
        "The key binding iat is missing or in the future",
      );
    }

    keyBound = true;
  } else if (options.requireKeyBinding === true) {
    throw new CredentialError(
      "SD_JWT_KEY_BINDING",
      "The presentation has no key binding JWT",
    );
  }

  return {
    header,
    payload,
    claims,
    disclosed: parsed.disclosures.map((item) => item.name),
    keyBound,
  };
}
