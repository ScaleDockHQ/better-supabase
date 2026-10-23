import { describe, expect, expectTypeOf, it, vi } from "vitest";

import type { RecordBindingResult } from "../../src/records/index.ts";
import type { RecordRef } from "../../src/schema/types.ts";

import { defineBlock } from "../../src/blocks/define-block.ts";
import { AsyncResult, ok } from "../../src/core/result.ts";
import {
  countBinding,
  defineRecordBinding,
  loadBindings,
  bindingCan,
} from "../../src/records/index.ts";
import { failed, resolved } from "../fixtures/ports.ts";

interface Notes {
  list(
    subject: RecordRef,
    options?: { limit?: number },
  ): AsyncResult<readonly string[]>;
  counts(
    subjects: readonly RecordRef[],
  ): AsyncResult<Readonly<Record<string, number>>>;
}

const notesBlock = defineBlock({
  name: "notes",
  sql: ["notes"],
  category: "collaboration",
  create: (): Notes => notes,
  record: defineRecordBinding({
    permissions: { read: "read", write: "create" },
    load: (client: Notes, subject, options?: { limit?: number }) =>
      client.list(subject, options),
    count: (client: Notes, subjects) => client.counts(subjects),
    events: ["note.*"],
  }),
});

const labelsBlock = defineBlock({
  name: "labels",
  category: "work",
  create: () => ({ broken: true }),
  record: defineRecordBinding({
    module: "labeling",
    permissions: { read: "view" },
    load: (_client: unknown, subject) =>
      subject.id === "bad"
        ? failed<number>("No labels")
        : resolved(subject.id.length),
  }),
});

const list = vi.fn((subject: RecordRef, options?: { limit?: number }) =>
  resolved([`${subject.id}:${options?.limit ?? "all"}`]),
);

const notes: Notes = {
  list,
  counts: (subjects) =>
    resolved(
      Object.fromEntries(
        subjects.map((each) => [`${each.type}:${each.id}`, 1]),
      ),
    ),
};

const blocks = { notes: notesBlock, labels: labelsBlock };
const source = { blocks, clients: { notes, labels: {} } };
const customer = { type: "customer", id: "7" };

describe("loadBindings", () => {
  it("loads each binding settled and typed", async () => {
    const loaded = await loadBindings(source, customer, ["notes", "labels"], {
      options: { notes: { limit: 5 } },
    });

    expect(loaded).toEqual({
      notes: { kind: "ok", data: ["7:5"] },
      labels: { kind: "ok", data: 1 },
    });
    expectTypeOf(loaded.notes).toEqualTypeOf<
      RecordBindingResult<readonly string[]>
    >();
    expectTypeOf(loaded.labels).toEqualTypeOf<RecordBindingResult<number>>();
  });

  it("keeps an error to its binding", async () => {
    const loaded = await loadBindings(source, { type: "customer", id: "bad" }, [
      "notes",
      "labels",
    ]);

    expect(loaded.notes.kind).toBe("ok");
    expect(loaded.labels).toMatchObject({
      kind: "error",
      error: { kind: "not_found" },
    });
  });

  it("hides a binding the caller can't read without loading it", async () => {
    list.mockClear();
    const checks: unknown[] = [];

    const loaded = await loadBindings(source, customer, ["notes", "labels"], {
      can: (check) => {
        checks.push(check);

        return check.binding !== "notes";
      },
    });

    expect(loaded.notes).toEqual({ kind: "hidden" });
    expect(list).not.toHaveBeenCalled();
    expect(checks).toEqual([
      { binding: "notes", module: "notes", action: "read" },
      { binding: "labels", module: "labeling", action: "view" },
    ]);
  });

  it("fails a binding whose block isn't built or that no block has", async () => {
    const loaded = await loadBindings({ blocks, clients: {} }, customer, [
      "notes",
    ]);

    expect(loaded.notes).toMatchObject({
      kind: "error",
      error: { kind: "invalid_request" },
    });

    const unknown = await loadBindings(source, customer, [
      "missing" as "notes",
    ]);

    expect(unknown).toMatchObject({
      missing: { kind: "error", error: { kind: "invalid_request" } },
    });
  });

  it("falls back to the block key for the module", async () => {
    const checks: string[] = [];

    const bare = defineBlock({
      name: "bare",
      category: "work",
      record: defineRecordBinding({
        permissions: { read: "read" },
        load: () => AsyncResult.from(() => Promise.resolve(ok(true))),
      }),
    });

    await loadBindings(
      { blocks: { bare }, clients: { bare: {} } },
      customer,
      ["bare"],
      {
        can: ({ module }) => {
          checks.push(module);

          return true;
        },
      },
    );

    expect(checks).toEqual(["bare"]);
  });
});

describe("bindingCan", () => {
  const permissions = { notes: { read: "notes.read" } };

  it("asks for the key the module's action names", () => {
    const can = bindingCan({ tenant: "o", keys: ["notes.*"] }, permissions);

    expect(can({ binding: "notes", module: "notes", action: "read" })).toBe(
      true,
    );
    expect(
      bindingCan(
        { tenant: "o", keys: [] },
        permissions,
      )({ binding: "notes", module: "notes", action: "read" }),
    ).toBe(false);
  });

  it("allows an action without a key", () => {
    const can = bindingCan(null, permissions);

    expect(can({ binding: "x", module: "other", action: "read" })).toBe(true);
    expect(can({ binding: "x", module: "notes", action: "write" })).toBe(true);
  });
});

describe("countBinding", () => {
  it("counts rows per subject key", async () => {
    const result = await countBinding(source, "notes", [customer]);

    expect(result.ok && result.data).toEqual({ "customer:7": 1 });
  });

  it("fails a binding without count", async () => {
    const result = await countBinding(source, "labels", [customer]);

    expect(result.ok).toBe(false);
    expect(!result.ok && result.error.kind).toBe("unsupported");
  });
});
