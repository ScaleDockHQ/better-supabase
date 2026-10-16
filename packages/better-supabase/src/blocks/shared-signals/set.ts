import type { AsyncResult } from "../../core/result.ts";
import type { Signer } from "../signing-keys/signing-keys.ts";

import { type Jwks, JwsError, verifyCompact } from "../../core/jws.ts";
import { isRecord } from "../shared.ts";

/** The `typ` header of a Security Event Token (RFC 8417 §2.3). */
export const SET_TYP = "secevent+jwt";
/** The media type a pushed SET is sent with (RFC 8935 §2). */
export const SET_CONTENT_TYPE = "application/secevent+jwt";

/** The SSF 1.0 stream events (§8.1.4, §8.1.5). */
export const SSF_EVENTS = {
  verification:
    "https://schemas.openid.net/secevent/ssf/event-type/verification",
  streamUpdated:
    "https://schemas.openid.net/secevent/ssf/event-type/stream-updated",
} as const;

/** The CAEP 1.0 event types (§3). */
export const CAEP_EVENTS = {
  sessionRevoked:
    "https://schemas.openid.net/secevent/caep/event-type/session-revoked",
  tokenClaimsChange:
    "https://schemas.openid.net/secevent/caep/event-type/token-claims-change",
  credentialChange:
    "https://schemas.openid.net/secevent/caep/event-type/credential-change",
  assuranceLevelChange:
    "https://schemas.openid.net/secevent/caep/event-type/assurance-level-change",
  deviceComplianceChange:
    "https://schemas.openid.net/secevent/caep/event-type/device-compliance-change",
  sessionEstablished:
    "https://schemas.openid.net/secevent/caep/event-type/session-established",
  sessionPresented:
    "https://schemas.openid.net/secevent/caep/event-type/session-presented",
  riskLevelChange:
    "https://schemas.openid.net/secevent/caep/event-type/risk-level-change",
} as const;

/** The RISC 1.0 event types (§2), without the deprecated `sessions-revoked`. */
export const RISC_EVENTS = {
  accountCredentialChangeRequired:
    "https://schemas.openid.net/secevent/risc/event-type/account-credential-change-required",
  accountPurged:
    "https://schemas.openid.net/secevent/risc/event-type/account-purged",
  accountDisabled:
    "https://schemas.openid.net/secevent/risc/event-type/account-disabled",
  accountEnabled:
    "https://schemas.openid.net/secevent/risc/event-type/account-enabled",
  identifierChanged:
    "https://schemas.openid.net/secevent/risc/event-type/identifier-changed",
  identifierRecycled:
    "https://schemas.openid.net/secevent/risc/event-type/identifier-recycled",
  credentialCompromise:
    "https://schemas.openid.net/secevent/risc/event-type/credential-compromise",
  optIn: "https://schemas.openid.net/secevent/risc/event-type/opt-in",
  optOutInitiated:
    "https://schemas.openid.net/secevent/risc/event-type/opt-out-initiated",
  optOutCancelled:
    "https://schemas.openid.net/secevent/risc/event-type/opt-out-cancelled",
  optOutEffective:
    "https://schemas.openid.net/secevent/risc/event-type/opt-out-effective",
  recoveryActivated:
    "https://schemas.openid.net/secevent/risc/event-type/recovery-activated",
  recoveryInformationChanged:
    "https://schemas.openid.net/secevent/risc/event-type/recovery-information-changed",
} as const;

/**
 * An SSF subject identifier (RFC 9493 and SSF §3): `{ format: "email",
 * email }`, `{ format: "iss_sub", iss, sub }`, `{ format: "opaque", id }`,
 * or a complex subject with `user`, `session`, `tenant` and other members.
 */
export type SubjectIdentifier = { readonly format: string } & Readonly<
  Record<string, unknown>
>;

/** One event: its type URI and its claims. */
export interface SecurityEvent {
  readonly type: string;
  readonly claims: Readonly<Record<string, unknown>>;
}

/** What signs a SET: a signing-keys `signer(owner)`, or anything with `signJwt`. */
export type SetSigner = Pick<Signer, "signJwt">;

export interface MintSetInput {
  readonly issuer: string;
  readonly audience: string | readonly string[];
  readonly subject: SubjectIdentifier;
  readonly event: SecurityEvent;
  /** Links SETs that describe the same change (SSF §4.1.7). */
  readonly txn?: string;
}

export interface MintedSet {
  readonly jti: string;
  readonly token: string;
}

/**
 * A signed SET (RFC 8417) with the SSF profile: `typ: secevent+jwt`, a
 * top-level `sub_id`, exactly one event, and no `sub` or `exp` claim.
 */
export function mintSet(
  signer: SetSigner,
  input: MintSetInput,
): AsyncResult<MintedSet> {
  const jti = crypto.randomUUID().replaceAll("-", "");
  const audience =
    typeof input.audience === "string"
      ? input.audience
      : input.audience.length === 1
        ? input.audience[0]
        : [...input.audience];
  return signer
    .signJwt(
      {
        iss: input.issuer,
        jti,
        iat: Math.floor(Date.now() / 1000),
        aud: audience,
        ...(input.txn === undefined ? {} : { txn: input.txn }),
        sub_id: input.subject,
        events: { [input.event.type]: input.event.claims },
      },
      { typ: SET_TYP },
    )
    .map((token) => ({ jti, token }));
}

/** The RFC 8935 §2.3 error codes a receiver answers with. */
export type SetErrorCode =
  | "invalid_request"
  | "invalid_key"
  | "invalid_issuer"
  | "invalid_audience"
  | "authentication_failed"
  | "access_denied";

export interface VerifiedSet {
  readonly jti: string;
  readonly issuer: string;
  /** Seconds since the epoch. */
  readonly issuedAt: number;
  readonly audience: readonly string[];
  readonly subject: SubjectIdentifier;
  readonly type: string;
  readonly claims: Readonly<Record<string, unknown>>;
  readonly txn: string | undefined;
  readonly token: string;
}

export type SetVerification =
  | { readonly ok: true; readonly set: VerifiedSet }
  | {
      readonly ok: false;
      readonly err: SetErrorCode;
      readonly description: string;
    };

export interface VerifySetOptions {
  readonly jwks: Jwks;
  readonly issuer: string;
  readonly audience: string;
  /** How far `iat` may be in the future, in seconds. Default: 300. */
  readonly skewSeconds?: number;
  /** The transmitter's `critical_subject_members` (SSF §7.1). */
  readonly criticalSubjectMembers?: readonly string[];
  /** The complex subject members this receiver processes. Default: the SSF ones. */
  readonly understoodSubjectMembers?: readonly string[];
}

const SSF_MEMBERS = [
  "user",
  "device",
  "session",
  "application",
  "tenant",
  "org_unit",
  "group",
] as const;

const fail = (err: SetErrorCode, description: string): SetVerification => ({
  ok: false,
  err,
  description,
});

const jwsFailure = (cause: unknown): SetVerification => {
  if (!(cause instanceof JwsError)) throw cause;
  switch (cause.code) {
    case "JWS_MALFORMED":
    case "JWS_TYP":
      return fail("invalid_request", cause.message);
    default:
      return fail("invalid_key", cause.message);
  }
};

/**
 * Verifies a SET as an RFC 8935 receiver: the signature against `jwks`,
 * `typ`, `iss`, `aud`, `jti`, `iat`, one event and an SSF `sub_id`. A
 * failure carries the error code to answer the transmitter with.
 */
export async function verifySet(
  token: string,
  options: VerifySetOptions,
): Promise<SetVerification> {
  let header: Readonly<Record<string, unknown>>;
  let payload: Readonly<Record<string, unknown>>;
  try {
    ({ header, payload } = await verifyCompact(token, options.jwks));
  } catch (cause) {
    return jwsFailure(cause);
  }
  const typ =
    typeof header["typ"] === "string" ? header["typ"].toLowerCase() : "";
  if (typ !== SET_TYP && typ !== SET_CONTENT_TYPE)
    return fail("invalid_request", `The typ must be ${SET_TYP}`);
  if (payload["iss"] !== options.issuer)
    return fail("invalid_issuer", "The iss is not the transmitter's issuer");
  const aud = payload["aud"];
  const audience =
    typeof aud === "string"
      ? [aud]
      : Array.isArray(aud)
        ? aud.filter((value): value is string => typeof value === "string")
        : [];
  if (!audience.includes(options.audience))
    return fail("invalid_audience", "The aud does not name this receiver");
  const jti = payload["jti"];
  if (typeof jti !== "string" || jti === "")
    return fail("invalid_request", "The SET has no jti");
  const iat = payload["iat"];
  if (typeof iat !== "number" || !Number.isFinite(iat))
    return fail("invalid_request", "The SET has no iat");
  if (iat > Date.now() / 1000 + (options.skewSeconds ?? 300))
    return fail("invalid_request", "The iat is in the future");
  const events = payload["events"];
  const entries = isRecord(events) ? Object.entries(events) : [];
  const [entry] = entries;
  if (entry === undefined || entries.length !== 1 || !isRecord(entry[1]))
    return fail("invalid_request", "A SET carries exactly one event");
  const subject = payload["sub_id"];
  if (!isRecord(subject) || typeof subject["format"] !== "string")
    return fail("invalid_request", "The SET has no sub_id");
  const understood = options.understoodSubjectMembers ?? SSF_MEMBERS;
  const unknown = (options.criticalSubjectMembers ?? []).find(
    (member) => member in subject && !understood.includes(member),
  );
  if (unknown !== undefined)
    return fail(
      "invalid_request",
      `The critical subject member ${unknown} is not understood`,
    );
  const txn = payload["txn"];
  return {
    ok: true,
    set: {
      jti,
      issuer: options.issuer,
      issuedAt: iat,
      audience,
      // SAFETY: subject is an object whose format is a string.
      subject: subject as SubjectIdentifier,
      type: entry[0],
      claims: entry[1],
      txn: typeof txn === "string" ? txn : undefined,
      token,
    },
  };
}
