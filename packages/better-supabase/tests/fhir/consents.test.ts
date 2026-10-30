import { describe, expect, it } from "vitest";

import type { FhirConsentSource } from "../../src/fhir/consents.ts";

import { toFhirConsent } from "../../src/fhir/consents.ts";

const consent: FhirConsentSource = {
  id: "consent-1",
  purposeKey: "share-gp",
  purposeTitle: "Share data with the GP",
  purposeVersion: "2",
  legalBasis: "consent",
  subject: { type: "client", id: "client-1" },
  givenBy: "self",
  status: "granted",
  grantedAt: Temporal.Instant.from("2026-10-01T10:00:00Z"),
  validUntil: Temporal.Instant.from("2027-10-01T10:00:00Z"),
};

describe("toFhirConsent", () => {
  it("maps a granted consent as an active permit for its purpose", () => {
    expect(
      toFhirConsent(consent, { purposeSystem: "urn:app:purposes" }),
    ).toEqual({
      resourceType: "Consent",
      id: "consent-1",
      status: "active",
      scope: {
        coding: [
          {
            system: "http://terminology.hl7.org/CodeSystem/consentscope",
            code: "patient-privacy",
          },
        ],
      },
      category: [{ coding: [{ system: "http://loinc.org", code: "59284-0" }] }],
      patient: { reference: "Patient/client-1" },
      dateTime: "2026-10-01T10:00:00Z",
      performer: [{ reference: "Patient/client-1" }],
      policyRule: { text: "consent" },
      provision: {
        type: "permit",
        period: { start: "2026-10-01T10:00:00Z", end: "2027-10-01T10:00:00Z" },
        purpose: [
          {
            system: "urn:app:purposes",
            version: "2",
            code: "share-gp",
            display: "Share data with the GP",
          },
        ],
      },
    });
  });

  it("maps refused, withdrawn and expired decisions", () => {
    const refused = toFhirConsent({ ...consent, status: "refused" });

    const withdrawn = toFhirConsent({
      ...consent,
      status: "withdrawn",
      withdrawnAt: Temporal.Instant.from("2026-11-01T10:00:00Z"),
    });

    expect(refused.status).toBe("rejected");
    expect(refused.provision?.type).toBe("deny");
    expect(withdrawn.status).toBe("inactive");
    expect(withdrawn.provision?.period?.end).toBe("2026-11-01T10:00:00Z");
    expect(toFhirConsent({ ...consent, status: "expired" }).status).toBe(
      "inactive",
    );
  });

  it("names a representative as the performer, and takes scope options", () => {
    const resource = toFhirConsent(
      { ...consent, givenBy: "representative", givenByContactId: "link-1" },
      {
        patient: { reference: "Patient/p-1" },
        scope: "research",
        category: [{ text: "Research" }],
      },
    );

    expect(resource.performer).toEqual([{ reference: "RelatedPerson/link-1" }]);
    expect(resource.patient).toEqual({ reference: "Patient/p-1" });
    expect(resource.scope.coding?.[0]?.code).toBe("research");
    expect(resource.category).toEqual([{ text: "Research" }]);
  });
});
