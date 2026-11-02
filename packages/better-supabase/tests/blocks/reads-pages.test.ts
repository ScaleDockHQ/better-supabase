import { describe, expect, it } from "vitest";

import { createBookings } from "../../src/blocks/bookings/bookings.ts";
import { createCare } from "../../src/blocks/care/care.ts";
import { createDocuments } from "../../src/blocks/documents/index.ts";
import { createHiring } from "../../src/blocks/hiring/index.ts";
import { createQualifications } from "../../src/blocks/qualifications/qualifications.ts";
import { AsyncResult } from "../../src/core/result.ts";
import { fieldsTransport } from "./fields-transport.ts";

const AT = "2026-10-29T10:00:00Z";

describe("hiring.board", () => {
  const rows = {
    list_jobs: () => [
      { id: "j1", title: "Engineer", status: "open", fields: {} },
    ],
    list_applications: () => [
      {
        id: "a1",
        job_id: "j1",
        candidate_type: "person",
        candidate_id: "p1",
        stage_id: "s1",
        state: "active",
        created_at: AT,
      },
    ],
  };

  it("reads the job and its stages together", async () => {
    const board = await createHiring({ transport: fieldsTransport(rows) })
      .board({ organizationId: "o", jobId: "j1" })
      .orThrow();

    expect(board.job.title).toBe("Engineer");
    expect(board.stages.map((s) => s.stageId)).toEqual(["s1"]);
  });

  it("is not_found for a job the caller can't see", async () => {
    const result = await createHiring({
      transport: fieldsTransport(rows),
    }).board({ organizationId: "o", jobId: "other" });

    expect(result.ok ? undefined : result.error.kind).toBe("not_found");
  });
});

describe("bookings.page", () => {
  const t = () =>
    fieldsTransport({
      list_booking_services: () => [
        {
          id: "s1",
          name: "Class",
          duration: "01:00:00",
          bufferBefore: "00:00:00",
          bufferAfter: "00:00:00",
          resourceKinds: ["room"],
          active: true,
        },
      ],
      list_booking_resources: () => [
        {
          id: "r1",
          name: "Studio",
          kind: "room",
          capacity: 2,
          tz: "UTC",
          active: true,
        },
      ],
      available_slots: () => [
        {
          resourceId: "r1",
          startsAt: AT,
          endsAt: "2026-10-29T11:00:00Z",
          localStart: "2026-10-29T10:00:00",
          seats: 2,
        },
      ],
    });

  it("adds the slots when a service and range are given", async () => {
    const fake = t();

    const page = await createBookings({ transport: fake })
      .page({
        organizationId: "o",
        serviceId: "s1",
        range: {
          from: Temporal.Instant.from(AT),
          until: Temporal.Instant.from("2026-10-30T10:00:00Z"),
        },
      })
      .orThrow();

    expect(page.services).toHaveLength(1);
    expect(page.resources).toHaveLength(1);
    expect(page.slots).toHaveLength(1);
  });

  it("leaves the slots empty and skips the read without a service", async () => {
    const fake = t();

    const page = await createBookings({ transport: fake })
      .page({ organizationId: "o" })
      .orThrow();

    expect(page.slots).toEqual([]);
    expect(fake.calls.map(([fn]) => fn)).not.toContain("available_slots");
  });
});

describe("qualifications.matrix", () => {
  const type = (key: string) => ({
    id: key,
    organizationId: "o",
    key,
    name: key,
    holderTypes: ["member"],
    evidenceRequired: false,
    createdAt: AT,
    updatedAt: AT,
  });

  it("gives each holder one cell per type", async () => {
    const t = fieldsTransport({
      list_qualification_types: () => [type("forklift"), type("first_aid")],
      qualification_gaps: () => [
        {
          holderType: "member",
          holderId: "u2",
          holderTitle: "Ben",
          typeKey: "forklift",
          typeName: "forklift",
          status: "missing",
        },
      ],
      qualified_holders: (args) =>
        (args as { type_key: string }).type_key === "forklift"
          ? ["u1"]
          : ["u1", "u2"],
    });

    const matrix = await createQualifications({ transport: t })
      .matrix({ organizationId: "o" })
      .orThrow();

    expect(matrix.types.map((x) => x.key)).toEqual(["forklift", "first_aid"]);
    expect(matrix.rows).toEqual([
      {
        holderId: "u2",
        holderTitle: "Ben",
        cells: { forklift: "missing", first_aid: "valid" },
      },
      {
        holderId: "u1",
        holderTitle: "u1",
        cells: { forklift: "valid", first_aid: "valid" },
      },
    ]);
  });
});

describe("documents.page", () => {
  const opened = {
    id: "d1",
    organizationId: "o",
    subjectType: "project",
    subjectId: "p1",
    name: "body",
    topic: "documents:d1",
    canWrite: true,
    createdAt: AT,
    updatedAt: AT,
    snapshot: "AQI=",
    snapshotSeq: "0",
    updates: [],
  };

  it("reads versions and suggestions only when asked", async () => {
    const t = fieldsTransport({
      open_document: () => opened,
      list_document_versions: () => [{ id: "v1", number: 1, createdAt: AT }],
      list_document_suggestions: () => [],
    });

    const documents = createDocuments({ transport: t });

    const ref = {
      organizationId: "o",
      subjectType: "project",
      subjectId: "p1",
    };

    const bare = await documents.page(ref).orThrow();

    const full = await documents
      .page({ ...ref, versions: true, suggestions: true })
      .orThrow();

    expect(bare.versions).toEqual([]);
    expect(full.versions).toHaveLength(1);
    expect(full.id).toBe("d1");
    expect(t.calls.map(([fn]) => fn)).toEqual([
      "open_document",
      "open_document",
      "list_document_versions",
      "list_document_suggestions",
    ]);
  });
});

describe("care.dossier", () => {
  const stub =
    <T>(value: T) =>
    () =>
      AsyncResult.ok(value);

  // SAFETY: the dossier calls only the five reads stubbed here.
  const parts = {
    "care-plans": { list: stub([{ id: "cp1" }]) },
    observations: { latest: stub({ weight: { id: "ob1" } }) },
    medications: { ordersOf: stub([{ id: "mo1" }]) },
    consents: { list: stub([{ id: "c1" }]) },
    funding: { awardsWithUsage: stub([]) },
  } as unknown as Parameters<typeof createCare>[0]["parts"];

  it("reads the five parts together", async () => {
    const care = createCare({ parts } as Parameters<typeof createCare>[0]);

    const dossier = await care
      .dossier({ organizationId: "o", subject: { type: "client", id: "k1" } })
      .orThrow();

    expect(dossier).toMatchObject({
      plans: [{ id: "cp1" }],
      latestObservations: { weight: { id: "ob1" } },
      orders: [{ id: "mo1" }],
      consents: [{ id: "c1" }],
      funding: [],
    });
  });
});
