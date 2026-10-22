import type { StandardSchemaV1 } from "@standard-schema/spec";

import { Temporal } from "temporal-polyfill";
import { describe, expect, expectTypeOf, it } from "vitest";

import type { AsyncResult } from "../../src/core/result.ts";
import type { RecordRef } from "../../src/schema/types.ts";

import { defineBlock } from "../../src/blocks/define-block.ts";
import { entitySchema } from "../../src/blocks/entity-schema.ts";
import { featureWrites, runSectionWrite } from "../../src/records/feature.ts";
import {
  defineRecordFeature,
  defineSection,
  findSectionWrite,
  plainData,
  recordCan,
  recordPermissionKeys,
  recordWriteInput,
  sectionRowInput,
} from "../../src/records/index.ts";
import { resolved } from "../fixtures/ports.ts";

interface Note {
  readonly id: string;
  readonly at: Temporal.Instant;
}

interface Notes {
  list(subject: RecordRef): AsyncResult<readonly Note[]>;
  add(subject: RecordRef, body: string): AsyncResult<Note>;
  remove(id: string): AsyncResult<boolean>;
}

const noteInput = entitySchema<{ readonly body: string }>({
  title: "NoteInput",
  fields: { body: { kind: "string", minLength: 1 } },
});

const notesSection = defineSection({
  permissions: { read: "read", write: "create" },
  load: (client: Notes, subject) => client.list(subject),
  writes: {
    add: {
      input: noteInput,
      run: (
        client: Notes,
        subject: RecordRef,
        input: { readonly body: string },
      ) => client.add(subject, input.body),
    },
    remove: {
      permission: "moderate",
      input: sectionRowInput,
      run: (
        client: Notes,
        _subject: RecordRef,
        { id }: { readonly id: string },
      ) => client.remove(id),
    },
  },
});

const notesBlock = defineBlock({
  name: "notes",
  sql: ["notes"],
  category: "collaboration",
  sections: { notes: notesSection },
});

const otherNotesBlock = defineBlock({
  name: "other",
  sql: ["other"],
  category: "collaboration",
  sections: {
    notes: notesSection,
    labels: defineSection({
      permissions: { read: "view" },
      load: () => resolved(1),
    }),
  },
});

const permissions = {
  notes: {
    read: "notes.read",
    create: "notes.create",
    moderate: "notes.moderate",
  },
};

const feature = defineRecordFeature({
  type: "customer",
  blocks: { notes: notesBlock, other: otherNotesBlock },
  permissions,
});

describe("defineRecordFeature", () => {
  it("lists every section once, the first block winning a name", () => {
    expect(feature.sections).toEqual(["notes", "labels"]);
    expectTypeOf(feature.sections).toEqualTypeOf<
      readonly ("notes" | "labels")[]
    >();
  });

  it("collects the permission keys its sections check", () => {
    expect(recordPermissionKeys(feature)).toEqual([
      "notes.read",
      "notes.create",
      "notes.moderate",
    ]);
  });
});

describe("recordCan", () => {
  it("maps each section's read and writes to the caller's keys", () => {
    const can = recordCan(feature, {
      tenant: "t",
      keys: ["notes.read", "notes.create"],
    });

    expect(can).toEqual({
      notes: { read: true, add: true, remove: false },
      labels: { read: true },
    });
    expectTypeOf(can.notes).toEqualTypeOf<
      { readonly read: boolean } & {
        readonly add: boolean;
        readonly remove: boolean;
      }
    >();
  });

  it("allows everything without a permission set and nothing on a failed one", () => {
    expect(recordCan(feature, undefined).notes.remove).toBe(true);
    expect(recordCan(feature, null).notes).toEqual({
      read: false,
      add: false,
      remove: false,
    });
  });
});

describe("recordWriteInput", () => {
  const schema = recordWriteInput(noteInput);

  it("validates the record id and the write's input", async () => {
    expect(
      await schema["~standard"].validate({ id: "7", input: { body: "Hi" } }),
    ).toEqual({ value: { id: "7", input: { body: "Hi" } } });
    expect(
      await schema["~standard"].validate({ id: "", input: { body: "Hi" } }),
    ).toMatchObject({ issues: [{ path: ["id"] }] });
    expect(
      await schema["~standard"].validate({ id: "7", input: { body: "" } }),
    ).toMatchObject({ issues: [{ path: ["input", "body"] }] });
    expect(await schema["~standard"].validate("7")).toMatchObject({
      issues: [{ message: "Expected an object" }],
    });
  });
});

describe("plainData", () => {
  it("turns Temporal values into ISO strings, deeply", () => {
    const at = Temporal.Instant.from("2026-10-21T10:00:00Z");

    const plain = plainData({
      ok: true,
      rows: [{ id: "1", at, count: 2n, when: null }],
    });

    expect(plain).toEqual({
      ok: true,
      rows: [{ id: "1", at: "2026-10-21T10:00:00Z", count: 2n, when: null }],
    });
    expectTypeOf(plain.rows[0]?.at).toEqualTypeOf<string | undefined>();
  });
});

describe("feature edges", () => {
  const plainBlock = defineBlock({
    name: "plain",
    sql: ["plain"],
    category: "collaboration",
  });

  const bare = defineRecordFeature({
    type: "customer",
    blocks: { plain: plainBlock, notes: notesBlock },
  });

  it("skips blocks without sections and keys without a permissions map", () => {
    expect(bare.sections).toEqual(["notes"]);
    expect(recordPermissionKeys(bare)).toEqual([]);
    expect(featureWrites(bare)).toEqual([["notes", ["add", "remove"]]]);
  });

  it("finds a write only on a known section", () => {
    expect(findSectionWrite(bare, "notes", "add")).toMatchObject({
      key: "notes",
      permission: "create",
    });
    expect(findSectionWrite(bare, "notes", "rename")).toBeUndefined();
    expect(findSectionWrite(bare, "files", "add")).toBeUndefined();
  });

  it("fails a write without a client for its block", async () => {
    const result = await runSectionWrite(
      bare,
      {},
      "notes",
      "add",
      { type: "customer", id: "7" },
      { body: "Hi" },
    );

    expect(result).toMatchObject({ ok: false });
  });
});

describe("recordWriteInput edges", () => {
  const asyncSchema: StandardSchemaV1<unknown, { readonly n: number }> = {
    "~standard": {
      version: 1,
      vendor: "test",
      validate: (value) =>
        Promise.resolve(
          typeof value === "object" && value !== null && "n" in value
            ? { value: { n: Number(value.n) } }
            : { issues: [{ message: "Needs n" }] },
        ),
    },
  };

  const schema = recordWriteInput(asyncSchema);

  it("awaits an async input schema and defaults a missing input", async () => {
    expect(
      await schema["~standard"].validate({ id: "7", input: { n: 2 } }),
    ).toEqual({ value: { id: "7", input: { n: 2 } } });
    expect(await schema["~standard"].validate({ id: "7" })).toEqual({
      issues: [{ message: "Needs n", path: ["input"] }],
    });
  });
});
