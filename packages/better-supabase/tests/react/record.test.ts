import type * as ReactModule from "react";

import { Temporal } from "temporal-polyfill";
import { describe, expect, it, vi } from "vitest";

import type { AuthSnapshot } from "../../src/client/index.ts";
import type { AsyncResult } from "../../src/core/result.ts";
import type { ClientLike } from "../../src/react/hooks.ts";
import type { SubjectRef } from "../../src/schema/types.ts";

import { defineBlock } from "../../src/blocks/define-block.ts";
import { entitySchema } from "../../src/blocks/entity-schema.ts";
import { BetterSupabaseProvider } from "../../src/react/hooks.ts";
import { createRecordProvider } from "../../src/react/record.ts";
import { defineRecordFeature, defineSection } from "../../src/records/index.ts";
import { renderHook } from "../fixtures/hook-runtime.ts";
import { flush, resolved } from "../fixtures/ports.ts";

// vi.mock factories run before the imports above, so they load modules themselves.
vi.mock(import("react"), async (importOriginal) => ({
  ...(await importOriginal<typeof ReactModule>()),
  ...(await import("../fixtures/hook-runtime.ts")).reactHooks,
}));

interface Note {
  readonly id: string;
  readonly at: Temporal.Instant;
}

interface Notes {
  list(subject: SubjectRef): AsyncResult<readonly Note[]>;
  add(subject: SubjectRef, body: string): AsyncResult<Note>;
}

const AT = Temporal.Instant.from("2026-10-21T10:00:00Z");
const rows: Note[] = [{ id: "n1", at: AT }];

const notes: Notes = {
  list: () => resolved([...rows]),
  add: () => {
    const row = { id: `n${rows.length + 1}`, at: AT };
    rows.push(row);

    return resolved(row);
  },
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
      },
    }),
  },
});

const feature = defineRecordFeature({
  type: "customer",
  blocks: { notes: notesBlock },
});

const { RecordProvider, useRecord } = createRecordProvider(feature);

const signedIn: AuthSnapshot = {
  status: "signed-in",
  user: { id: "user-1" },
  claims: { sub: "user-1" },
};

// SAFETY: the provider reads only `supabase`, `auth` and `tenant` here.
const client = {
  supabase: {},
  auth: { current: () => signedIn, subscribe: () => () => undefined },
  tenant: "org-1",
} as unknown as ClientLike;

describe("createRecordProvider", () => {
  it("shows the server's sections, then loads them as plain data", async () => {
    const view = renderHook(() => {
      void BetterSupabaseProvider({ client });
      void RecordProvider({
        id: "c1",
        initial: {
          sections: { notes: { kind: "ok", data: [] } },
          can: { notes: { read: true, add: false } },
        },
      });

      return useRecord();
    }, undefined);

    expect(view.result.state.sections.notes).toEqual({ kind: "ok", data: [] });
    expect(view.result.state.can.notes.add).toBe(false);

    await flush();
    expect(view.result.state.sections.notes).toEqual({
      kind: "ok",
      data: [{ id: "n1", at: "2026-10-21T10:00:00Z" }],
    });
    expect(view.result.state.subject).toEqual({ type: "customer", id: "c1" });
    expect(view.result.meta.feature).toBe(feature);
    view.unmount();
  });

  it("runs a write on the client and loads its section again", async () => {
    const view = renderHook(() => {
      void BetterSupabaseProvider({ client });
      void RecordProvider({ id: "c1" });

      return useRecord();
    }, undefined);

    await flush();

    const added = await view.result.actions.write("notes", "add", {
      body: "Second",
    });

    expect(added).toMatchObject({
      ok: true,
      data: { id: "n2", at: "2026-10-21T10:00:00Z" },
    });
    await flush();
    expect(view.result.state.sections.notes).toMatchObject({
      kind: "ok",
      data: [{ id: "n1" }, { id: "n2" }],
    });
    expect(view.result.state.can.notes).toEqual({ read: true, add: true });
    view.unmount();
  });

  it("runs a write through its Server Action when one is given", async () => {
    const action = vi.fn(async () => ({
      ok: true as const,
      data: { id: "n9", at: "2026-10-21T10:00:00Z" },
      error: null,
    }));

    const view = renderHook(() => {
      void BetterSupabaseProvider({ client });
      void RecordProvider({ id: "c1", writes: { notes: { add: action } } });

      return useRecord();
    }, undefined);

    await view.result.actions.write("notes", "add", { body: "Third" });
    expect(action).toHaveBeenCalledWith({ id: "c1", input: { body: "Third" } });
    view.unmount();
  });

  it("throws outside its provider", () => {
    expect(() => renderHook(() => useRecord(), undefined)).toThrow(
      /wrap the customer record/,
    );
  });
});
