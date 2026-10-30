import { describe, expect, it } from "vitest";

import { toFhirPatient, toFhirRelatedPerson } from "../../src/fhir/people.ts";

describe("toFhirPatient", () => {
  it("maps a client with names, contact points and identifiers", () => {
    expect(
      toFhirPatient({
        id: "client-1",
        name: "Anna de Vries",
        givenNames: ["Anna"],
        familyName: "de Vries",
        email: "anna@example.com",
        phone: "+31 6 1234 5678",
        gender: "female",
        birthDate: Temporal.PlainDate.from("1950-04-12"),
        identifiers: [
          {
            system: "http://fhir.nl/fhir/NamingSystem/bsn",
            value: "123456782",
          },
        ],
        archived: false,
      }),
    ).toEqual({
      resourceType: "Patient",
      id: "client-1",
      identifier: [
        { system: "http://fhir.nl/fhir/NamingSystem/bsn", value: "123456782" },
      ],
      active: true,
      name: [{ text: "Anna de Vries", given: ["Anna"], family: "de Vries" }],
      telecom: [
        { system: "email", value: "anna@example.com" },
        { system: "phone", value: "+31 6 1234 5678" },
      ],
      gender: "female",
      birthDate: "1950-04-12",
    });
  });

  it("leaves out what the record doesn't have", () => {
    expect(
      toFhirPatient({ id: "client-2", identifiers: [], archived: true }),
    ).toEqual({ resourceType: "Patient", id: "client-2", active: false });
    expect(
      toFhirPatient({ id: "client-3", familyName: "Bakker" }).name,
    ).toEqual([{ family: "Bakker" }]);
  });
});

describe("toFhirRelatedPerson", () => {
  it("maps a representative with an HL7 role code and a period", () => {
    expect(
      toFhirRelatedPerson(
        {
          id: "link-1",
          role: "guardian",
          name: "Piet de Vries",
          email: "piet@example.com",
          active: true,
          validFrom: Temporal.PlainDate.from("2026-01-01"),
          validUntil: Temporal.PlainDate.from("2027-01-01"),
        },
        "client-1",
      ),
    ).toEqual({
      resourceType: "RelatedPerson",
      id: "link-1",
      active: true,
      patient: { reference: "Patient/client-1" },
      relationship: [
        {
          coding: [
            {
              system: "http://terminology.hl7.org/CodeSystem/v3-RoleCode",
              code: "GUARD",
            },
          ],
          text: "guardian",
        },
      ],
      name: [{ text: "Piet de Vries" }],
      telecom: [{ system: "email", value: "piet@example.com" }],
      period: { start: "2026-01-01", end: "2027-01-01" },
    });
  });

  it.each([
    ["parent", "http://terminology.hl7.org/CodeSystem/v3-RoleCode", "PRN"],
    ["emergency_contact", "http://terminology.hl7.org/CodeSystem/v2-0131", "C"],
    ["contact_person", "http://terminology.hl7.org/CodeSystem/v2-0131", "CP"],
    ["other", "http://terminology.hl7.org/CodeSystem/v2-0131", "O"],
  ] as const)("codes the %s role", (role, system, code) => {
    expect(
      toFhirRelatedPerson({ id: "link-2", role, name: "X" }, "client-1")
        .relationship,
    ).toEqual([{ coding: [{ system, code }], text: role }]);
  });

  it.each(["legal_representative", "mentor", "curator"] as const)(
    "names the %s role as text",
    (role) => {
      const resource = toFhirRelatedPerson(
        { id: "link-3", role, name: "Y", phone: "010" },
        "client-1",
        { patient: { reference: "Patient/p-1" } },
      );

      expect(resource.relationship).toEqual([{ text: role }]);
      expect(resource.patient).toEqual({ reference: "Patient/p-1" });
      expect(resource.telecom).toEqual([{ system: "phone", value: "010" }]);
      expect(resource.period).toBeUndefined();
    },
  );
});
