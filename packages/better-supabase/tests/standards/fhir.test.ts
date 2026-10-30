import { describe, expect, it } from "vitest";

import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import {
  toFhirBundle,
  toFhirCarePlan,
  toFhirConsent,
  toFhirMedicationRequest,
  toFhirObservation,
  toFhirPatient,
} from "../../src/fhir/index.ts";

/** R4 forbids empty strings, arrays and objects anywhere in a resource. */
function emptyElements(value: unknown, path = "$"): string[] {
  if (value === "" || value === null) {
    return [path];
  }

  if (Array.isArray(value)) {
    return value.length === 0
      ? [path]
      : value.flatMap((item, index) =>
          emptyElements(item, `${path}[${index}]`),
        );
  }

  if (typeof value === "object") {
    const entries = Object.entries(value);

    return entries.length === 0
      ? [path]
      : entries.flatMap(([key, item]) => emptyElements(item, `${path}.${key}`));
  }

  return value === undefined ? [path] : [];
}

const resources = [
  toFhirPatient({ id: "p-1", identifiers: [] }),
  toFhirObservation({
    id: "o-1",
    definitionKey: "weight",
    title: "Weight",
    valueType: "number",
    subjectId: "p-1",
    observedAt: Temporal.Instant.from("2026-10-30T08:00:00Z"),
    value: null,
    status: "final",
    createdAt: Temporal.Instant.from("2026-10-30T08:00:00Z"),
  }),
  toFhirMedicationRequest({
    id: "m-1",
    subject: { type: "client", id: "p-1" },
    medicationId: "med-1",
    dose: 1,
    doseUnit: "tablet",
    asNeeded: true,
    startsOn: Temporal.PlainDate.from("2026-10-30"),
    status: "active",
  }),
  toFhirCarePlan({
    id: "c-1",
    subjectId: "p-1",
    title: "Plan",
    status: "draft",
    createdAt: Temporal.Instant.from("2026-10-30T08:00:00Z"),
    problems: [],
  }),
  toFhirConsent({
    id: "k-1",
    purposeKey: "care",
    purposeTitle: "Care",
    purposeVersion: "1",
    legalBasis: "consent",
    subject: { type: "client", id: "p-1" },
    givenBy: "self",
    status: "granted",
    grantedAt: Temporal.Instant.from("2026-10-30T08:00:00Z"),
  }),
];

describe("FHIR R4", () => {
  it("pins the release the mappers follow", () => {
    expect(SPEC_PINS.fhirR4).toBe("4.0.1");
  });

  it("writes no empty elements, which R4 JSON forbids", () => {
    expect(emptyElements(toFhirBundle(resources))).toEqual([]);
  });

  it("writes the elements R4 requires on each resource", () => {
    const [patient, observation, request, plan, consent] = resources;

    expect(patient).toMatchObject({ resourceType: "Patient" });
    expect(observation).toMatchObject({ status: "final", code: {} });
    expect(request).toMatchObject({
      status: "active",
      intent: "order",
      subject: {},
    });
    expect(plan).toMatchObject({
      status: "draft",
      intent: "plan",
      subject: {},
    });
    // ppc-1: a policy or a policy rule.
    expect(consent).toMatchObject({
      status: "active",
      scope: {},
      category: [{}],
      policyRule: {},
    });
  });
});
