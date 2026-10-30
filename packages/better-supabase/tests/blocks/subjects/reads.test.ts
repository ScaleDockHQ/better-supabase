import { describe, expect, it } from "vitest";

import { createSubjects } from "../../../src/blocks/subjects/index.ts";

function fakeTransport(results: Readonly<Record<string, unknown>>) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];

  return {
    calls,
    transport: {
      call(
        _schema: string,
        fn: string,
        args: Readonly<Record<string, unknown>>,
      ) {
        calls.push({ fn, args: { ...args } });

        return Promise.resolve(results[fn]);
      },
    },
  };
}

const patient = { type: "patient", id: "p1" };

describe("subjects reads", () => {
  it("logs a read with its purpose", async () => {
    const fake = fakeTransport({ record_subject_read: null });
    const { reads } = createSubjects({ transport: fake.transport });

    const result = await reads.log(patient, { purpose: "treatment" });

    expect(result.ok).toBe(true);
    expect(fake.calls).toEqual([
      {
        fn: "record_subject_read",
        args: {
          subject_type: "patient",
          subject_id: "p1",
          purpose: "treatment",
        },
      },
    ]);
  });

  it("logs a read without a purpose", async () => {
    const fake = fakeTransport({ record_subject_read: null });
    const { reads } = createSubjects({ transport: fake.transport });

    await reads.log(patient).orThrow();

    expect(fake.calls[0]?.args["purpose"]).toBeNull();
  });

  it("lists the read log and reads each entry", async () => {
    const fake = fakeTransport({
      subject_access_log: [
        {
          id: "e1",
          actorId: "u1",
          actorName: "Ann",
          at: "2026-10-30T09:00:00+00:00",
          purpose: "treatment",
          emergency: true,
          block: "subjects",
          function: "record_summary",
        },
        {
          id: "e2",
          actorId: null,
          actorName: null,
          at: "2026-10-30T08:00:00+00:00",
          purpose: null,
          emergency: false,
          block: null,
          function: null,
        },
      ],
    });

    const { reads } = createSubjects({ transport: fake.transport });

    const entries = await reads
      .list(patient, {
        since: Temporal.Instant.from("2026-10-01T00:00:00Z"),
        limit: 10,
      })
      .orThrow();

    expect(fake.calls).toEqual([
      {
        fn: "subject_access_log",
        args: {
          subject_type: "patient",
          subject_id: "p1",
          since: "2026-10-01T00:00:00Z",
          max_rows: 10,
        },
      },
    ]);
    expect(entries).toEqual([
      {
        id: "e1",
        actorId: "u1",
        actorName: "Ann",
        at: Temporal.Instant.from("2026-10-30T09:00:00Z"),
        purpose: "treatment",
        emergency: true,
        block: "subjects",
        function: "record_summary",
      },
      {
        id: "e2",
        at: Temporal.Instant.from("2026-10-30T08:00:00Z"),
        emergency: false,
      },
    ]);
  });

  it("defaults the page and treats a missing list as empty", async () => {
    const fake = fakeTransport({ subject_access_log: null });
    const { reads } = createSubjects({ transport: fake.transport });

    const entries = await reads.list(patient).orThrow();

    expect(entries).toEqual([]);
    expect(fake.calls[0]?.args).toMatchObject({ since: null, max_rows: 100 });
  });

  it("fails on an entry without an instant", async () => {
    const fake = fakeTransport({ subject_access_log: [{ id: "e1" }] });
    const { reads } = createSubjects({ transport: fake.transport });

    const result = await reads.list(patient);

    expect(result.ok).toBe(false);
  });
});
