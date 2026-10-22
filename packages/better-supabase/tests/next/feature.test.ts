import type { StandardSchemaV1 } from "@standard-schema/spec";

import { Temporal } from "temporal-polyfill";
import { describe, expect, expectTypeOf, it, vi } from "vitest";

import type { BlockClientSource } from "../../src/blocks/create-blocks.ts";
import type { DbError } from "../../src/core/errors.ts";
import type { AsyncResult } from "../../src/core/result.ts";
import type { RecordServerHost } from "../../src/next/feature.ts";
import type { createNext } from "../../src/next/index.ts";
import type { RecordListQuery } from "../../src/records/index.ts";
import type { RecordRef } from "../../src/schema/types.ts";
import type { ActionResult } from "../../src/server/kit.ts";

import { defineBlock } from "../../src/blocks/define-block.ts";
import { entitySchema } from "../../src/blocks/entity-schema.ts";
import { recordListServer, recordServer } from "../../src/next/index.ts";
import {
  defineRecordFeature,
  defineRecordList,
  defineSection,
  sectionRowInput,
} from "../../src/records/index.ts";
import { failed, resolved } from "../fixtures/ports.ts";

const mocks = vi.hoisted(() => ({
  updateTag: vi.fn<(tag: string) => undefined>(),
}));

vi.mock(import("next/cache.js"), () => ({
  updateTag: mocks.updateTag,
  revalidateTag: vi.fn(),
  cacheTag: vi.fn(),
  cacheLife: () => undefined,
}));

interface Note {
  readonly id: string;
  readonly at: Temporal.Instant;
}

interface Notes {
  list(subject: RecordRef): AsyncResult<readonly Note[]>;
  add(subject: RecordRef, body: string): AsyncResult<Note>;
  remove(id: string): AsyncResult<boolean>;
}

const AT = Temporal.Instant.from("2026-10-21T10:00:00Z");

const notes: Notes = {
  list: (subject) =>
    subject.id === "bad"
      ? failed("No notes")
      : resolved([{ id: "n1", at: AT }]),
  add: (_subject, body) =>
    body === "fail" ? failed("Refused") : resolved({ id: "n2", at: AT }),
  remove: () => resolved(true),
};

const createNotes = vi.fn((_options: Record<string, unknown>): Notes => notes);

const notesBlock = defineBlock({
  name: "notes",
  sql: ["notes"],
  category: "collaboration",
  create: createNotes,
  sections: {
    notes: defineSection({
      permissions: { read: "read", write: "create" },
      load: (client: Notes, subject) => client.list(subject),
      timeline: (rows: readonly Note[]) =>
        rows.map((row) => ({ id: row.id, kind: "note", at: row.at, row })),
      writes: {
        add: {
          input: entitySchema<{ readonly body: string }>({
            title: "NoteInput",
            fields: { body: { kind: "string", minLength: 1 } },
          }),
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
    }),
  },
});

interface Keys {
  permissions(
    keys: readonly string[],
  ): AsyncResult<{ readonly tenant: string; readonly keys: readonly string[] }>;
}

const permissionsCall = vi.fn((keys: readonly string[]) =>
  resolved({
    tenant: "org",
    keys: keys.filter(
      (key) => key !== "notes.moderate" && key !== "notes.hidden",
    ),
  }),
);

const accessBlock = defineBlock({
  name: "access",
  category: "identity",
  create: (): Keys => ({ permissions: permissionsCall }),
});

const feature = defineRecordFeature({
  type: "customer",
  blocks: { notes: notesBlock },
  permissions: {
    notes: {
      read: "notes.read",
      create: "notes.create",
      moderate: "notes.moderate",
    },
  },
  access: accessBlock,
});

const db = { $context: { tenant: "org" } } as unknown as BlockClientSource;
const supabase = { storage: { from: () => undefined } };

const host: RecordServerHost = {
  context: () => Promise.resolve({ db, supabase }),
  action:
    <S extends StandardSchemaV1, T>(
      options: { readonly input: S },
      fn: (
        input: StandardSchemaV1.InferOutput<S>,
        ctx: {
          readonly db: typeof db;
          readonly supabase: typeof supabase;
          readonly tenant: string;
        },
      ) => Promise<T>,
    ) =>
    async (input: never): Promise<ActionResult<unknown>> => {
      const checked = await options.input["~standard"].validate(input);

      if (checked.issues !== undefined) {
        return {
          ok: false,
          data: null,
          error: { kind: "invalid_request", message: "Invalid" } as never,
        };
      }

      const result = (await fn(checked.value, {
        db,
        supabase,
        tenant: "org",
      })) as { ok: boolean; data?: unknown; error?: unknown };

      return result.ok
        ? { ok: true, data: result.data, error: null }
        : { ok: false, data: null, error: result.error as never };
    },
};

const customer = recordServer(host, feature);

describe("recordServer", () => {
  it("loads sections as plain data with the caller's flags", async () => {
    const view = await customer.load("7");

    expect(permissionsCall).toHaveBeenCalledWith([
      "notes.read",
      "notes.create",
      "notes.moderate",
    ]);
    expect(view).toEqual({
      subject: { type: "customer", id: "7" },
      sections: {
        notes: { kind: "ok", data: [{ id: "n1", at: "2026-10-21T10:00:00Z" }] },
      },
      can: { notes: { read: true, add: true, remove: false } },
    });
    expectTypeOf<
      Extract<typeof view.sections.notes, { readonly kind: "ok" }>["data"]
    >().toEqualTypeOf<{ readonly id: string; readonly at: string }[]>();
    expectTypeOf<
      Extract<typeof view.sections.notes, { readonly kind: "error" }>["error"]
    >().toEqualTypeOf<DbError>();
  });

  it("settles a failed section instead of throwing", async () => {
    const view = await customer.load("bad", { sections: ["notes"] });

    expect(view.sections.notes).toMatchObject({ kind: "error" });
  });

  it("runs a write, returns plain data and drops the section's tags", async () => {
    mocks.updateTag.mockClear();

    const added = await customer.actions.notes.add({
      id: "7",
      input: { body: "Hi" },
    });

    expect(added).toEqual({
      ok: true,
      data: { id: "n2", at: "2026-10-21T10:00:00Z" },
      error: null,
    });
    expect(mocks.updateTag.mock.calls).toEqual([
      ["bsb:record@org:customer:7#notes"],
      ["bsb:record@org:customer:7"],
    ]);

    mocks.updateTag.mockClear();

    expect(
      await customer.actions.notes.add({ id: "7", input: { body: "fail" } }),
    ).toMatchObject({ ok: false });
    expect(mocks.updateTag).not.toHaveBeenCalled();
  });

  it("builds the block clients with the caller's storage", async () => {
    createNotes.mockClear();

    await customer.load("7", { sections: ["notes"] });
    await customer.actions.notes.add({ id: "7", input: { body: "Hi" } });

    expect(createNotes).toHaveBeenCalledTimes(2);

    for (const [options] of createNotes.mock.calls) {
      expect(options).toMatchObject({ storage: supabase.storage });
    }
  });

  it("lists the record's cache tags", () => {
    expect(customer.tags("7", "org")).toEqual([
      "bsb:record@org:customer:7",
      "bsb:record@org:customer:7#notes",
    ]);
  });

  it("accepts the bsb that createNext returns", () => {
    expectTypeOf<ReturnType<typeof createNext>>().toExtend<RecordServerHost>();
  });
});

describe("recordServer without access or storage", () => {
  const bare: RecordServerHost = {
    ...host,
    context: () => Promise.resolve({ db }),
  };

  it("allows every section and builds the clients without storage", async () => {
    createNotes.mockClear();

    const open = recordServer(
      bare,
      defineRecordFeature({
        type: "customer",
        blocks: { notes: notesBlock },
        config: { notes: { schema: "notes", options: {} } },
      }),
    );

    const view = await open.load("7", { options: {} });

    expect(view.can).toEqual({
      notes: { read: true, add: true, remove: true },
    });
    expect(view).not.toHaveProperty("permissionsError");
    expect(createNotes.mock.calls[0]?.[0]).not.toHaveProperty("storage");
  });

  it("reports a failed permission load and hides every section", async () => {
    const refused = defineBlock({
      name: "access",
      category: "identity",
      create: (): Keys => ({ permissions: () => failed("No access") }),
    });

    const closed = recordServer(
      bare,
      defineRecordFeature({
        type: "customer",
        blocks: { notes: notesBlock },
        permissions: { notes: { read: "notes.read" } },
        access: refused,
        config: { notes: { schema: "notes", options: {} } },
      }),
    );

    const view = await closed.load("7");

    expect(view.permissionsError).toMatchObject({ message: "No access" });
    expect(view.can.notes.read).toBe(false);
  });
});

describe("recordServer timeline", () => {
  it("loads the record's timeline as plain data", async () => {
    expect(await customer.timeline("7", { limit: 10 })).toEqual({
      entries: [
        {
          id: "n1",
          kind: "note",
          at: "2026-10-21T10:00:00Z",
          row: { id: "n1", at: "2026-10-21T10:00:00Z" },
          section: "notes",
        },
      ],
      skipped: {},
    });
  });

  it("skips the sections the caller can't read", async () => {
    const hidden = recordServer(
      { ...host, context: () => Promise.resolve({ db }) },
      defineRecordFeature({
        type: "customer",
        blocks: { notes: notesBlock },
        permissions: { notes: { read: "notes.hidden" } },
        access: accessBlock,
      }),
    );

    expect(await hidden.timeline("7")).toEqual({
      entries: [],
      skipped: { notes: { kind: "hidden" } },
    });
  });
});

interface Page {
  readonly items: readonly { readonly id: string }[];
  readonly total: number;
}

const customers: RecordListQuery<{ readonly page: number }, Page> = {
  parse: (input) =>
    (input instanceof URLSearchParams ? input.get("page") : input?.["page"]) ===
    "x"
      ? { ok: false, issues: [{ path: ["page"], message: "Not a page" }] }
      : { ok: true, value: { page: 1 } },
  run: () => resolved({ items: [{ id: "7" }, { id: "8" }], total: 2 }),
  filterFields: () => [],
};

describe("recordListServer", () => {
  const list = recordListServer(
    host,
    defineRecordList(feature, customers, { columns: { notes: "data" } }),
  );

  it("loads a page with its section columns as plain data", async () => {
    const view = await list.load({});

    expect(view).toMatchObject({
      ok: true,
      data: {
        query: { page: 1 },
        page: { total: 2 },
        rows: [
          {
            subject: { type: "customer", id: "7" },
            cells: {
              notes: {
                kind: "ok",
                data: [{ id: "n1", at: "2026-10-21T10:00:00Z" }],
              },
            },
          },
          { subject: { type: "customer", id: "8" } },
        ],
        can: { notes: { read: true, add: true, remove: false } },
      },
    });
  });

  it("returns the error for bad URL state", async () => {
    expect(await list.load({ page: "x" })).toMatchObject({
      ok: false,
      error: { kind: "validation" },
    });
  });

  it("allows every column without an access block", async () => {
    const open = recordListServer(
      { context: () => Promise.resolve({ db }) },
      defineRecordList(
        defineRecordFeature({
          type: "customer",
          blocks: { notes: notesBlock },
        }),
        customers,
        { columns: { notes: "data" } },
      ),
    );

    expect(await open.load(undefined)).toMatchObject({
      ok: true,
      data: { can: { notes: { read: true } } },
    });
  });
});
