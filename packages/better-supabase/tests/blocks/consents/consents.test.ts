import { describe, expect, it } from "vitest";

import {
  consentPurposeInputSchema,
  consentsBlock,
  consentsEvents,
  createConsents,
} from "../../../src/blocks/consents/index.ts";
import { fakeTransport } from "../inbox/fixtures.ts";

const AT = "2026-01-01T00:00:00Z";
const UNTIL = "2027-01-01T00:00:00Z";

const PURPOSE = {
  id: "p1",
  organizationId: "org",
  key: "marketing.email",
  title: "Marketing email",
  description: null,
  legalBasis: "consent",
  version: "1",
  requiresSignature: false,
  validMonths: 12,
  archivedAt: null,
  createdAt: AT,
  updatedAt: AT,
};

const CONSENT = {
  id: "c1",
  organizationId: "org",
  purposeId: "p1",
  purposeKey: "marketing.email",
  purposeTitle: "Marketing email",
  purposeVersion: "1",
  legalBasis: "consent",
  subjectType: "people",
  subjectId: "person-1",
  givenBy: "self",
  givenByContactId: null,
  givenByUserId: "u1",
  status: "granted",
  scope: { channels: ["email"] },
  grantedAt: AT,
  validUntil: UNTIL,
  withdrawnAt: null,
  withdrawnReason: null,
  signatureId: null,
  submissionId: "s1",
  attachmentId: null,
  createdBy: "u1",
  createdAt: AT,
  active: true,
};

describe("createConsents", () => {
  it("saves purposes for the organization or the whole system", async () => {
    const { transport, call } = fakeTransport({
      save_consent_purpose: PURPOSE,
      list_consent_purposes: [PURPOSE, { ...PURPOSE, organizationId: null }],
      archive_consent_purpose: { ...PURPOSE, archivedAt: AT },
    });

    const consents = createConsents({ transport, tenant: "org" });

    const saved = await consents
      .savePurpose({ key: "marketing.email", title: "Marketing email" })
      .orThrow();

    expect(saved).toMatchObject({ key: "marketing.email", validMonths: 12 });
    expect(saved.description).toBeUndefined();
    expect(saved.archivedAt).toBeUndefined();
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "save_consent_purpose",
      expect.objectContaining({ tenant: "org", key: "marketing.email" }),
    );

    await consents
      .savePurpose({ key: "terms", title: "Terms", system: true })
      .orThrow();
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "save_consent_purpose",
      expect.objectContaining({ tenant: null, key: "terms" }),
    );

    const listed = await consents.purposes().orThrow();
    expect(listed.map((purpose) => purpose.organizationId)).toEqual([
      "org",
      null,
    ]);

    const archived = await consents.archivePurpose("p1").orThrow();
    expect(archived.archivedAt?.toString()).toBe(AT);
  });

  it("records, checks, lists and withdraws decisions", async () => {
    const { transport, call } = fakeTransport({
      record_consent: CONSENT,
      consent_active: true,
      list_consents: [CONSENT],
      withdraw_consent: {
        ...CONSENT,
        status: "withdrawn",
        withdrawnAt: AT,
        withdrawnReason: "asked",
        active: false,
      },
      expire_consents: 3,
    });

    const consents = createConsents({ transport, tenant: "org" });
    const subject = { type: "people", id: "person-1" };

    const recorded = await consents
      .record({
        subject,
        purposeKey: "marketing.email",
        status: "granted",
        scope: { channels: ["email"] },
        evidence: { submissionId: "s1" },
      })
      .orThrow();

    expect(recorded).toMatchObject({
      subject,
      status: "granted",
      active: true,
      submissionId: "s1",
    });
    expect(recorded.validUntil?.toString()).toBe(UNTIL);
    expect(recorded.givenByContactId).toBeUndefined();
    expect(call).toHaveBeenLastCalledWith("better_supabase", "record_consent", {
      subject_type: "people",
      subject_id: "person-1",
      purpose_key: "marketing.email",
      status: "granted",
      given_by: "self",
      given_by_contact_id: null,
      valid_until: null,
      scope: { channels: ["email"] },
      evidence: { submissionId: "s1" },
    });

    expect(
      await consents
        .isActive({ subject, purposeKey: "marketing.email" })
        .orThrow(),
    ).toBe(true);
    expect(await consents.list({ subject }).orThrow()).toHaveLength(1);
    expect(call).toHaveBeenLastCalledWith("better_supabase", "list_consents", {
      subject_type: "people",
      subject_id: "person-1",
      include_history: false,
    });

    const withdrawn = await consents
      .withdraw({ consentId: "c1", reason: "asked" })
      .orThrow();

    expect(withdrawn).toMatchObject({
      status: "withdrawn",
      withdrawnReason: "asked",
      active: false,
    });

    expect(await consents.expire().orThrow()).toBe(3);
  });

  it("needs a tenant for organization purposes", async () => {
    const { transport } = fakeTransport({});
    const consents = createConsents({ transport });

    const result = await consents.savePurpose({ key: "a", title: "A" });

    expect(result.ok).toBe(false);
  });

  it("validates purpose input and declares its events", () => {
    const validate = consentPurposeInputSchema["~standard"].validate;

    expect(validate({ key: "marketing.email", title: "Email" })).toEqual({
      value: { key: "marketing.email", title: "Email" },
    });
    expect(validate({ key: "a", title: "A", validMonths: 0 })).toHaveProperty(
      "issues",
    );
    expect(consentsEvents.types).toEqual(
      expect.arrayContaining([
        "consent.granted",
        "consent.refused",
        "consent.withdrawn",
        "consent.expired",
        "consent_purpose.created",
        "consent_purpose.updated",
      ]),
    );
    expect(consentsBlock.name).toBe("consents");
  });
});
