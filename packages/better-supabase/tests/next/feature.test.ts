import type { StandardSchemaV1 } from "@standard-schema/spec";

import { Temporal } from "temporal-polyfill";
import { describe, expect, expectTypeOf, it, vi } from "vitest";

import type { BlockClientSource } from "../../src/blocks/create-blocks.ts";
import type { DbError } from "../../src/core/errors.ts";
import type { AsyncResult } from "../../src/core/result.ts";
import type { RecordServerHost } from "../../src/next/feature.ts";
import type { createNext } from "../../src/next/index.ts";
import type { SubjectRef } from "../../src/schema/types.ts";
import type { ActionResult } from "../../src/server/kit.ts";

import { defineBlock } from "../../src/blocks/define-block.ts";
import { entitySchema } from "../../src/blocks/entity-schema.ts";
import { recordServer } from "../../src/next/index.ts";
import {
  defineRecordFeature,
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
  list(subject: SubjectRef): AsyncResult<readonly Note[]>;
  add(subject: SubjectRef, body: string): AsyncResult<Note>;
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

const notesBlock = defineBlock({
  name: "notes",
  sql: ["notes"],
  category: "collaboration",
  create: (): Notes => notes,
  sections: {
    notes: defineSection({
      permissions: { read: "read", write: "create" },
      load: (client: Notes, subject) => client.list(subject),
      writes: {
        add: {
          input: entitySchema<{ readonly body: string }>({
            title: "NoteInput",
            fields: { body: { kind: "string", minLength: 1 } },
          }),
          run: (
            client: Notes,
            subject: SubjectRef,
            input: { readonly body: string },
          ) => client.add(subject, input.body),
        },
        remove: {
          permission: "moderate",
          input: sectionRowInput,
          run: (
            client: Notes,
            _subject: SubjectRef,
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
    keys: keys.filter((key) => key !== "notes.moderate"),
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

const host: RecordServerHost = {
  context: () => Promise.resolve({ db }),
  action:
    <S extends StandardSchemaV1, T>(
      options: { readonly input: S },
      fn: (
        input: StandardSchemaV1.InferOutput<S>,
        ctx: { readonly db: typeof db; readonly tenant: string },
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

      const result = (await fn(checked.value, { db, tenant: "org" })) as {
        ok: boolean;
        data?: unknown;
        error?: unknown;
      };

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
      ["bs:record@org:customer:7#notes"],
      ["bs:record@org:customer:7"],
    ]);

    mocks.updateTag.mockClear();

    expect(
      await customer.actions.notes.add({ id: "7", input: { body: "fail" } }),
    ).toMatchObject({ ok: false });
    expect(mocks.updateTag).not.toHaveBeenCalled();
  });

  it("lists the record's cache tags", () => {
    expect(customer.tags("7", "org")).toEqual([
      "bs:record@org:customer:7",
      "bs:record@org:customer:7#notes",
    ]);
  });

  it("accepts the bs that createNext returns", () => {
    expectTypeOf<ReturnType<typeof createNext>>().toExtend<RecordServerHost>();
  });
});
