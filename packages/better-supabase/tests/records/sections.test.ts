import { describe, expect, expectTypeOf, it, vi } from "vitest";

import type { SectionResult } from "../../src/records/index.ts";
import type { SubjectRef } from "../../src/schema/types.ts";

import { defineBlock } from "../../src/blocks/define-block.ts";
import { AsyncResult, ok } from "../../src/core/result.ts";
import {
  countSection,
  defineSection,
  loadSections,
  sectionCan,
} from "../../src/records/index.ts";
import { failed, resolved } from "../fixtures/ports.ts";

interface Notes {
  list(
    subject: SubjectRef,
    options?: { limit?: number },
  ): AsyncResult<readonly string[]>;
  counts(
    subjects: readonly SubjectRef[],
  ): AsyncResult<Readonly<Record<string, number>>>;
}

const notesBlock = defineBlock({
  name: "notes",
  sql: ["notes"],
  category: "collaboration",
  create: (): Notes => notes,
  sections: {
    notes: defineSection({
      permissions: { read: "read", write: "create" },
      load: (client: Notes, subject, options?: { limit?: number }) =>
        client.list(subject, options),
      count: (client: Notes, subjects) => client.counts(subjects),
      events: ["note.*"],
    }),
  },
});

const labelsBlock = defineBlock({
  name: "labels",
  category: "work",
  create: () => ({ broken: true }),
  sections: {
    labels: defineSection({
      module: "labeling",
      permissions: { read: "view" },
      load: (_client: unknown, subject) =>
        subject.id === "bad"
          ? failed<number>("No labels")
          : resolved(subject.id.length),
    }),
  },
});

const list = vi.fn((subject: SubjectRef, options?: { limit?: number }) =>
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

describe("loadSections", () => {
  it("loads each section settled and typed", async () => {
    const loaded = await loadSections(source, customer, ["notes", "labels"], {
      options: { notes: { limit: 5 } },
    });

    expect(loaded).toEqual({
      notes: { kind: "ok", data: ["7:5"] },
      labels: { kind: "ok", data: 1 },
    });
    expectTypeOf(loaded.notes).toEqualTypeOf<
      SectionResult<readonly string[]>
    >();
    expectTypeOf(loaded.labels).toEqualTypeOf<SectionResult<number>>();
  });

  it("keeps an error to its section", async () => {
    const loaded = await loadSections(source, { type: "customer", id: "bad" }, [
      "notes",
      "labels",
    ]);

    expect(loaded.notes.kind).toBe("ok");
    expect(loaded.labels).toMatchObject({
      kind: "error",
      error: { kind: "not_found" },
    });
  });

  it("hides a section the caller can't read without loading it", async () => {
    list.mockClear();
    const checks: unknown[] = [];

    const loaded = await loadSections(source, customer, ["notes", "labels"], {
      can: (check) => {
        checks.push(check);

        return check.section !== "notes";
      },
    });

    expect(loaded.notes).toEqual({ kind: "hidden" });
    expect(list).not.toHaveBeenCalled();
    expect(checks).toEqual([
      { section: "notes", module: "notes", action: "read" },
      { section: "labels", module: "labeling", action: "view" },
    ]);
  });

  it("fails a section whose block isn't built or that no block has", async () => {
    const loaded = await loadSections({ blocks, clients: {} }, customer, [
      "notes",
    ]);

    expect(loaded.notes).toMatchObject({
      kind: "error",
      error: { kind: "invalid_request" },
    });

    const unknown = await loadSections(source, customer, [
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
      sections: {
        bare: defineSection({
          permissions: { read: "read" },
          load: () => AsyncResult.from(() => Promise.resolve(ok(true))),
        }),
      },
    });

    await loadSections(
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

describe("sectionCan", () => {
  const permissions = { notes: { read: "notes.read" } };

  it("asks for the key the module's action names", () => {
    const can = sectionCan({ tenant: "o", keys: ["notes.*"] }, permissions);

    expect(can({ section: "notes", module: "notes", action: "read" })).toBe(
      true,
    );
    expect(
      sectionCan(
        { tenant: "o", keys: [] },
        permissions,
      )({ section: "notes", module: "notes", action: "read" }),
    ).toBe(false);
  });

  it("allows an action without a key", () => {
    const can = sectionCan(null, permissions);

    expect(can({ section: "x", module: "other", action: "read" })).toBe(true);
    expect(can({ section: "x", module: "notes", action: "write" })).toBe(true);
  });
});

describe("countSection", () => {
  it("counts rows per subject key", async () => {
    const result = await countSection(source, "notes", [customer]);

    expect(result.ok && result.data).toEqual({ "customer:7": 1 });
  });

  it("fails a section without count", async () => {
    const result = await countSection(source, "labels", [customer]);

    expect(result.ok).toBe(false);
    expect(!result.ok && result.error.kind).toBe("unsupported");
  });
});
