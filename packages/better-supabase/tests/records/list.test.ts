import { Temporal } from "temporal-polyfill";
import { describe, expect, expectTypeOf, it, vi } from "vitest";

import type { DbError } from "../../src/core/errors.ts";
import type { AsyncResult } from "../../src/core/result.ts";
import type { SubjectRef } from "../../src/schema/types.ts";

import { defineBlock } from "../../src/blocks/define-block.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { defineListQuery } from "../../src/list/index.ts";
import {
  defineRecordFeature,
  defineRecordList,
  defineSection,
  loadTimeline,
  timelineSections,
} from "../../src/records/index.ts";
import { capturingClient } from "../fixtures/client.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { failed, resolved } from "../fixtures/ports.ts";

const betterSupabase = defineSupabase(schema);

const customers = defineListQuery(betterSupabase, "customers", {
  search: ["name"],
  sorts: { name: [{ name: "asc" }, { id: "asc" }] },
  defaultSort: "name",
  pagination: "offset",
});

interface Note {
  readonly id: string;
  readonly at: Temporal.Instant;
  readonly by?: string;
}

interface Notes {
  list(subject: SubjectRef): AsyncResult<readonly Note[]>;
  counts(
    subjects: readonly SubjectRef[],
  ): AsyncResult<Readonly<Record<string, number>>>;
}

interface Labels {
  of(subject: SubjectRef): AsyncResult<readonly string[]>;
}

const at = (iso: string) => Temporal.Instant.from(iso);

const notesBlock = defineBlock({
  name: "notes",
  sql: ["notes"],
  category: "collaboration",
  sections: {
    notes: defineSection({
      permissions: { read: "read" },
      load: (client: Notes, subject) => client.list(subject),
      count: (client: Notes, subjects) => client.counts(subjects),
      timeline: (notes) =>
        notes.map((note) => ({
          id: note.id,
          kind: "note",
          at: note.at,
          ...(note.by === undefined ? {} : { actor: note.by }),
          row: note,
        })),
    }),
  },
});

const labelsBlock = defineBlock({
  name: "labels",
  sql: ["labels"],
  category: "collaboration",
  sections: {
    labels: defineSection({
      permissions: { read: "view" },
      load: (client: Labels, subject) => client.of(subject),
    }),
    stars: defineSection({
      permissions: { read: "view" },
      load: () => resolved(0),
      column: (_client: Labels, subjects) =>
        resolved(
          Object.fromEntries(
            subjects.map((subject) => [`${subject.type}:${subject.id}`, 5]),
          ),
        ),
    }),
  },
});

const feature = defineRecordFeature({
  type: "customer",
  blocks: { notes: notesBlock, labels: labelsBlock },
  permissions: { labels: { view: "labels.view" } },
});

const notes: Notes = {
  list: (subject) =>
    subject.id === "c2"
      ? resolved([
          { id: "n2", at: at("2026-10-02T00:00:00Z"), by: "u1" },
          { id: "n1", at: at("2026-10-01T00:00:00Z") },
        ])
      : resolved([]),
  counts: (subjects) =>
    resolved(subjects[0] === undefined ? {} : { "customer:c1": 2 }),
};

const labels: Labels = {
  of: (subject) =>
    subject.id === "bad" ? failed("No labels") : resolved([`l-${subject.id}`]),
};

function database(rows: readonly { readonly id: string }[]) {
  const { client, requests } = capturingClient(() => ({
    body: rows,
    headers: { "content-range": `0-${rows.length - 1}/${rows.length}` },
  }));

  return { db: betterSupabase.connect(client), requests };
}

describe("defineRecordList", () => {
  const list = defineRecordList(feature, customers, {
    columns: { notes: "count", labels: "data", stars: "data" },
  });

  it("runs the list and fills each column for the whole page", async () => {
    const { db } = database([{ id: "c1" }, { id: "c2" }]);

    const page = await list
      .load({ db, clients: { notes, labels } }, { q: "acme" })
      .orThrow();

    expect(page.query).toMatchObject({ q: "acme", sort: "name" });
    expect(page.page).toMatchObject({ page: { number: 1 } });
    expect(page.rows.map((row) => row.cells)).toEqual([
      {
        notes: { kind: "ok", data: 2 },
        labels: { kind: "ok", data: ["l-c1"] },
        stars: { kind: "ok", data: 5 },
      },
      {
        notes: { kind: "ok", data: 0 },
        labels: { kind: "ok", data: ["l-c2"] },
        stars: { kind: "ok", data: 5 },
      },
    ]);
    expect(page.rows[0]?.subject).toEqual({ type: "customer", id: "c1" });
    expect(page.can.labels.read).toBe(true);
    expectTypeOf(page.rows[0]!.cells.notes).toEqualTypeOf<
      | { readonly kind: "ok"; readonly data: number }
      | { readonly kind: "error"; readonly error: DbError }
      | { readonly kind: "hidden" }
    >();
  });

  it("hides a column the caller can't read and settles a failed one", async () => {
    const { db } = database([{ id: "bad" }]);

    const hidden = await list
      .load(
        {
          db,
          clients: { notes, labels },
          permissions: { tenant: "t", keys: [] },
        },
        undefined,
      )
      .orThrow();

    expect(hidden.rows[0]?.cells.labels).toEqual({ kind: "hidden" });

    const settled = await list
      .load({ db, clients: { notes, labels } }, undefined)
      .orThrow();

    expect(settled.rows[0]?.cells.labels).toMatchObject({
      kind: "error",
      error: { message: "No labels" },
    });
  });

  it("fails on bad URL state and on a column without its block", async () => {
    const { db } = database([{ id: "c1" }]);

    expect(
      await list.load({ db, clients: { notes, labels } }, { sort: "nope" }),
    ).toMatchObject({ ok: false, error: { kind: "validation" } });

    const page = await list.load({ db, clients: {} }, undefined).orThrow();

    expect(page.rows[0]?.cells.notes).toMatchObject({
      kind: "error",
      error: { kind: "invalid_request" },
    });
  });

  it("counts only sections that count, and takes a custom id", async () => {
    const counted = defineRecordList(feature, customers, {
      columns: { labels: "count" },
      id: (row) => `x-${row.id}`,
    });

    const { db } = database([{ id: "c1" }]);

    const page = await counted
      .load({ db, clients: { notes, labels } }, undefined)
      .orThrow();

    expect(page.rows[0]?.subject.id).toBe("x-c1");
    expect(page.rows[0]?.cells.labels).toMatchObject({
      kind: "error",
      error: { kind: "unsupported" },
    });
    expect(defineRecordList(feature, customers).columns).toEqual({});
  });
});

describe("loadTimeline", () => {
  const source = { blocks: feature.blocks, clients: { notes, labels } };
  const subject = { type: "customer", id: "c2" } as const;

  it("merges every timeline section, newest first", async () => {
    expect(timelineSections(feature.blocks)).toEqual(["notes"]);

    const timeline = await loadTimeline(source, subject);

    expect(
      timeline.entries.map((entry) => [entry.section, entry.id, entry.actor]),
    ).toEqual([
      ["notes", "n2", "u1"],
      ["notes", "n1", undefined],
    ]);
    expect(timeline.skipped).toEqual({});
    expect(
      (await loadTimeline(source, subject, { limit: 1 })).entries,
    ).toHaveLength(1);
  });

  it("skips a hidden or failing section", async () => {
    const hidden = await loadTimeline(source, subject, { can: () => false });

    expect(hidden).toEqual({
      entries: [],
      skipped: { notes: { kind: "hidden" } },
    });

    const broken = vi.fn(() => failed("Down"));

    const failing = await loadTimeline(
      {
        blocks: feature.blocks,
        clients: { notes: { ...notes, list: broken } },
      },
      subject,
      { sections: ["notes", "labels"] },
    );

    expect(failing.skipped["notes"]).toMatchObject({ kind: "error" });
    expect(failing.skipped["labels"]).toMatchObject({ kind: "error" });
  });

  it("orders entries at the same time by section and id", async () => {
    const same = at("2026-10-03T00:00:00Z");

    const twins: Notes = {
      ...notes,
      list: () =>
        resolved([
          { id: "b", at: same },
          { id: "a", at: same },
        ]),
    };

    const timeline = await loadTimeline(
      { blocks: feature.blocks, clients: { notes: twins, labels } },
      subject,
    );

    expect(timeline.entries.map((entry) => entry.id)).toEqual(["a", "b"]);
  });
});
