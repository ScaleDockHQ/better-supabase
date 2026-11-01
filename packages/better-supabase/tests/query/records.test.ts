import { QueryClient, skipToken } from "@tanstack/query-core";
import { describe, expect, expectTypeOf, it, vi } from "vitest";

import type { AsyncResult } from "../../src/core/result.ts";
import type { RecordRef } from "../../src/schema/types.ts";

import { defineBlock } from "../../src/blocks/define-block.ts";
import { entitySchema } from "../../src/blocks/entity-schema.ts";
import { emitBlockEvent } from "../../src/core/block-events.ts";
import { EventHub } from "../../src/core/events.ts";
import {
  invalidateOnRecordEvents,
  recordQueries,
} from "../../src/query/records.ts";
import {
  defineRecordType,
  defineRecordBinding,
} from "../../src/records/index.ts";
import { failed, resolved } from "../fixtures/ports.ts";

interface Note {
  readonly id: string;
  readonly body: string;
}

interface Notes {
  list(subject: RecordRef): AsyncResult<readonly Note[]>;
  add(subject: RecordRef, body: string): AsyncResult<Note>;
}

function notesClient() {
  const rows: Note[] = [{ id: "n1", body: "First" }];

  const client: Notes & { readonly rows: Note[] } = {
    rows,
    list: (subject) =>
      subject.id === "bad" ? failed("No notes") : resolved([...rows]),
    add: (_subject, body) => {
      const row = { id: `n${rows.length + 1}`, body };
      rows.push(row);

      return resolved(row);
    },
  };

  return client;
}

const notesBlock = defineBlock({
  name: "notes",
  sql: ["notes"],
  category: "collaboration",
  create: (): Notes => notesClient(),
  events: { types: ["note.added"] },
  record: defineRecordBinding({
    permissions: { read: "read", write: "create" },
    events: ["note.*"],
    load: (client: Notes, subject) => client.list(subject),
    writes: {
      add: {
        input: entitySchema<{ readonly body: string }>({
          title: "NoteInput",
          fields: { body: { kind: "string", minLength: 1 } },
        }),
        run: ({
          organizationId: client,
          command: subject,
          ns: input,
        }: {
          organizationId: Notes;
          command: RecordRef;
          ns: { readonly body: string };
        }) => client.add(subject, input.body),
      },
    },
  }),
});

const feature = defineRecordType({
  type: "customer",
  blocks: { notes: notesBlock },
  permissions: { notes: { read: "notes.read", create: "notes.create" } },
});

describe("recordQueries", () => {
  it("makes query options per binding, keyed by type, id and binding", async () => {
    const notes = notesClient();
    const queries = recordQueries(feature, { notes });
    const queryClient = new QueryClient();

    const options = queries.bindings.notes("c1");
    expect(options.queryKey).toEqual(["bsb-record", "customer", "c1", "notes"]);
    await expect(queryClient.query(options)).resolves.toEqual([
      { id: "n1", body: "First" },
    ]);
    expect(queries.$key).toEqual(["bsb-record", "customer"]);
    expect(queries.key("c1", "notes")).toEqual([
      "bsb-record",
      "customer",
      "c1",
      "notes",
    ]);
    expect(queries.bindings.notes(skipToken).queryFn).toBe(skipToken);
    expectTypeOf(options.queryKey).not.toBeAny();
  });

  it("throws a DbException when a binding fails", async () => {
    const queries = recordQueries(feature, { notes: notesClient() });

    await expect(
      new QueryClient().query(queries.bindings.notes("bad")),
    ).rejects.toMatchObject({ error: { message: "No notes" } });
  });

  it("runs a write and makes the binding stale", async () => {
    const notes = notesClient();
    const queries = recordQueries(feature, { notes });
    const queryClient = new QueryClient();
    await queryClient.query(queries.bindings.notes("c1"));

    const mutation = queries.writes.notes.add("c1");
    const row = await mutation.mutationFn({ body: "Second" });
    expect(row).toEqual({ id: "n2", body: "Second" });

    await mutation.onSuccess(row, { body: "Second" }, undefined, {
      client: queryClient,
    });
    expect(
      queryClient.getQueryState(["bsb-record", "customer", "c1", "notes"])
        ?.isInvalidated,
    ).toBe(true);
  });

  it("loads the flags through the access client", async () => {
    const permissions = vi.fn(() =>
      resolved({ tenant: "org", keys: ["notes.read"] }),
    );

    const queries = recordQueries(
      feature,
      { notes: notesClient() },
      { access: { permissions } },
    );

    await expect(new QueryClient().query(queries.can())).resolves.toEqual({
      notes: { read: true, add: false },
    });
    expect(permissions).toHaveBeenCalledWith(["notes.read", "notes.create"]);

    const open = recordQueries(feature, { notes: notesClient() });
    await expect(new QueryClient().query(open.can())).resolves.toEqual({
      notes: { read: true, add: true },
    });
  });
});

describe("recordQueries options", () => {
  it("scopes the keys, passes load options and sets the stale time", async () => {
    const queries = recordQueries(
      feature,
      { notes: notesClient() },
      { scope: "org", staleTime: 1000 },
    );

    const options = queries.bindings.notes("c1", { pageSize: 5 } as never);
    expect(options.queryKey).toEqual([
      "bsb-record",
      "customer",
      "c1",
      "notes",
      { pageSize: 5 },
      { scope: "org" },
    ]);
    expect(options.staleTime).toBe(1000);
    await expect(new QueryClient().query(options)).resolves.toHaveLength(1);
    expect(queries.key("c1")).toEqual(["bsb-record", "customer", "c1"]);
    expect(queries.can().queryKey).toEqual([
      "bsb-record",
      "customer",
      expect.anything(),
      { scope: "org" },
    ]);
  });

  it("throws a DbException when the flags fail to load", async () => {
    const queries = recordQueries(
      feature,
      { notes: notesClient() },
      { access: { permissions: () => failed("No access") } },
    );

    await expect(new QueryClient().query(queries.can())).rejects.toMatchObject({
      error: { message: "No access" },
    });
  });
});

describe("invalidateOnRecordEvents", () => {
  it("makes the matching binding of every record stale", async () => {
    const queries = recordQueries(feature, { notes: notesClient() });
    const queryClient = new QueryClient();
    const events = new EventHub();
    await queryClient.query(queries.bindings.notes("c1"));

    const stop = invalidateOnRecordEvents(queryClient, { events }, feature);
    emitBlockEvent(events, "note.added", {});
    stop();

    await vi.waitFor(() => {
      expect(
        queryClient.getQueryState(queries.key("c1", "notes"))?.isInvalidated,
      ).toBe(true);
    });
  });

  it("ignores events no binding lists", () => {
    const queryClient = new QueryClient();
    const invalidate = vi.spyOn(queryClient, "invalidateQueries");
    const events = new EventHub();

    const stop = invalidateOnRecordEvents(queryClient, { events }, feature);
    emitBlockEvent(events, "task.added", {});
    stop();

    expect(invalidate).not.toHaveBeenCalled();
  });
});
