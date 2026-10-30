import * as v from "valibot";
import { describe, expect, it } from "vitest";

import {
  createObservations,
  observationDefinitionInputSchema,
  observationInputSchema,
  observationsBlock,
} from "../../../src/blocks/observations/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-30T08:00:00Z";

const DEFINITION = {
  id: "d1",
  organizationId: null,
  system: true,
  key: "blood_pressure",
  title: "Blood pressure",
  valueType: "components",
  unit: "mm[Hg]",
  codeSystem: "http://loinc.org",
  code: "85354-9",
  components: [
    {
      key: "systolic",
      title: "Systolic",
      code: "8480-6",
      unit: "mm[Hg]",
      referenceLow: 90,
      referenceHigh: 140,
      criticalHigh: 180,
    },
    { key: "diastolic", code: "8462-4", optional: false },
  ],
  decimals: null,
  validLow: null,
  validHigh: null,
  archivedAt: null,
  createdAt: AT,
  updatedAt: AT,
};

const OBSERVATION = {
  id: "o1",
  organizationId: "org-1",
  definitionId: "d2",
  definitionKey: "heart_rate",
  title: "Heart rate",
  valueType: "number",
  unit: "/min",
  subjectType: "patient",
  subjectId: "p1",
  observedAt: AT,
  value: 135,
  flag: "critical_high",
  status: "final",
  replacesId: null,
  reason: null,
  method: "manual",
  device: null,
  source: "manual",
  externalId: null,
  submissionId: null,
  performerId: "u1",
  note: "after a walk",
  createdAt: AT,
  fields: { ward: "north" },
};

const Fields = v.object({ ward: v.picklist(["north", "south"]) });

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

describe("createObservations", () => {
  it("saves, archives and lists definitions", async () => {
    const t = fieldsTransport({
      save_observation_definition: () => ({
        ...DEFINITION,
        id: "d3",
        organizationId: "org-1",
        system: false,
        key: "mews",
        title: "MEWS",
        valueType: "integer",
        components: [],
        validLow: 0,
        validHigh: 14,
        criticalHigh: 7,
      }),
      archive_observation_definition: () => ({ ...DEFINITION, archivedAt: AT }),
      list_observation_definitions: () => [DEFINITION],
    });

    const observations = createObservations({ transport: t });

    const saved = await observations
      .saveDefinition("org-1", "mews", {
        title: "MEWS",
        valueType: "integer",
        validLow: 0,
        validHigh: 14,
        criticalHigh: 7,
      })
      .orThrow();

    const archived = await observations.archiveDefinition("d1").orThrow();

    const listed = await observations
      .definitions("org-1", { includeArchived: true })
      .orThrow();

    expect(saved).toMatchObject({
      key: "mews",
      system: false,
      organizationId: "org-1",
      validLow: 0,
      validHigh: 14,
      criticalHigh: 7,
    });
    expect(archived.archivedAt?.toString()).toBe(AT);
    expect(listed[0]?.components).toEqual([
      {
        key: "systolic",
        title: "Systolic",
        code: "8480-6",
        unit: "mm[Hg]",
        referenceLow: 90,
        referenceHigh: 140,
        criticalHigh: 180,
      },
      { key: "diastolic", code: "8462-4", optional: false },
    ]);
    expect(t.calls).toEqual([
      [
        "save_observation_definition",
        {
          tenant: "org-1",
          key: "mews",
          definition: {
            title: "MEWS",
            valueType: "integer",
            validLow: 0,
            validHigh: 14,
            criticalHigh: 7,
          },
        },
      ],
      ["archive_observation_definition", { definition_id: "d1" }],
      [
        "list_observation_definitions",
        { tenant: "org-1", include_archived: true },
      ],
    ]);
  });

  it("records one and many observations with their extra fields", async () => {
    const t = fieldsTransport({
      record_observations: () => [OBSERVATION, { ...OBSERVATION, id: "o2" }],
    });

    const observations = createObservations({ transport: t, fields: Fields });
    const observedAt = Temporal.Instant.from(AT);

    const recorded = await observations
      .record("org-1", {
        subjectType: "patient",
        subjectId: "p1",
        definitionKey: "heart_rate",
        value: 135,
        observedAt,
        method: "manual",
        note: "after a walk",
        fields: { ward: "north" },
      })
      .orThrow();

    const batch = await observations
      .recordMany("org-1", [
        {
          subjectType: "patient",
          subjectId: "p1",
          definitionKey: "heart_rate",
          value: 135,
          fields: { ward: "north" },
        },
        {
          subjectType: "patient",
          subjectId: "p1",
          definitionKey: "blood_pressure",
          value: { systolic: 120, diastolic: 80 },
          fields: { ward: "north" },
        },
      ])
      .orThrow();

    expect(recorded).toMatchObject({
      id: "o1",
      flag: "critical_high",
      value: 135,
      unit: "/min",
      note: "after a walk",
      fields: { ward: "north" },
    });
    expect(recorded.observedAt.toString()).toBe(AT);
    expect(batch.map((row) => row.id)).toEqual(["o1", "o2"]);
    expect(t.calls).toEqual([
      [
        "record_observations",
        {
          tenant: "org-1",
          items: [
            {
              subjectType: "patient",
              subjectId: "p1",
              definitionKey: "heart_rate",
              value: 135,
              observedAt: AT,
              details: { method: "manual", note: "after a walk" },
              fields: { ward: "north" },
            },
          ],
        },
      ],
      [
        "record_observations",
        {
          tenant: "org-1",
          items: [
            {
              subjectType: "patient",
              subjectId: "p1",
              definitionKey: "heart_rate",
              value: 135,
              details: {},
              fields: { ward: "north" },
            },
            {
              subjectType: "patient",
              subjectId: "p1",
              definitionKey: "blood_pressure",
              value: { systolic: 120, diastolic: 80 },
              details: {},
              fields: { ward: "north" },
            },
          ],
        },
      ],
    ]);
  });

  it("refuses extra fields the schema rejects before calling", async () => {
    const t = fieldsTransport({});
    const observations = createObservations({ transport: t, fields: Fields });

    const result = await observations.record("org-1", {
      subjectType: "patient",
      subjectId: "p1",
      definitionKey: "heart_rate",
      value: 70,
      // SAFETY: a value outside the schema, to show it is refused.
      fields: { ward: "east" } as unknown as { ward: "north" },
    });

    expect(result.ok).toBe(false);
    expect(t.calls).toEqual([]);
  });

  it("ingests device readings by external id", async () => {
    const t = fieldsTransport({
      ingest_observations: () => ({ inserted: 1, skipped: 1, ids: ["o3"] }),
    });

    const observations = createObservations({ transport: t });

    const result = await observations
      .ingest("org-1", [
        {
          subjectType: "patient",
          subjectId: "p1",
          definitionKey: "oxygen_saturation",
          value: 97,
          externalId: "oximeter-1",
          source: "device",
          device: "oximeter",
        },
      ])
      .orThrow();

    expect(result).toEqual({ inserted: 1, skipped: 1, ids: ["o3"] });
    expect(t.calls).toEqual([
      [
        "ingest_observations",
        {
          tenant: "org-1",
          items: [
            {
              subjectType: "patient",
              subjectId: "p1",
              definitionKey: "oxygen_saturation",
              value: 97,
              details: { device: "oximeter" },
              externalId: "oximeter-1",
              source: "device",
            },
          ],
        },
      ],
    ]);
  });

  it("amends and marks observations in error", async () => {
    const t = fieldsTransport({
      amend_observation: () => ({
        ...OBSERVATION,
        id: "o4",
        value: 115,
        flag: "high",
        replacesId: "o1",
        reason: "wrong monitor",
      }),
      mark_observation_error: () => ({
        ...OBSERVATION,
        status: "entered_in_error",
        reason: "cuff too small",
      }),
    });

    const observations = createObservations({ transport: t });

    const amended = await observations
      .amend("o1", { value: 115, note: "rechecked" }, "wrong monitor")
      .orThrow();

    const marked = await observations
      .markError("o1", "cuff too small")
      .orThrow();

    expect(amended).toMatchObject({
      replacesId: "o1",
      reason: "wrong monitor",
      flag: "high",
    });
    expect(marked.status).toBe("entered_in_error");
    expect(t.calls).toEqual([
      [
        "amend_observation",
        {
          observation_id: "o1",
          changes: { value: 115, details: { note: "rechecked" } },
          reason: "wrong monitor",
        },
      ],
      [
        "mark_observation_error",
        { observation_id: "o1", reason: "cuff too small" },
      ],
    ]);
  });

  it("lists, charts and summarizes a record's observations", async () => {
    const t = fieldsTransport({
      list_observations: () => [OBSERVATION],
      observation_series: (args) =>
        args["bucket"] === null
          ? [{ id: "o1", observedAt: AT, value: 72, flag: "normal" }]
          : [
              {
                bucket: "2026-10-30T00:00:00Z",
                count: "2",
                min: 72,
                max: "88",
                avg: 80,
                components: { systolic: { min: 120, max: 150, avg: 135 } },
              },
            ],
      latest_observations: () => ({ heart_rate: OBSERVATION }),
      observations_from_submission: () => [OBSERVATION],
    });

    const observations = createObservations({ transport: t });
    const since = Temporal.Instant.from("2026-10-29T00:00:00Z");

    const listed = await observations
      .list("patient", "p1", { definitionKey: "heart_rate", limit: 10 })
      .orThrow();

    const points = await observations
      .series("patient", "p1", "heart_rate", { since })
      .orThrow();

    const buckets = await observations
      .buckets("patient", "p1", "heart_rate", "day")
      .orThrow();

    const latest = await observations.latest("patient", "p1").orThrow();
    const mapped = await observations.fromSubmission("s1").orThrow();

    expect(listed).toHaveLength(1);
    expect(points).toEqual([
      {
        id: "o1",
        observedAt: Temporal.Instant.from(AT),
        value: 72,
        flag: "normal",
      },
    ]);
    expect(buckets[0]).toMatchObject({
      count: 2,
      min: 72,
      max: 88,
      avg: 80,
      components: { systolic: { min: 120, max: 150, avg: 135 } },
    });
    expect(latest["heart_rate"]?.id).toBe("o1");
    expect(mapped).toHaveLength(1);
    expect(t.calls).toEqual([
      [
        "list_observations",
        {
          subject_type: "patient",
          subject_id: "p1",
          definition_key: "heart_rate",
          include_all: false,
          max_rows: 10,
        },
      ],
      [
        "observation_series",
        {
          subject_type: "patient",
          subject_id: "p1",
          definition_key: "heart_rate",
          since: "2026-10-29T00:00:00Z",
          until: null,
          bucket: null,
        },
      ],
      [
        "observation_series",
        {
          subject_type: "patient",
          subject_id: "p1",
          definition_key: "heart_rate",
          since: null,
          until: null,
          bucket: "day",
        },
      ],
      ["latest_observations", { subject_type: "patient", subject_id: "p1" }],
      ["observations_from_submission", { submission_id: "s1" }],
    ]);
  });

  it("rejects a malformed row", async () => {
    const t = fieldsTransport({
      list_observations: () => [{ ...OBSERVATION, flag: "abnormal" }],
    });

    const observations = createObservations({ transport: t });

    const result = await observations.list("patient", "p1");

    expect(result.ok).toBe(false);
  });

  it("runs the hooks", async () => {
    const seen: string[] = [];

    const observations = createObservations({
      transport: fieldsTransport({ latest_observations: () => ({}) }),
      hooks: {
        latest: {
          after: () => {
            seen.push("latest");
          },
        },
      },
    });

    await observations.latest("patient", "p1").orThrow();

    expect(seen).toEqual(["latest"]);
  });
});

describe("observations block", () => {
  it("names the block and validates the inputs", () => {
    expect(observationsBlock.name).toBe("observations");
    expect(
      validate(observationDefinitionInputSchema, {
        title: "MEWS",
        valueType: "integer",
      }).issues,
    ).toBeUndefined();
    expect(
      validate(observationDefinitionInputSchema, {
        title: "MEWS",
        valueType: "score",
      }).issues,
    ).toBeDefined();
    expect(
      validate(observationInputSchema, {
        subjectType: "patient",
        subjectId: "p1",
        definitionKey: "heart_rate",
        value: 72,
      }).issues,
    ).toBeUndefined();
    expect(
      validate(observationInputSchema, {
        subjectType: "",
        subjectId: "p1",
        definitionKey: "heart_rate",
        value: 72,
      }).issues,
    ).toBeDefined();
  });
});
