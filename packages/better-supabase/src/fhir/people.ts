import type { Representative } from "../blocks/contacts/contacts.ts";
import type { RepresentativeRole } from "../blocks/contacts/representatives.ts";
import type { FhirTemporal } from "./shared.ts";
import type {
  FhirAdministrativeGender,
  FhirCodeableConcept,
  FhirContactPoint,
  FhirHumanName,
  FhirIdentifier,
  FhirPatient,
  FhirPeriod,
  FhirReference,
  FhirRelatedPerson,
} from "./types.ts";

import { compact, fhirTime, patientReference } from "./shared.ts";

const ROLE_CODE = "http://terminology.hl7.org/CodeSystem/v3-RoleCode";
const CONTACT_ROLE = "http://terminology.hl7.org/CodeSystem/v2-0131";

/**
 * The record a `Patient` describes: a contacts person, the app's own clients
 * row, or any object with these fields.
 */
export interface FhirPatientSource {
  readonly id: string;
  /** The full name, as `name.text`. */
  readonly name?: string;
  readonly givenNames?: readonly string[];
  readonly familyName?: string;
  readonly email?: string;
  readonly phone?: string;
  readonly gender?: FhirAdministrativeGender;
  readonly birthDate?: FhirTemporal;
  /** A national id (BSN, NHS number) goes here with its system URI. */
  readonly identifiers?: readonly FhirIdentifier[];
  /** An archived record is `active: false`. */
  readonly archived?: boolean;
}

function nameOf(
  name: string | undefined,
  given: readonly string[] | undefined,
  family: string | undefined,
): FhirHumanName[] | undefined {
  if (name === undefined && given === undefined && family === undefined) {
    return undefined;
  }

  return [compact<FhirHumanName>({ text: name, given, family })];
}

function telecomOf(
  email: string | undefined,
  phone: string | undefined,
): FhirContactPoint[] | undefined {
  const telecom: FhirContactPoint[] = [
    ...(email === undefined
      ? []
      : [{ system: "email" as const, value: email }]),
    ...(phone === undefined
      ? []
      : [{ system: "phone" as const, value: phone }]),
  ];

  return telecom.length === 0 ? undefined : telecom;
}

/** A client record as a FHIR R4 `Patient`. */
export function toFhirPatient(source: FhirPatientSource): FhirPatient {
  return compact<FhirPatient>({
    resourceType: "Patient",
    id: source.id,
    identifier:
      source.identifiers === undefined || source.identifiers.length === 0
        ? undefined
        : source.identifiers,
    active: source.archived === undefined ? undefined : !source.archived,
    name: nameOf(source.name, source.givenNames, source.familyName),
    telecom: telecomOf(source.email, source.phone),
    gender: source.gender,
    birthDate: fhirTime(source.birthDate),
  });
}

/** The representative fields `toFhirRelatedPerson` reads. */
export type FhirRepresentativeSource = Pick<
  Representative,
  "id" | "role" | "name"
> &
  Partial<
    Pick<
      Representative,
      "email" | "phone" | "active" | "validFrom" | "validUntil"
    >
  >;

export interface FhirRelatedPersonOptions {
  /** The record represented. Default `Patient/<patientId>`. */
  readonly patient?: FhirReference;
}

function relationshipOf(role: RepresentativeRole): FhirCodeableConcept {
  switch (role) {
    case "guardian": {
      return { coding: [{ system: ROLE_CODE, code: "GUARD" }], text: role };
    }

    case "parent": {
      return { coding: [{ system: ROLE_CODE, code: "PRN" }], text: role };
    }

    case "emergency_contact": {
      return { coding: [{ system: CONTACT_ROLE, code: "C" }], text: role };
    }

    case "contact_person": {
      return { coding: [{ system: CONTACT_ROLE, code: "CP" }], text: role };
    }

    case "other": {
      return { coding: [{ system: CONTACT_ROLE, code: "O" }], text: role };
    }

    case "legal_representative":
    case "mentor":
    case "curator": {
      return { text: role };
    }

    default: {
      const never: never = role;

      return never;
    }
  }
}

/**
 * A representative (`db.contacts.representatives`) as a FHIR R4 `RelatedPerson`
 * of the record. Roles with an HL7 code carry it (`guardian`, `parent`,
 * `emergency_contact`, `contact_person`, `other`); the rest carry the role as
 * text.
 */
export function toFhirRelatedPerson(
  representative: FhirRepresentativeSource,
  patientId: string,
  options?: FhirRelatedPersonOptions,
): FhirRelatedPerson {
  const period = compact<FhirPeriod>({
    start: fhirTime(representative.validFrom),
    end: fhirTime(representative.validUntil),
  });

  return compact<FhirRelatedPerson>({
    resourceType: "RelatedPerson",
    id: representative.id,
    active: representative.active,
    patient: options?.patient ?? patientReference(patientId),
    relationship: [relationshipOf(representative.role)],
    name: [{ text: representative.name }],
    telecom: telecomOf(representative.email, representative.phone),
    period: Object.keys(period).length === 0 ? undefined : period,
  });
}
