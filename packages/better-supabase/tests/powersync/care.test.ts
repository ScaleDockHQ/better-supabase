import type { SQLInputValue } from "node:sqlite";

import { DatabaseSync } from "node:sqlite";
import { describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type {
  CrudEntryLike,
  PowerSyncDatabaseLike,
} from "../../src/powersync/index.ts";

import { dbError } from "../../src/core/errors.ts";
import { err, ok } from "../../src/core/result.ts";
import {
  activityLinksRoute,
  careUploadOutcome,
  medicationAdministrationRoute,
  observationRoute,
  progressNoteRoute,
} from "../../src/powersync/index.ts";

const sqlite = new DatabaseSync(":memory:");

sqlite.exec(`
  CREATE TABLE engagement_subjects (activity_id TEXT, subject_type TEXT, subject_id TEXT, position INTEGER);
  CREATE TABLE observation_definitions (id TEXT, "key" TEXT, value_type TEXT);
  INSERT INTO engagement_subjects VALUES ('n1', 'case', 'c2', 1), ('n1', 'client', 'c1', 0);
  INSERT INTO observation_definitions VALUES ('d1', 'heart_rate', 'number'), ('d2', 'blood_pressure', 'components');
`);

const database = {
  getAll: (sql: string, parameters: readonly unknown[] = []) =>
    Promise.resolve(
      // SAFETY: node:sqlite returns plain rows; the route reads them as records.
      sqlite.prepare(sql).all(...(parameters as SQLInputValue[])) as never,
    ),
} as unknown as PowerSyncDatabaseLike;

const entry = (
  op: CrudEntryLike["op"],
  id: string,
  opData?: Record<string, unknown>,
): CrudEntryLike => ({
  op,
  table: "t",
  id,
  ...(opData === undefined ? {} : { opData }),
});

const recorder = (answer: Result<unknown> = ok({})) => {
  const calls: [string, ...unknown[]][] = [];

  const call =
    (name: string) =>
    (...args: unknown[]) => {
      calls.push([name, ...args]);

      return Promise.resolve(answer);
    };

  return { calls, call };
};

describe("careUploadOutcome", () => {
  const outcome = (hint: string) =>
    careUploadOutcome(dbError("conflict", "x", { hint }), entry("PATCH", "a"));

  it("turns clinical conflicts into conflicts the nurse sees", () => {
    for (const hint of [
      "MEDICATION_ADMINISTRATION_INVALID",
      "ACTIVITY_LOCKED",
      "OBSERVATION_NOT_FOUND",
    ]) {
      expect(outcome(hint)).toBe("conflict");
    }
  });

  it("leaves every other error to the default", () => {
    expect(outcome("SOMETHING_ELSE")).toBeUndefined();
  });
});

describe("progressNoteRoute", () => {
  it("logs the note on its linked records in order, keyed by the local id", async () => {
    const { calls, call } = recorder();

    const route = progressNoteRoute(
      {
        log: call("log"),
        update: call("update"),
        amend: call("amend"),
        markError: call("markError"),
      },
      database,
    );

    const result = await route(
      entry("PUT", "n1", {
        tenant_id: "org",
        type: "note",
        title: "Morning round",
        body: "Calm",
      }),
    );

    expect(result.ok).toBe(true);

    expect(calls).toEqual([
      [
        "log",
        "org",
        {
          type: "note",
          title: "Morning round",
          body: "Calm",
          externalRef: "n1",
        },
        [
          { type: "client", id: "c1" },
          { type: "case", id: "c2" },
        ],
      ],
    ]);
  });

  it("counts a note that locked meanwhile as applied", async () => {
    const locked = err(
      dbError("conflict", "locked", { hint: "ACTIVITY_LOCKED" }),
    );

    const { call } = recorder(locked);

    const route = progressNoteRoute(
      {
        log: call("log"),
        update: call("update"),
        amend: call("amend"),
        markError: call("markError"),
      },
      database,
    );

    const result = await route(
      entry("PUT", "n1", { tenant_id: "org", type: "note", title: "T" }),
    );

    expect(result.ok).toBe(true);
  });

  it("keeps an edit of a locked note as an addendum", async () => {
    const locked = err(
      dbError("conflict", "locked", { hint: "ACTIVITY_LOCKED" }),
    );

    const { calls, call } = recorder(locked);

    const route = progressNoteRoute(
      {
        log: call("log"),
        update: call("update"),
        amend: call("amend"),
        markError: call("markError"),
      },
      database,
    );

    await route(entry("PATCH", "n1", { body: "More" }));

    expect(calls.map(([name]) => name)).toEqual(["update", "amend"]);
    expect(calls[1]).toEqual(["amend", "n1", "More"]);
  });

  it("marks an error, refuses other notes and deletes", async () => {
    const { calls, call } = recorder();

    const route = progressNoteRoute(
      {
        log: call("log"),
        update: call("update"),
        amend: call("amend"),
        markError: call("markError"),
      },
      database,
    );

    await route(entry("PATCH", "n1", { marked_error_reason: "wrong client" }));

    expect(calls).toEqual([["markError", "n1", "wrong client"]]);

    const call2 = await route(
      entry("PUT", "x", { tenant_id: "org", type: "call", title: "T" }),
    );

    expect(call2.ok).toBe(false);
    expect((await route(entry("DELETE", "n1"))).ok).toBe(false);
  });

  it("has nothing to replay for link rows", async () => {
    expect((await activityLinksRoute()(entry("PUT", "n1:a:b"))).ok).toBe(true);
  });
});

describe("observationRoute", () => {
  const writes = (known: readonly unknown[] = []) => {
    const { calls, call } = recorder();

    return {
      calls,
      route: observationRoute(
        {
          record: call("record"),
          list: () => Promise.resolve(ok(known as never)),
          markError: call("markError"),
        },
        database,
      ),
    };
  };

  it("records a number reading on the definition's key", async () => {
    const { calls, route } = writes();

    await route(
      entry("PUT", "o1", {
        tenant_id: "org",
        definition_id: "d1",
        subject_type: "client",
        subject_id: "c1",
        value_number: 72,
        observed_at: "2026-01-01T08:00:00Z",
      }),
    );

    expect(calls).toHaveLength(1);

    expect(calls[0]?.[2]).toMatchObject({
      definitionKey: "heart_rate",
      value: 72,
      subjectId: "c1",
    });
  });

  it("builds components values from the JSON column", async () => {
    const { calls, route } = writes();

    await route(
      entry("PUT", "o1", {
        tenant_id: "org",
        definition_id: "d2",
        subject_type: "client",
        subject_id: "c1",
        components: '{"systolic":120,"diastolic":80}',
      }),
    );

    expect(calls[0]?.[2]).toMatchObject({
      value: { systolic: 120, diastolic: 80 },
    });
  });

  it("counts an already recorded reading as applied", async () => {
    const { calls, route } = writes([
      { observedAt: Temporal.Instant.from("2026-01-01T08:00:00Z"), value: 72 },
    ]);

    const result = await route(
      entry("PUT", "o1", {
        tenant_id: "org",
        definition_id: "d1",
        subject_type: "client",
        subject_id: "c1",
        value_number: 72,
        observed_at: "2026-01-01T08:00:00Z",
      }),
    );

    expect(result.ok).toBe(true);
    expect(calls).toHaveLength(0);
  });

  it("refuses a reading without a synced definition", async () => {
    const { route } = writes();

    const result = await route(
      entry("PUT", "o1", {
        tenant_id: "org",
        definition_id: "nope",
        subject_type: "client",
        subject_id: "c1",
        value_number: 1,
      }),
    );

    expect(!result.ok && result.error.kind).toBe("invalid_input");
  });

  it("marks an error and refuses other changes", async () => {
    const { calls, route } = writes();

    await route(entry("PATCH", "o1", { status: "error", reason: "wrong arm" }));

    expect(calls).toEqual([["markError", "o1", "wrong arm"]]);
    expect((await route(entry("PATCH", "o1", { note: "x" }))).ok).toBe(false);
    expect((await route(entry("DELETE", "o1"))).ok).toBe(false);
  });
});

describe("medicationAdministrationRoute", () => {
  const setup = () => {
    const { calls, call } = recorder();

    return {
      calls,
      route: medicationAdministrationRoute({
        recordAdministration: call("recordAdministration"),
        recordAsNeeded: call("recordAsNeeded"),
      }),
    };
  };

  it("records a planned dose with its checker", async () => {
    const { calls, route } = setup();

    await route(
      entry("PATCH", "m1", { status: "given", dose: 5, checked_by: "u2" }),
    );

    expect(calls).toEqual([
      [
        "recordAdministration",
        "m1",
        { dose: 5, checkedBy: "u2", status: "given" },
      ],
    ]);
  });

  it("records an as-needed dose and refuses a scheduled insert", async () => {
    const { calls, route } = setup();

    await route(entry("PUT", "m2", { order_id: "o1", reason: "pain" }));

    expect(calls).toEqual([["recordAsNeeded", "o1", { reason: "pain" }]]);

    expect(
      (
        await route(
          entry("PUT", "m3", { scheduled_at: "2026-01-01T08:00:00Z" }),
        )
      ).ok,
    ).toBe(false);
  });

  it("refuses unknown statuses and deletes", async () => {
    const { route } = setup();

    expect((await route(entry("PATCH", "m1", { status: "planned" }))).ok).toBe(
      false,
    );

    expect((await route(entry("DELETE", "m1"))).ok).toBe(false);
  });
});
