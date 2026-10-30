import { afterEach, describe, expect, it, vi } from "vitest";

import type { ValidationIssue } from "../../src/core/errors.ts";
import type { Result } from "../../src/core/result.ts";
import type {
  FhirImportDefinition,
  FhirObservationDefinition,
  FhirObservationSource,
} from "../../src/fhir/observations.ts";

import {
  fromFhirObservation,
  toFhirObservation,
} from "../../src/fhir/observations.ts";

const LOINC = "http://loinc.org";

const issuesOf = (result: Result<unknown>): readonly ValidationIssue[] =>
  result.error?.kind === "validation" ? result.error.issues : [];

const AT = "2026-10-30T08:15:00Z";

const base: FhirObservationSource = {
  id: "obs-1",
  definitionKey: "heart_rate",
  title: "Heart rate",
  valueType: "number",
  subjectId: "client-1",
  observedAt: Temporal.Instant.from(AT),
  value: 72,
  status: "final",
  createdAt: Temporal.Instant.from("2026-10-30T08:16:00Z"),
};

const heartRate: FhirObservationDefinition = {
  codeSystem: LOINC,
  code: "8867-4",
  unit: "/min",
  referenceLow: 60,
  referenceHigh: 100,
};

const bloodPressure: FhirObservationDefinition = {
  codeSystem: LOINC,
  code: "85354-9",
  unit: "mm[Hg]",
  components: [
    { key: "systolic", title: "Systolic", code: "8480-6" },
    { key: "diastolic", title: "Diastolic", code: "8462-4" },
  ],
};

describe("toFhirObservation", () => {
  it("maps a measured value with its code, unit and reference range", () => {
    const resource = toFhirObservation(
      {
        ...base,
        unit: "/min",
        flag: "high",
        externalId: "dev-9",
        performerId: "u-1",
      },
      {
        definition: heartRate,
        identifierSystem: "urn:device",
        user: (id) => ({ reference: `Practitioner/${id}` }),
        category: [{ coding: [{ code: "vital-signs" }] }],
      },
    );

    expect(resource).toEqual({
      resourceType: "Observation",
      id: "obs-1",
      identifier: [{ system: "urn:device", value: "dev-9" }],
      status: "final",
      category: [{ coding: [{ code: "vital-signs" }] }],
      code: {
        coding: [{ system: LOINC, code: "8867-4", display: "Heart rate" }],
        text: "Heart rate",
      },
      subject: { reference: "Patient/client-1" },
      effectiveDateTime: AT,
      issued: "2026-10-30T08:16:00Z",
      performer: [{ reference: "Practitioner/u-1" }],
      valueQuantity: {
        value: 72,
        unit: "/min",
        system: "http://unitsofmeasure.org",
        code: "/min",
      },
      interpretation: [
        {
          coding: [
            {
              system:
                "http://terminology.hl7.org/CodeSystem/v3-ObservationInterpretation",
              code: "H",
            },
          ],
        },
      ],
      referenceRange: [
        {
          low: {
            value: 60,
            unit: "/min",
            system: "http://unitsofmeasure.org",
            code: "/min",
          },
          high: {
            value: 100,
            unit: "/min",
            system: "http://unitsofmeasure.org",
            code: "/min",
          },
        },
      ],
    });
  });

  it.each([
    ["normal", "N"],
    ["low", "L"],
    ["critical_low", "LL"],
    ["critical_high", "HH"],
  ] as const)("interprets the %s flag as %s", (flag, code) => {
    expect(toFhirObservation({ ...base, flag }).interpretation).toEqual([
      {
        coding: [
          {
            system:
              "http://terminology.hl7.org/CodeSystem/v3-ObservationInterpretation",
            code,
          },
        ],
      },
    ]);
  });

  it.each([
    ["amended", "amended"],
    ["entered_in_error", "entered-in-error"],
  ] as const)("maps the %s status", (status, expected) => {
    expect(toFhirObservation({ ...base, status }).status).toBe(expected);
  });

  it("names the code by title and the subject by option without a definition", () => {
    const resource = toFhirObservation(base, {
      subject: { reference: "Group/g-1" },
    });

    expect(resource.code).toEqual({ text: "Heart rate" });
    expect(resource.subject).toEqual({ reference: "Group/g-1" });
    expect(resource.valueQuantity).toEqual({ value: 72 });
    expect(resource.referenceRange).toBeUndefined();
    expect(resource.performer).toBeUndefined();
  });

  it("maps each value type to its value element", () => {
    expect(
      toFhirObservation({ ...base, valueType: "integer", value: 3 })
        .valueInteger,
    ).toBe(3);
    expect(
      toFhirObservation({
        ...base,
        valueType: "integer",
        value: 3,
        unit: "{score}",
      }).valueQuantity?.value,
    ).toBe(3);
    expect(
      toFhirObservation({ ...base, valueType: "boolean", value: true })
        .valueBoolean,
    ).toBe(true);
    expect(
      toFhirObservation({ ...base, valueType: "code", value: "LA6576-8" })
        .valueCodeableConcept,
    ).toEqual({ coding: [{ code: "LA6576-8" }] });
    expect(
      toFhirObservation({ ...base, valueType: "text", value: "calm" })
        .valueString,
    ).toBe("calm");
  });

  it("leaves the value out when it doesn't match the value type", () => {
    for (const valueType of [
      "number",
      "integer",
      "boolean",
      "code",
      "text",
    ] as const) {
      const resource = toFhirObservation({
        ...base,
        valueType,
        value: valueType === "boolean" ? "yes" : false,
      });

      expect(
        Object.keys(resource).filter((key) => key.startsWith("value")),
      ).toEqual([]);
    }
  });

  it("marks a missing value as data absent", () => {
    expect(
      toFhirObservation({ ...base, value: null }).dataAbsentReason,
    ).toEqual({
      coding: [
        {
          system: "http://terminology.hl7.org/CodeSystem/data-absent-reason",
          code: "unknown",
        },
      ],
    });
  });

  it("maps components with the definition's component codes", () => {
    const resource = toFhirObservation(
      {
        ...base,
        valueType: "components",
        value: { systolic: 120 },
        note: "seated",
        method: "cuff",
        device: "Omron",
      },
      { definition: bloodPressure },
    );

    expect(resource.component).toEqual([
      {
        code: {
          coding: [{ system: LOINC, code: "8480-6", display: "Systolic" }],
          text: "Systolic",
        },
        valueQuantity: {
          value: 120,
          unit: "mm[Hg]",
          system: "http://unitsofmeasure.org",
          code: "mm[Hg]",
        },
      },
      {
        code: {
          coding: [{ system: LOINC, code: "8462-4", display: "Diastolic" }],
          text: "Diastolic",
        },
        dataAbsentReason: {
          coding: [
            {
              system:
                "http://terminology.hl7.org/CodeSystem/data-absent-reason",
              code: "unknown",
            },
          ],
        },
      },
    ]);
    expect(resource.referenceRange).toBeUndefined();
    expect(resource.note).toEqual([{ text: "seated" }]);
    expect(resource.method).toEqual({ text: "cuff" });
    expect(resource.device).toEqual({ display: "Omron" });
  });

  it("names components by key without a definition", () => {
    const resource = toFhirObservation({
      ...base,
      valueType: "components",
      value: { left: 1 },
    });

    expect(resource.component).toEqual([
      { code: { text: "left" }, valueQuantity: { value: 1 } },
    ]);
  });
});

const definitions: readonly FhirImportDefinition[] = [
  {
    key: "heart_rate",
    valueType: "number",
    codeSystem: LOINC,
    code: "8867-4",
    unit: "/min",
  },
  { key: "steps", valueType: "integer", code: "41950-7" },
  { key: "smoker", valueType: "boolean", code: "smoker" },
  { key: "mood", valueType: "code", code: "mood" },
  { key: "remark", valueType: "text", code: "remark" },
  {
    key: "blood_pressure",
    valueType: "components",
    codeSystem: LOINC,
    code: "85354-9",
    unit: "mm[Hg]",
    components: [
      { key: "systolic", code: "8480-6" },
      { key: "diastolic", code: "8462-4" },
    ],
  },
];

const coded = (code: string, system?: string): unknown => ({
  coding: [system === undefined ? { code } : { system, code }],
});

const observation = (fields: Record<string, unknown>): unknown => ({
  resourceType: "Observation",
  id: "ext-1",
  status: "final",
  subject: { reference: "Patient/client-1" },
  effectiveDateTime: AT,
  ...fields,
});

describe("fromFhirObservation", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("reads a quantity as an ingest item for its definition", () => {
    const result = fromFhirObservation(
      observation({
        code: coded("8867-4", LOINC),
        valueQuantity: { value: 72, code: "/min" },
        identifier: [{ value: "dev-9" }],
        method: { text: "palpation" },
        note: [{ text: "after rest" }],
        device: { display: "Watch" },
      }),
      { subjectType: "client", definitions },
    );

    expect(result.ok).toBe(true);
    expect(result.data).toMatchObject({
      subjectType: "client",
      subjectId: "client-1",
      definitionKey: "heart_rate",
      value: 72,
      externalId: "dev-9",
      source: "import",
      method: "palpation",
      note: "after rest",
      device: "Watch",
    });
    expect(result.data?.observedAt?.toString()).toBe(AT);
  });

  it("reads each value type", () => {
    const read = (fields: Record<string, unknown>): unknown =>
      fromFhirObservation(observation(fields), {
        subjectType: "client",
        definitions,
        subjectId: "client-2",
        source: "device",
      }).data?.value;

    expect(read({ code: coded("41950-7"), valueInteger: 5000 })).toBe(5000);
    expect(read({ code: coded("smoker"), valueBoolean: false })).toBe(false);
    expect(
      read({ code: coded("mood"), valueCodeableConcept: coded("happy") }),
    ).toBe("happy");
    expect(read({ code: coded("mood"), valueString: "sad" })).toBe("sad");
    expect(read({ code: coded("remark"), valueString: "ok" })).toBe("ok");
    expect(
      read({
        code: coded("85354-9", LOINC),
        component: [
          {
            code: coded("8480-6", LOINC),
            valueQuantity: { value: 120, unit: "mm[Hg]" },
          },
          { code: coded("8462-4", LOINC), valueQuantity: { value: 80 } },
          { code: coded("other", LOINC), valueQuantity: { value: 1 } },
        ],
      }),
    ).toEqual({ systolic: 120, diastolic: 80 });
  });

  it("takes the time from an instant or a period, and the id as external id", () => {
    const result = fromFhirObservation(
      observation({
        code: coded("smoker"),
        valueBoolean: true,
        effectiveDateTime: undefined,
        effectivePeriod: { start: "2026-10-30T09:00:00+02:00" },
      }),
      { subjectType: "client", definitions },
    );

    expect(result.data?.externalId).toBe("ext-1");
    expect(result.data?.observedAt?.toString()).toBe("2026-10-30T07:00:00Z");
    expect(result.data?.source).toBe("import");
  });

  it("rejects anything but an Observation", () => {
    const result = fromFhirObservation(
      { resourceType: "Patient" },
      { subjectType: "client", definitions },
    );

    expect(result.error).toMatchObject({
      kind: "validation",
      message:
        "The Observation can't be imported: resourceType must be Observation",
      issues: [{ path: ["resourceType"] }],
    });
    expect(
      fromFhirObservation("nope", { subjectType: "client", definitions }).ok,
    ).toBe(false);
  });

  it("lists every problem of a resource it can't store", () => {
    const result = fromFhirObservation(
      {
        resourceType: "Observation",
        status: "registered",
        code: coded("unknown"),
        subject: { reference: "#contained" },
        effectiveDateTime: "2026-10-30",
      },
      { subjectType: "client", definitions },
    );

    expect(result.ok).toBe(false);
    expect(issuesOf(result).map((issue) => issue.path?.join("."))).toEqual([
      "status",
      "code",
      "subject",
      "id",
      "effectiveDateTime",
    ]);
  });

  it("rejects values the definition can't hold", () => {
    const issues = (fields: Record<string, unknown>): unknown =>
      issuesOf(
        fromFhirObservation(observation(fields), {
          subjectType: "client",
          definitions,
        }),
      ).map((issue) => issue.message);

    expect(
      issues({
        code: coded("8867-4", LOINC),
        valueQuantity: { value: 72, code: "/s" },
      }),
    ).toEqual(["value is in /s, the definition in /min"]);
    expect(
      issues({ code: coded("8867-4", LOINC), valueString: "high" }),
    ).toEqual(["value needs a numeric value"]);
    expect(
      issues({ code: coded("41950-7"), valueQuantity: { value: 1.5 } }),
    ).toEqual(["value must be an integer"]);
    expect(issues({ code: coded("smoker"), valueString: "yes" })).toEqual([
      "value must be a boolean",
    ]);
    expect(issues({ code: coded("mood") })).toEqual(["value must be a code"]);
    expect(issues({ code: coded("remark") })).toEqual([
      "value must be a string",
    ]);
    expect(
      issues({
        code: coded("85354-9", LOINC),
        component: ["bad", { code: coded("x") }],
      }),
    ).toEqual(["component has no value the definition knows"]);
  });

  it("returns the Temporal error when the runtime has none", () => {
    vi.stubGlobal("Temporal", undefined);

    const result = fromFhirObservation(
      observation({ code: coded("smoker"), valueBoolean: true }),
      { subjectType: "client", definitions },
    );

    expect(result.error?.kind).toBe("unexpected");
  });
});
