import { afterEach, describe, expect, it, vi } from "vitest";

import type { ValidationIssue } from "../../src/core/errors.ts";
import type { Result } from "../../src/core/result.ts";
import type { FhirMedicationOrderSource } from "../../src/fhir/medications.ts";

import {
  FHIR_MEDICATION_SYSTEMS,
  fromFhirMedicationRequest,
  toFhirMedicationAdministration,
  toFhirMedicationRequest,
} from "../../src/fhir/medications.ts";

const UCUM = "http://unitsofmeasure.org";

const issuesOf = (result: Result<unknown>): readonly ValidationIssue[] =>
  result.error?.kind === "validation" ? result.error.issues : [];

const order: FhirMedicationOrderSource = {
  id: "order-1",
  subject: { type: "client", id: "client-1" },
  medicationId: "med-1",
  dose: 500,
  doseUnit: "mg",
  asNeeded: false,
  startsOn: Temporal.PlainDate.from("2026-10-01"),
  status: "active",
};

describe("toFhirMedicationRequest", () => {
  it("maps a scheduled order with its coded medication", () => {
    const resource = toFhirMedicationRequest(
      {
        ...order,
        endsOn: Temporal.PlainDate.from("2026-10-14"),
        route: "oral",
        schedule: { times: ["08:00", "20:00:00"], weekdays: [1, 7, 9] },
        maxPerDay: 1000,
        prescriber: "Dr. Jansen",
        externalId: "rx-9",
        medication: {
          id: "med-1",
          name: "Paracetamol 500 mg",
          codeSystem: "atc",
          code: "N02BE01",
        },
      },
      { identifierSystem: "urn:pharmacy" },
    );

    expect(resource).toEqual({
      resourceType: "MedicationRequest",
      id: "order-1",
      identifier: [{ system: "urn:pharmacy", value: "rx-9" }],
      status: "active",
      intent: "order",
      medicationCodeableConcept: {
        coding: [
          {
            system: FHIR_MEDICATION_SYSTEMS.atc,
            code: "N02BE01",
            display: "Paracetamol 500 mg",
          },
        ],
        text: "Paracetamol 500 mg",
      },
      subject: { reference: "Patient/client-1" },
      requester: { display: "Dr. Jansen" },
      dosageInstruction: [
        {
          timing: {
            repeat: {
              boundsPeriod: { start: "2026-10-01", end: "2026-10-14" },
              timeOfDay: ["08:00:00", "20:00:00"],
              dayOfWeek: ["mon", "sun"],
            },
          },
          route: { text: "oral" },
          doseAndRate: [{ doseQuantity: { value: 500, unit: "mg" } }],
          maxDosePerPeriod: {
            numerator: { value: 1000, unit: "mg" },
            denominator: { value: 1, unit: "d", system: UCUM, code: "d" },
          },
        },
      ],
    });
  });

  it("references the medication without its row, and maps the other statuses", () => {
    const paused = toFhirMedicationRequest({ ...order, status: "paused" });

    const stopped = toFhirMedicationRequest({
      ...order,
      status: "stopped",
      stoppedReason: "side effects",
    });

    expect(paused.medicationReference).toEqual({
      reference: "Medication/med-1",
    });
    expect(paused.status).toBe("on-hold");
    expect(stopped.status).toBe("stopped");
    expect(stopped.statusReason).toEqual({ text: "side effects" });
  });

  it("writes hourly and as-needed dosing", () => {
    const [hourly] =
      toFhirMedicationRequest({ ...order, schedule: { everyHours: 6 } })
        .dosageInstruction ?? [];

    const [prn] =
      toFhirMedicationRequest({ ...order, asNeeded: true }).dosageInstruction ??
      [];

    const [reason] =
      toFhirMedicationRequest({
        ...order,
        asNeeded: true,
        asNeededReason: "pain",
      }).dosageInstruction ?? [];

    expect(hourly?.timing?.repeat).toEqual({
      boundsPeriod: { start: "2026-10-01" },
      frequency: 1,
      period: 6,
      periodUnit: "h",
    });
    expect(prn?.asNeededBoolean).toBe(true);
    expect(reason?.asNeededCodeableConcept).toEqual({ text: "pain" });
  });

  it("names custom and uncoded medications", () => {
    const custom = toFhirMedicationRequest(
      {
        ...order,
        medication: {
          id: "med-1",
          name: "House mix",
          codeSystem: "custom",
          code: "HM1",
        },
      },
      { customCodeSystem: "urn:app:meds" },
    );

    const uncoded = toFhirMedicationRequest({
      ...order,
      medication: { id: "med-1", name: "House mix", codeSystem: "custom" },
    });

    expect(custom.medicationCodeableConcept?.coding).toEqual([
      { system: "urn:app:meds", code: "HM1", display: "House mix" },
    ]);
    expect(uncoded.medicationCodeableConcept).toEqual({ text: "House mix" });
  });
});

describe("toFhirMedicationAdministration", () => {
  const user = (id: string): { reference: string } => ({
    reference: `Practitioner/${id}`,
  });

  it("maps a given dose with performer and verifier", () => {
    const resource = toFhirMedicationAdministration(
      {
        id: "adm-1",
        orderId: "order-1",
        status: "given",
        administeredAt: Temporal.Instant.from("2026-10-02T08:05:00Z"),
        scheduledAt: Temporal.Instant.from("2026-10-02T08:00:00Z"),
        dose: 500,
        performerId: "nurse-1",
        checkedBy: "nurse-2",
        note: "with water",
      },
      { ...order, route: "oral" },
      { user },
    );

    expect(resource).toEqual({
      resourceType: "MedicationAdministration",
      id: "adm-1",
      status: "completed",
      medicationReference: { reference: "Medication/med-1" },
      subject: { reference: "Patient/client-1" },
      effectiveDateTime: "2026-10-02T08:05:00Z",
      performer: [
        {
          function: {
            coding: [
              {
                system:
                  "http://terminology.hl7.org/CodeSystem/med-admin-perform-function",
                code: "performer",
              },
            ],
          },
          actor: { reference: "Practitioner/nurse-1" },
        },
        {
          function: {
            coding: [
              {
                system:
                  "http://terminology.hl7.org/CodeSystem/med-admin-perform-function",
                code: "verifier",
              },
            ],
          },
          actor: { reference: "Practitioner/nurse-2" },
        },
      ],
      request: { reference: "MedicationRequest/order-1" },
      note: [{ text: "with water" }],
      dosage: { route: { text: "oral" }, dose: { value: 500, unit: "mg" } },
    });
  });

  it.each([
    ["refused", "not-done"],
    ["skipped", "not-done"],
    ["missed", "not-done"],
    ["planned", "unknown"],
  ] as const)("maps a %s dose as %s", (status, expected) => {
    const resource = toFhirMedicationAdministration(
      {
        id: "adm-2",
        orderId: "order-1",
        status,
        scheduledAt: Temporal.Instant.from("2026-10-02T08:00:00Z"),
      },
      order,
    );

    expect(resource.status).toBe(expected);
    expect(resource.statusReason).toEqual(
      expected === "not-done" ? [{ text: status }] : undefined,
    );
    expect(resource.effectiveDateTime).toBe("2026-10-02T08:00:00Z");
    expect(resource.performer).toBeUndefined();
    expect(resource.dosage).toBeUndefined();
  });

  it("keeps the recorded reason for a refused dose", () => {
    expect(
      toFhirMedicationAdministration(
        {
          id: "adm-3",
          orderId: "order-1",
          status: "refused",
          reason: "nausea",
        },
        order,
      ).statusReason,
    ).toEqual([{ text: "nausea" }]);
  });
});

const request = (fields: Record<string, unknown>): unknown => ({
  resourceType: "MedicationRequest",
  id: "rx-1",
  status: "active",
  intent: "order",
  subject: { reference: "Patient/client-1" },
  medicationCodeableConcept: {
    coding: [
      {
        system: FHIR_MEDICATION_SYSTEMS.hpk,
        code: "2345",
        display: "Paracetamol",
      },
    ],
  },
  dosageInstruction: [
    {
      timing: {
        repeat: {
          boundsPeriod: { start: "2026-10-01", end: "2026-10-14T00:00:00Z" },
          timeOfDay: ["08:00:00", 9],
          dayOfWeek: ["mon", "xyz"],
        },
      },
      route: { coding: [{ display: "oral" }] },
      doseAndRate: [{ doseQuantity: { value: 1, unit: "tablet" } }],
      maxDosePerPeriod: {
        numerator: { value: 4 },
        denominator: { value: 1, code: "d" },
      },
    },
  ],
  requester: { display: "Dr. Jansen" },
  ...fields,
});

describe("fromFhirMedicationRequest", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("reads a pharmacy order with a catalog medication", () => {
    const result = fromFhirMedicationRequest(request({}), {
      subjectType: "client",
    });

    expect(result.error).toBeNull();
    expect(result.data).toMatchObject({
      subject: { type: "client", id: "client-1" },
      externalId: "rx-1",
      medication: {
        name: "Paracetamol",
        unit: "tablet",
        codeSystem: "hpk",
        code: "2345",
      },
      dose: 1,
      doseUnit: "tablet",
      route: "oral",
      schedule: { times: ["08:00"], weekdays: [1] },
      maxPerDay: 4,
      prescriber: "Dr. Jansen",
    });
    expect(result.data?.startsOn?.toString()).toBe("2026-10-01");
    expect(result.data?.endsOn?.toString()).toBe("2026-10-14");
  });

  it("reads a Medication reference, hourly timing and as-needed dosing", () => {
    const hourly = fromFhirMedicationRequest(
      request({
        identifier: [{ value: "ext-7" }],
        medicationCodeableConcept: undefined,
        medicationReference: { reference: "Medication/med-1" },
        authoredOn: "2026-09-30",
        dosageInstruction: [
          {
            timing: { repeat: { frequency: 1, period: 8, periodUnit: "h" } },
            route: { text: "iv" },
            doseAndRate: [{ doseQuantity: { value: 2, code: "mL" } }],
          },
        ],
      }),
      { subjectType: "client", subjectId: "client-9" },
    );

    const prn = fromFhirMedicationRequest(
      request({
        medicationCodeableConcept: {
          text: "Rescue",
          coding: [{ system: "urn:x", code: "R" }],
        },
        dosageInstruction: [
          {
            asNeededCodeableConcept: { text: "dyspnea" },
            doseAndRate: [{ doseQuantity: { value: 1, unit: "puff" } }],
          },
        ],
      }),
      { subjectType: "client" },
    );

    expect(hourly.data).toMatchObject({
      subject: { type: "client", id: "client-9" },
      externalId: "ext-7",
      medicationId: "med-1",
      route: "iv",
      dose: 2,
      doseUnit: "mL",
      schedule: { everyHours: 8 },
    });
    expect(hourly.data?.startsOn?.toString()).toBe("2026-09-30");
    expect(prn.data).toMatchObject({
      medication: {
        name: "Rescue",
        codeSystem: "custom",
        code: "R",
        unit: "puff",
      },
      asNeeded: true,
      asNeededReason: "dyspnea",
    });
    expect(prn.data?.schedule).toBeUndefined();
  });

  it("rejects anything but a MedicationRequest", () => {
    expect(
      issuesOf(fromFhirMedicationRequest(null, { subjectType: "client" })),
    ).toEqual([
      {
        path: ["resourceType"],
        message: "resourceType must be MedicationRequest",
      },
    ]);
  });

  it("lists every problem of an order it can't store", () => {
    const result = fromFhirMedicationRequest(
      {
        resourceType: "MedicationRequest",
        status: "completed",
        intent: "proposal",
        medicationCodeableConcept: { text: "Unknown" },
        dosageInstruction: [
          {
            timing: { repeat: { boundsPeriod: { start: "soon" } } },
            doseAndRate: [{ doseQuantity: { value: "1" } }],
          },
        ],
      },
      { subjectType: "client" },
    );

    expect(issuesOf(result).map((issue) => issue.message)).toEqual([
      "status completed is not active",
      "intent proposal is not an order",
      "id or identifier is required to import once",
      "subject must reference the record",
      "dosageInstruction needs a dose quantity",
      "medication needs a coded medication or a Medication reference",
      "timing needs timeOfDay, or a frequency of 1 every period hours",
      "dosageInstruction.0.timing.repeat.boundsPeriod.start must be a full date",
    ]);
  });

  it("needs a dose unit to add a catalog medication", () => {
    const result = fromFhirMedicationRequest(
      request({
        dosageInstruction: [
          {
            asNeededBoolean: true,
            doseAndRate: [{ doseQuantity: { value: 1 } }],
          },
        ],
      }),
      { subjectType: "client" },
    );

    expect(issuesOf(result).map((issue) => issue.message)).toEqual([
      "dose needs a unit to add the medication",
    ]);
  });

  it("returns the Temporal error when the runtime has none", () => {
    vi.stubGlobal("Temporal", undefined);

    expect(
      fromFhirMedicationRequest(request({}), { subjectType: "client" }).error
        ?.kind,
    ).toBe("unexpected");
  });
});
