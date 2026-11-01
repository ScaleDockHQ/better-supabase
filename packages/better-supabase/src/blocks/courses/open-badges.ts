import type { CourseCertificate } from "./courses.ts";

import { toBase64Url } from "../../core/base64.ts";

export const OPEN_BADGES_CONTEXT = [
  "https://www.w3.org/ns/credentials/v2",
  "https://purl.imsglobal.org/spec/ob/v3p0/context-3.0.3.json",
] as const;

export interface OpenBadgeIssuer {
  /** The issuer's URL or DID. */
  readonly id: string;
  readonly name: string;
  readonly url?: string;
  readonly email?: string;
}

export interface OpenBadgeAchievement {
  /** A URL that stays the same for this badge class. */
  readonly id: string;
  readonly name: string;
  readonly description: string;
  /** What a learner did to earn it, in words. */
  readonly criteria: string;
  /** A public image of the badge. */
  readonly imageUrl?: string;
}

export interface OpenBadgeRecipient {
  /** Email, hashed in the credential unless `hashed` is `false`. */
  readonly email: string;
  /** Default `true`: the credential carries a salted SHA-256, never the email. */
  readonly hashed?: boolean;
  readonly name?: string;
}

export interface OpenBadgeInput {
  /** The credential's own URL or `urn:uuid:` id. */
  readonly id: string;
  readonly issuer: OpenBadgeIssuer;
  readonly achievement: OpenBadgeAchievement;
  readonly recipient: OpenBadgeRecipient;
  readonly awardedAt: Date;
  readonly expiresAt?: Date;
  /** Random value for the hash. Default 16 random bytes. */
  readonly salt?: string;
}

/** An OpenBadgeCredential (Open Badges 3.0) without a proof. */
export interface OpenBadgeCredential {
  readonly "@context": readonly string[];
  readonly id: string;
  readonly type: readonly string[];
  readonly issuer: Readonly<Record<string, unknown>>;
  readonly validFrom: string;
  readonly validUntil?: string;
  readonly name: string;
  readonly credentialSubject: Readonly<Record<string, unknown>>;
  readonly proof?: unknown;
}

async function hashedIdentity(email: string, salt: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`${email}${salt}`),
  );

  const hex = [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");

  return `sha256$${hex}`;
}

/**
 * Writes an Open Badges 3.0 credential as the JSON-LD document a wallet or
 * verifier reads. The result is **unsigned**: it has no `proof`, so it is not
 * yet a verifiable credential. Sign it with `signer`, such as a function over
 * `better-supabase/verifiable-credentials` once that is installed, or hand the
 * document to your own issuer. The email goes into the credential only as
 * `sha256$<hex of email + salt>` unless `recipient.hashed` is `false`.
 */
export async function openBadgeCredential(
  input: OpenBadgeInput,
  signer?: (credential: OpenBadgeCredential) => Promise<OpenBadgeCredential>,
): Promise<OpenBadgeCredential> {
  const hashed = input.recipient.hashed ?? true;

  const salt =
    input.salt ?? toBase64Url(crypto.getRandomValues(new Uint8Array(16)));

  const identifier = {
    type: "IdentityObject",
    identityType: "emailAddress",
    hashed,
    identityHash: hashed
      ? await hashedIdentity(input.recipient.email, salt)
      : input.recipient.email,
    ...(hashed ? { salt } : {}),
  };

  const credential: OpenBadgeCredential = {
    "@context": OPEN_BADGES_CONTEXT,
    id: input.id,
    type: ["VerifiableCredential", "OpenBadgeCredential"],
    issuer: {
      id: input.issuer.id,
      type: ["Profile"],
      name: input.issuer.name,
      ...(input.issuer.url === undefined ? {} : { url: input.issuer.url }),
      ...(input.issuer.email === undefined
        ? {}
        : { email: input.issuer.email }),
    },
    validFrom: input.awardedAt.toISOString(),
    ...(input.expiresAt === undefined
      ? {}
      : { validUntil: input.expiresAt.toISOString() }),
    name: input.achievement.name,
    credentialSubject: {
      type: ["AchievementSubject"],
      identifier: [identifier],
      achievement: {
        id: input.achievement.id,
        type: ["Achievement"],
        name: input.achievement.name,
        description: input.achievement.description,
        criteria: { narrative: input.achievement.criteria },
        ...(input.achievement.imageUrl === undefined
          ? {}
          : { image: { id: input.achievement.imageUrl, type: "Image" } }),
      },
    },
  };

  return signer === undefined ? credential : signer(credential);
}

export interface CourseBadgeOptions {
  readonly issuer: OpenBadgeIssuer;
  /** The badge class for the course; see `OpenBadgeAchievement`. */
  readonly achievement: OpenBadgeAchievement;
  readonly recipient: OpenBadgeRecipient;
  /**
   * The credential's id. Default `urn:uuid:` plus the certificate's id, which
   * is stable, so exporting twice gives the same id.
   */
  readonly id?: string;
  readonly signer?: (
    credential: OpenBadgeCredential,
  ) => Promise<OpenBadgeCredential>;
}

/**
 * Exports a course certificate as an Open Badges 3.0 credential. A revoked
 * certificate is refused: a badge that was revoked is never handed out again
 * (revocation of an issued badge needs a status list, which is the signer's to
 * add).
 */
export async function courseCertificateBadge(
  certificate: CourseCertificate,
  options: CourseBadgeOptions,
): Promise<OpenBadgeCredential> {
  if (certificate.revokedAt !== undefined) {
    throw new RangeError("A revoked certificate cannot be exported as a badge");
  }

  return openBadgeCredential(
    {
      id: options.id ?? `urn:uuid:${certificate.id}`,
      issuer: options.issuer,
      achievement: options.achievement,
      recipient: options.recipient,
      awardedAt: new Date(certificate.issuedAt.epochMilliseconds),
      ...(certificate.expiresAt === undefined
        ? {}
        : { expiresAt: new Date(certificate.expiresAt.epochMilliseconds) }),
    },
    options.signer,
  );
}
