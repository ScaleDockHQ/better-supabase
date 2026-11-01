import type { Jwk, Jwks } from "../core/jws.ts";
import type { CredentialSigner } from "./shared.ts";
import type { BitstringStatusEntry } from "./status-list.ts";

import { isList, isRecord } from "../core/guards.ts";
import { JwsError, verifyCompact } from "../core/jws.ts";
import { nowInstant } from "../core/temporal.ts";
import { CredentialError, signJws } from "./shared.ts";
import { VC_CONTEXT_V2 } from "./status-list.ts";

/** The JWS `typ` of a credential secured with VC-JOSE-COSE. */
export const VC_JWT_TYP = "vc+jwt";

export interface IssueJwtVcOptions {
  readonly signer: CredentialSigner;
  readonly issuer: string;
  /** The types after `VerifiableCredential`, such as `QualificationCredential`. */
  readonly types: readonly string[];
  /** The subject's claims; `id` is the holder's identifier, such as a `did:jwk`. */
  readonly subject: Readonly<Record<string, unknown>>;
  readonly id?: string;
  readonly validFrom?: Temporal.Instant;
  readonly validUntil?: Temporal.Instant;
  readonly status?: BitstringStatusEntry;
  /** Written as `cnf.jwk`, so the credential can be bound to the holder's key. */
  readonly holderKey?: Jwk;
}

/**
 * A W3C Verifiable Credential 2.0 secured as a JWT (VC-JOSE-COSE): the
 * credential is the JWT payload, with `typ: vc+jwt` and `cty: vc`.
 */
export function issueJwtVc(options: IssueJwtVcOptions): Promise<string> {
  return signJws(
    options.signer,
    { typ: VC_JWT_TYP, cty: "vc" },
    {
      "@context": [VC_CONTEXT_V2],
      ...(options.id === undefined ? {} : { id: options.id }),
      type: ["VerifiableCredential", ...options.types],
      issuer: options.issuer,
      validFrom: (options.validFrom ?? nowInstant()).toString(),
      ...(options.validUntil === undefined
        ? {}
        : { validUntil: options.validUntil.toString() }),
      credentialSubject: options.subject,
      ...(options.status === undefined
        ? {}
        : { credentialStatus: options.status }),
      ...(options.holderKey === undefined
        ? {}
        : { cnf: { jwk: options.holderKey } }),
    },
  );
}

export interface VerifiedJwtVc {
  readonly credential: Readonly<Record<string, unknown>>;
  readonly types: readonly string[];
  readonly issuer: string;
  readonly subject: Readonly<Record<string, unknown>>;
}

/** Verifies the signature and the validity window of a `vc+jwt` credential. */
export async function verifyJwtVc(
  token: string,
  options: { readonly jwks: Jwks; readonly now?: Temporal.Instant },
): Promise<VerifiedJwtVc> {
  let payload: Readonly<Record<string, unknown>>;

  try {
    ({ payload } = await verifyCompact(token, options.jwks, {
      typ: VC_JWT_TYP,
    }));
  } catch (error) {
    throw error instanceof JwsError
      ? new CredentialError(error.code, error.message)
      : error;
  }

  const context = payload["@context"];
  const types = payload["type"];
  const subject = payload["credentialSubject"];

  if (!isList(context) || context[0] !== VC_CONTEXT_V2) {
    throw new CredentialError(
      "VC_CONTEXT",
      `The first @context must be ${VC_CONTEXT_V2}`,
    );
  }

  if (
    !isList(types) ||
    !types.every((item) => typeof item === "string") ||
    !types.includes("VerifiableCredential")
  ) {
    throw new CredentialError(
      "VC_TYPE",
      "The type must include VerifiableCredential",
    );
  }

  const issuer = isRecord(payload["issuer"])
    ? payload["issuer"]["id"]
    : payload["issuer"];

  if (typeof issuer !== "string" || !isRecord(subject)) {
    throw new CredentialError(
      "VC_CLAIMS",
      "issuer and credentialSubject are required",
    );
  }

  const now = (options.now ?? nowInstant()).epochMilliseconds;

  for (const [member, after] of [
    ["validFrom", true],
    ["validUntil", false],
  ] as const) {
    const value = payload[member];

    if (value !== undefined) {
      const at = typeof value === "string" ? Date.parse(value) : Number.NaN;

      if (Number.isNaN(at)) {
        throw new CredentialError("VC_CLAIMS", `${member} is not a date-time`);
      }

      if (after ? at > now : at <= now) {
        throw new CredentialError(
          after ? "VC_NOT_YET" : "VC_EXPIRED",
          after
            ? "The credential is not valid yet"
            : "The credential has expired",
        );
      }
    }
  }

  return { credential: payload, types, issuer, subject };
}
