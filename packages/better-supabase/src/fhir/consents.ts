import type { Consent, ConsentStatus } from "../blocks/consents/consents.ts";
import type {
  FhirCodeableConcept,
  FhirCoding,
  FhirConsent,
  FhirConsentStatus,
  FhirPeriod,
  FhirReference,
} from "./types.ts";

import { compact, fhirTime, patientReference } from "./shared.ts";

const CONSENT_SCOPE = "http://terminology.hl7.org/CodeSystem/consentscope";

/** LOINC 59284-0, Patient consent: the R4 examples' category. */
const PATIENT_CONSENT: FhirCodeableConcept = {
  coding: [{ system: "http://loinc.org", code: "59284-0" }],
};

/** The FHIR consent scopes. */
export type FhirConsentScope =
  | "adr"
  | "research"
  | "patient-privacy"
  | "treatment";

/** The consent fields `toFhirConsent` reads. */
export type FhirConsentSource = Pick<
  Consent,
  | "id"
  | "purposeKey"
  | "purposeTitle"
  | "purposeVersion"
  | "legalBasis"
  | "subject"
  | "givenBy"
  | "status"
  | "grantedAt"
> &
  Partial<Pick<Consent, "givenByContactId" | "validUntil" | "withdrawnAt">>;

export interface FhirConsentOptions {
  /** The record. Default `Patient/<subject.id>`. */
  readonly patient?: FhirReference;
  /** Default `patient-privacy`. */
  readonly scope?: FhirConsentScope;
  /** Default LOINC 59284-0 (Patient consent). */
  readonly category?: readonly FhirCodeableConcept[];
  /** The `system` of the purpose coding, such as the app's own URI. */
  readonly purposeSystem?: string;
}

function statusOf(status: ConsentStatus): FhirConsentStatus {
  switch (status) {
    case "granted": {
      return "active";
    }

    case "refused": {
      return "rejected";
    }

    case "withdrawn":
    case "expired": {
      return "inactive";
    }

    default: {
      const never: never = status;

      return never;
    }
  }
}

/**
 * A consents block decision as a FHIR R4 `Consent`. The purpose is the
 * provision's purpose coding (key, title and version), the lawful basis the
 * policy rule, and a representative's decision names `RelatedPerson/<contact
 * id>` as the performer.
 */
export function toFhirConsent(
  consent: FhirConsentSource,
  options?: FhirConsentOptions,
): FhirConsent {
  const patient = options?.patient ?? patientReference(consent.subject.id);

  const performer =
    consent.givenBy === "representative" &&
    consent.givenByContactId !== undefined
      ? { reference: `RelatedPerson/${consent.givenByContactId}` }
      : patient;

  return compact<FhirConsent>({
    resourceType: "Consent",
    id: consent.id,
    status: statusOf(consent.status),
    scope: {
      coding: [
        { system: CONSENT_SCOPE, code: options?.scope ?? "patient-privacy" },
      ],
    },
    category: options?.category ?? [PATIENT_CONSENT],
    patient,
    dateTime: fhirTime(consent.grantedAt),
    performer: [performer],
    policyRule: { text: consent.legalBasis },
    provision: {
      type: consent.status === "refused" ? "deny" : "permit",
      period: compact<FhirPeriod>({
        start: fhirTime(consent.grantedAt),
        end: fhirTime(consent.withdrawnAt ?? consent.validUntil),
      }),
      purpose: [
        compact<FhirCoding>({
          system: options?.purposeSystem,
          version: consent.purposeVersion,
          code: consent.purposeKey,
          display: consent.purposeTitle,
        }),
      ],
    },
  });
}
