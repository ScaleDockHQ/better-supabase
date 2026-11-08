import { beforeEach, describe, expect, it, vi } from "vitest";

import type { AuthSnapshot } from "../../src/client/index.ts";
import type { AsyncResult } from "../../src/core/result.ts";
import type { ClientLike } from "../../src/react/hooks.ts";
import type { RecordRef } from "../../src/schema/types.ts";

import { defineBlock } from "../../src/blocks/define-block.ts";
import { entitySchema } from "../../src/blocks/entity-schema.ts";
import { OfflineBoundary } from "../../src/next/offline/index.ts";
import { defineDataHooks } from "../../src/react/data-hooks.ts";
import { BetterSupabaseProvider } from "../../src/react/hooks.ts";
import { createRecordProvider } from "../../src/react/record.ts";
import {
  defineRecordBinding,
  defineRecordType,
} from "../../src/records/index.ts";
import { renderHook } from "../fixtures/hook-runtime.ts";
import { flush, resolved } from "../fixtures/ports.ts";

const mocks = vi.hoisted(() => ({ offline: false }));

vi.mock(import("next/offline.js"), () => ({ useOffline: () => mocks.offline }));

vi.mock(import("react"), async (original) => ({
  ...(await original()),
  // SAFETY: hook-runtime stands in for the hooks the controllers use.
  ...((await import("../fixtures/hook-runtime.ts")).reactHooks as object),
}));

const calls: string[] = [];
const rows = [{ id: "n1" }];

interface Notes {
  list(subject: RecordRef): AsyncResult<readonly { id: string }[]>;
  add(subject: RecordRef, body: string): AsyncResult<{ id: string }>;
}

const notes: Notes = {
  list: () => {
    calls.push("list");

    return resolved([...rows]);
  },
  add: (_subject, body) => {
    calls.push(`add:${body}`);

    return resolved({ id: body });
  },
};

const notesBlock = defineBlock({
  name: "notes",
  sql: ["notes"],
  category: "collaboration",
  create: (): Notes => notes,
  record: defineRecordBinding({
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
          subject: RecordRef,
          input: { readonly body: string },
        ) => client.add(subject, input.body),
      },
    },
  }),
});

const { RecordProvider, useRecord } = createRecordProvider(
  defineRecordType({ type: "customer", blocks: { notes: notesBlock } }),
);

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
  db: {
    tickets: {
      list: () => {
        calls.push("tickets");

        return resolved([{ id: "t1" }]);
      },
    },
  },
} as unknown as ClientLike;

const { useList } = defineDataHooks(
  "tickets",
  (db: { tickets: { list: () => AsyncResult<readonly { id: string }[]> } }) =>
    db.tickets,
);

beforeEach(() => {
  calls.length = 0;
  mocks.offline = false;
});

describe("OfflineBoundary", () => {
  it("pauses a data hook while offline and reads when the connection returns", async () => {
    mocks.offline = true;

    const view = renderHook(() => {
      void BetterSupabaseProvider({ client });
      void OfflineBoundary({});

      return useList();
    }, undefined);

    await flush();

    expect(calls).toEqual([]);
    expect(view.result).toMatchObject({ offline: true, error: undefined });

    mocks.offline = false;
    view.rerender(undefined);
    await flush();

    expect(calls).toEqual(["tickets"]);
    expect(view.result).toMatchObject({ offline: false, data: [{ id: "t1" }] });
    view.unmount();
  });

  it("holds a record's loads and queues its write until the connection returns", async () => {
    mocks.offline = true;

    const view = renderHook(() => {
      void BetterSupabaseProvider({ client });
      void OfflineBoundary({});
      void RecordProvider({ id: "c1" });

      return useRecord();
    }, undefined);

    await flush();

    expect(calls).toEqual([]);
    expect(view.result.state.offline).toBe(true);

    const first = view.result.actions.write("notes", "add", { body: "a" });
    const second = view.result.actions.write("notes", "add", { body: "b" });
    await flush();

    expect(second).toBe(first);
    expect(calls).toEqual([]);

    mocks.offline = false;
    view.rerender(undefined);

    await expect(first).resolves.toMatchObject({ ok: true, data: { id: "b" } });
    await flush();

    expect(calls).toContain("add:b");
    expect(calls).not.toContain("add:a");
    expect(view.result.state.offline).toBe(false);
    view.unmount();
  });

  it("settles a queued write with a network error when the record unmounts", async () => {
    mocks.offline = true;

    const view = renderHook(() => {
      void BetterSupabaseProvider({ client });
      void OfflineBoundary({});
      void RecordProvider({ id: "c1" });

      return useRecord();
    }, undefined);

    const queued = view.result.actions.write("notes", "add", { body: "a" });
    view.unmount();

    await expect(queued).resolves.toMatchObject({
      ok: false,
      error: { kind: "network" },
    });
    expect(calls).toEqual([]);
  });
});
