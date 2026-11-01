import { describe, expect, it } from "vitest";

import {
  courseCertificateBadge,
  OPEN_BADGES_CONTEXT,
  openBadgeCredential,
} from "../../../src/blocks/courses/open-badges.ts";

const base = {
  id: "urn:uuid:7c0f0e3e-0000-4000-8000-000000000001",
  issuer: { id: "https://academy.example", name: "Academy" },
  achievement: {
    id: "https://academy.example/badges/algebra",
    name: "Algebra",
    description: "Completed the Algebra course",
    criteria: "Finish every required lesson and pass the quiz.",
  },
  recipient: { email: "ada@example.com" },
  awardedAt: new Date("2026-10-01T10:00:00Z"),
};

describe("openBadgeCredential", () => {
  it("writes an unsigned OpenBadgeCredential with a hashed email", async () => {
    const credential = await openBadgeCredential({ ...base, salt: "s" });

    const subject = credential.credentialSubject as {
      identifier: { identityHash: string; hashed: boolean; salt: string }[];
    };

    const digest = await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode("ada@example.comS".replace("S", "s")),
    );

    const hex = [...new Uint8Array(digest)]
      .map((byte) => byte.toString(16).padStart(2, "0"))
      .join("");

    expect(credential["@context"]).toEqual(OPEN_BADGES_CONTEXT);
    expect(credential.type).toEqual([
      "VerifiableCredential",
      "OpenBadgeCredential",
    ]);
    expect(credential.proof).toBeUndefined();
    expect(credential.validFrom).toBe("2026-10-01T10:00:00.000Z");
    expect(subject.identifier[0]?.identityHash).toBe(`sha256$${hex}`);
    expect(JSON.stringify(credential)).not.toContain("ada@example.com");
  });

  it("keeps the email only when hashing is off", async () => {
    const credential = await openBadgeCredential({
      ...base,
      recipient: { email: "ada@example.com", hashed: false },
    });

    expect(JSON.stringify(credential)).toContain("ada@example.com");
  });

  it("hands the credential to a signer", async () => {
    const credential = await openBadgeCredential(base, async (value) => ({
      ...value,
      proof: { type: "DataIntegrityProof" },
    }));

    expect(credential.proof).toEqual({ type: "DataIntegrityProof" });
  });
});

describe("courseCertificateBadge", () => {
  const certificate = {
    id: "00000000-0000-4000-8000-0000000000aa",
    courseId: "c",
    userId: "u",
    code: "abc",
    issuedAt: Temporal.Instant.from("2026-10-01T10:00:00Z"),
    expiresAt: Temporal.Instant.from("2027-10-01T10:00:00Z"),
  };

  it("maps issue and expiry and uses a stable id", async () => {
    const credential = await courseCertificateBadge(certificate, {
      issuer: base.issuer,
      achievement: base.achievement,
      recipient: base.recipient,
    });

    expect(credential.id).toBe(`urn:uuid:${certificate.id}`);
    expect(credential.validUntil).toBe("2027-10-01T10:00:00.000Z");
  });

  it("refuses a revoked certificate", async () => {
    await expect(
      courseCertificateBadge(
        {
          ...certificate,
          revokedAt: Temporal.Instant.from("2026-11-01T00:00:00Z"),
        },
        {
          issuer: base.issuer,
          achievement: base.achievement,
          recipient: base.recipient,
        },
      ),
    ).rejects.toThrow(RangeError);
  });
});
