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
  it("restores an archived purpose", async () => {
    const { transport, call } = fakeTransport({
      restore_consent_purpose: PURPOSE,
    });

    const consents = createConsents({ transport, tenant: "org" });

    expect(await consents.restorePurpose("p1").orThrow()).toMatchObject({
      id: PURPOSE.id,
    });
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "restore_consent_purpose",
      { purpose_id: "p1" },
    );
  });

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
      expires_at: null,
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

  it("records signals, issues receipts and lists them", async () => {
    const SIGNAL = {
      id: "s1",
      organizationId: "org",
      subjectType: "people",
      subjectId: "person-1",
      kind: "gpc",
      raw: "1",
      parsed: { optOut: true },
      consentIds: ["c1"],
      receivedAt: AT,
    };

    const RECEIPT = {
      receiptId: "r1",
      format: "kantara-1.1",
      issuedAt: AT,
      organizationId: "org",
      subject: { type: "people", id: "person-1" },
      purpose: {
        key: "marketing.email",
        title: "Marketing email",
        version: "1",
        legalBasis: "consent",
      },
      consent: {
        id: "c1",
        status: "granted",
        givenBy: "self",
        grantedAt: AT,
        scope: { channels: ["email"] },
        validUntil: UNTIL,
        withdrawnAt: AT,
      },
      evidence: { ip: "::1" },
      digest: "abc",
    };

    const { transport, call } = fakeTransport({
      record_consent_signal: SIGNAL,
      list_consent_signals: [{ ...SIGNAL, parsed: null, consentIds: null }],
      issue_consent_receipt: RECEIPT,
      list_consent_receipts: [
        {
          ...RECEIPT,
          consent: {
            ...RECEIPT.consent,
            scope: null,
            validUntil: null,
            withdrawnAt: null,
          },
          evidence: null,
        },
      ],
    });

    const consents = createConsents({ transport, tenant: "org" });
    const subject = { type: "people", id: "person-1" };

    const signal = await consents
      .recordSignal({
        subject,
        kind: "gpc",
        value: "1",
        purposeKeys: ["a"],
        consentId: "c1",
      })
      .orThrow();

    expect(signal).toMatchObject({
      kind: "gpc",
      consentIds: ["c1"],
      parsed: { optOut: true },
    });
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "record_consent_signal",
      expect.objectContaining({ purpose_keys: ["a"], consent_id: "c1" }),
    );

    await consents.recordSignal({ subject, kind: "tcf", value: "x" }).orThrow();
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "record_consent_signal",
      expect.objectContaining({ purpose_keys: [], consent_id: null }),
    );

    const [listed] = await consents.signals(subject).orThrow();
    expect(listed).toMatchObject({ parsed: {}, consentIds: [] });

    const receipt = await consents.issueReceipt("c1").orThrow();
    expect(receipt.consent.withdrawnAt?.toString()).toBe(AT);
    expect(receipt.evidence).toEqual({ ip: "::1" });

    const [bare] = await consents.receipts(subject).orThrow();
    expect(bare?.consent).toMatchObject({ scope: {} });
    expect(bare?.consent.validUntil).toBeUndefined();
    expect(bare?.evidence).toEqual({});
  });
});
