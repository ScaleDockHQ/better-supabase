import { describe, expect, it } from "vitest";

import type { AnyModels } from "../../../src/schema/types.ts";

import {
  activityListQuery,
  activitySink,
  createComments,
  mentionsIn,
} from "../../../src/blocks/comments/index.ts";
import { defineSupabase } from "../../../src/core/define.ts";
import { defineSchema } from "../../../src/schema/define.ts";

const ADA = "8c5a3d3e-0000-4000-8000-000000000001";
const BOB = "8c5a3d3e-0000-4000-8000-000000000002";

const row = {
  id: "c1",
  organization_id: "org-1",
  subject_type: "project",
  subject_id: "p1",
  author_id: ADA,
  body: "Hello",
  mentions: [BOB],
  parent_id: null,
  created_at: "2026-10-06T12:00:00Z",
  edited_at: null,
  deleted_at: null,
};

function fakeTransport(results: Record<string, unknown>) {
  const calls: [string, string, Record<string, unknown>][] = [];
  return {
    calls,
    transport: {
      call(
        schema: string,
        fn: string,
        args: Readonly<Record<string, unknown>>,
      ) {
        calls.push([schema, fn, { ...args }]);
        const result = results[fn];
        return result instanceof Error
          ? Promise.reject(result)
          : Promise.resolve(result);
      },
    },
  };
}

describe("mentionsIn", () => {
  it("returns each mentioned id once, in order", () => {
    expect(
      mentionsIn(
        `Hi @[Bob](${BOB.toUpperCase()}) and @[Ada](${ADA}), again @[Bob](${BOB}); not @Bob or @[x](42)`,
      ),
    ).toEqual([BOB, ADA]);
  });
});

describe("createComments", () => {
  it("creates with the mentions from the body unless given", async () => {
    const fake = fakeTransport({ create_comment: row });
    const comments = createComments({
      transport: fake.transport,
      schema: "app",
    });
    const comment = await comments
      .create({
        organizationId: "org-1",
        subjectType: "project",
        subjectId: "p1",
        body: `Hello @[Bob](${BOB})`,
      })
      .orThrow();
    expect(comment).toMatchObject({
      id: "c1",
      authorId: ADA,
      mentions: [BOB],
      parentId: undefined,
      editedAt: undefined,
    });
    expect(comment.createdAt.toString()).toBe("2026-10-06T12:00:00Z");
    await comments
      .create({
        organizationId: "org-1",
        subjectType: "project",
        subjectId: "p1",
        body: "Reply",
        mentions: [],
        parentId: "c0",
      })
      .orThrow();
    expect(fake.calls).toEqual([
      [
        "app",
        "create_comment",
        {
          tenant: "org-1",
          subject_type: "project",
          subject_id: "p1",
          body: `Hello @[Bob](${BOB})`,
          mentions: [BOB],
          parent: undefined,
        },
      ],
      [
        "app",
        "create_comment",
        {
          tenant: "org-1",
          subject_type: "project",
          subject_id: "p1",
          body: "Reply",
          mentions: [],
          parent: "c0",
        },
      ],
    ]);
  });

  it("edits, or returns not_found for a comment the caller can't edit", async () => {
    const edited = { ...row, edited_at: "2026-10-06T12:05:00Z" };
    const ok = fakeTransport({ edit_comment: edited });
    const comment = await createComments({ transport: ok.transport })
      .edit("c1", { body: "Changed" })
      .orThrow();
    expect(comment.editedAt?.toString()).toBe("2026-10-06T12:05:00Z");
    expect(ok.calls[0]).toEqual([
      "better_supabase",
      "edit_comment",
      { id: "c1", body: "Changed", mentions: [] },
    ]);

    const none = fakeTransport({ edit_comment: null });
    expect(
      await createComments({ transport: none.transport }).edit("c9", {
        body: "x",
        mentions: [ADA],
      }),
    ).toMatchObject({
      ok: false,
      error: { kind: "not_found", hint: "COMMENT_NOT_FOUND" },
    });
  });

  it("takes mentions from mentionsOf, copies threads and lists a timeline", async () => {
    const fake = fakeTransport({
      create_comment: { ...row, document: { type: "doc" } },
      edit_comment: row,
      copy_comments: 3,
      list_activity: [
        {
          id: "a1",
          organization_id: "org-1",
          type: "quote.sent",
          actor_id: ADA,
          subject_type: "quote",
          subject_id: "q1",
          summary: "Sent",
          data: { total: 10 },
          occurred_at: "2026-10-06T12:00:00Z",
        },
        {
          id: "a2",
          organization_id: "org-1",
          type: "quote.created",
          actor_id: null,
          subject_type: null,
          subject_id: null,
          summary: null,
          data: null,
          occurred_at: "2026-10-06T11:00:00Z",
        },
      ],
    });
    const comments = createComments({
      transport: fake.transport,
      mentionsOf: ({ document }) => (document ? [ADA] : []),
    });
    const created = await comments
      .create({
        organizationId: "org-1",
        subjectType: "project",
        subjectId: "p1",
        body: "Hi",
        document: { type: "doc" },
      })
      .orThrow();
    expect(created.document).toEqual({ type: "doc" });
    expect(fake.calls[0]![2]).toMatchObject({
      mentions: [ADA],
      document: { type: "doc" },
    });
    await comments.edit("c1", { body: "x", document: null }).orThrow();
    expect(fake.calls[1]![2]).toMatchObject({
      clear_document: true,
      mentions: [],
    });
    expect(
      await comments
        .copy(
          "org-1",
          { type: "quote", id: "q1" },
          { type: "invoice", id: "i1" },
        )
        .orThrow(),
    ).toBe(3);
    expect(fake.calls[2]![2]).toEqual({
      tenant: "org-1",
      from_type: "quote",
      from_id: "q1",
      to_type: "invoice",
      to_id: "i1",
    });
    const history = await comments
      .history(
        "org-1",
        { type: "quote", id: "q1" },
        {
          before: Temporal.Instant.from("2026-10-07T00:00:00Z"),
          limit: 2,
        },
      )
      .orThrow();
    expect(history[0]).toMatchObject({
      type: "quote.sent",
      actorId: ADA,
      subjectId: "q1",
      data: { total: 10 },
    });
    expect(history[1]).toMatchObject({ actorId: undefined, data: {} });
    expect(fake.calls[3]![2]).toMatchObject({
      subject_type: "quote",
      before: "2026-10-07T00:00:00Z",
      max_rows: 2,
    });
  });

  it("removes and lists a thread", async () => {
    const fake = fakeTransport({
      delete_comment: true,
      list_comments: [
        row,
        { ...row, id: "c2", body: null, deleted_at: "2026-10-06T13:00:00Z" },
      ],
    });
    const comments = createComments({ transport: fake.transport });
    expect(await comments.remove("c1").orThrow()).toBe(true);
    const thread = await comments
      .list("org-1", "project", "p1", {
        after: Temporal.Instant.from("2026-10-06T00:00:00Z"),
        limit: 20,
      })
      .orThrow();
    expect(thread.map((comment) => [comment.id, comment.body])).toEqual([
      ["c1", "Hello"],
      ["c2", ""],
    ]);
    expect(thread[1]?.deletedAt).toBeDefined();
    expect(fake.calls[1]).toEqual([
      "better_supabase",
      "list_comments",
      {
        tenant: "org-1",
        subject_type: "project",
        subject_id: "p1",
        after: "2026-10-06T00:00:00Z",
        max_rows: 20,
        skip: undefined,
      },
    ]);
  });

  it("pages by offset and counts comments per subject", async () => {
    const fake = fakeTransport({
      list_comments: [],
      comment_counts: { p1: 3, p9: "2" },
    });
    const comments = createComments({ transport: fake.transport });
    await comments.list("org-1", "project", "p1", { offset: 40, limit: 20 });
    expect(fake.calls[0]![2]).toMatchObject({ skip: 40, max_rows: 20 });
    expect(
      await comments.counts("org-1", "project", ["p1", "p2", "p9"]).orThrow(),
    ).toEqual({ p1: 3, p2: 0, p9: 2 });
    expect(fake.calls[1]).toEqual([
      "better_supabase",
      "comment_counts",
      {
        tenant: "org-1",
        subject_type: "project",
        subject_ids: ["p1", "p2", "p9"],
      },
    ]);
  });

  it("maps database errors to DbError", async () => {
    const fake = fakeTransport({
      delete_comment: Object.assign(new Error("permission denied"), {
        code: "42501",
      }),
    });
    expect(
      await createComments({ transport: fake.transport }).remove("c1"),
    ).toMatchObject({ ok: false, error: { kind: "forbidden" } });
  });
});

describe("activitySink", () => {
  const event = (patch: Record<string, unknown>) => ({
    specversion: "1.0" as const,
    id: "evt-1",
    source: "https://app.test",
    type: "dev.better-supabase.comment.created",
    time: "2026-10-06T12:00:00Z",
    partitionkey: "org-1",
    subject: "comments/c1",
    data: { commentId: "c1", authorId: ADA },
    ...patch,
  });

  it("records tenant events with their actor and subject, once per batch", async () => {
    const fake = fakeTransport({ record_activity: 2 });
    await activitySink({ transport: fake.transport }).send([
      event({}),
      event({
        id: "evt-2",
        type: "app.project.archived",
        subject: undefined,
        data: { subjectType: "project", subjectId: "p1", actorId: BOB },
      }),
      event({ id: "evt-3", partitionkey: undefined }),
      event({ id: "evt-4", subject: "loose", data: "text", type: "x" }),
    ]);
    expect(fake.calls).toEqual([
      [
        "better_supabase",
        "record_activity",
        {
          batch: {
            entries: [
              {
                event_id: "evt-1",
                organization_id: "org-1",
                type: "comment.created",
                actor_id: ADA,
                subject_type: "comment",
                subject_id: "c1",
                summary: undefined,
                data: { commentId: "c1", authorId: ADA },
                occurred_at: "2026-10-06T12:00:00Z",
              },
              {
                event_id: "evt-2",
                organization_id: "org-1",
                type: "app.project.archived",
                actor_id: BOB,
                subject_type: "project",
                subject_id: "p1",
                summary: undefined,
                data: { subjectType: "project", subjectId: "p1", actorId: BOB },
                occurred_at: "2026-10-06T12:00:00Z",
              },
              {
                event_id: "evt-4",
                organization_id: "org-1",
                type: "x",
                actor_id: undefined,
                subject_type: undefined,
                subject_id: undefined,
                summary: undefined,
                data: {},
                occurred_at: "2026-10-06T12:00:00Z",
              },
            ],
          },
        },
      ],
    ]);
  });

  it("filters by type and lets describe() summarize or skip", async () => {
    const fake = fakeTransport({ record_activity: 1 });
    const sink = activitySink({
      transport: fake.transport,
      schema: "app",
      typePrefix: "com.acme",
      types: ["comment.*", "invoice.paid"],
      describe: (cloud, type) =>
        cloud.id === "evt-2"
          ? null
          : {
              summary: `${type} by Ada`,
              actorId: ADA,
              subjectType: "thread",
              subjectId: "t1",
              data: { x: 1 },
            },
    });
    await sink.send([
      event({ type: "com.acme.comment.created" }),
      event({ id: "evt-2", type: "com.acme.comment.deleted" }),
      event({ id: "evt-3", type: "com.acme.invoice.voided" }),
    ]);
    expect(fake.calls).toEqual([
      [
        "app",
        "record_activity",
        {
          batch: {
            entries: [
              {
                event_id: "evt-1",
                organization_id: "org-1",
                type: "comment.created",
                actor_id: ADA,
                subject_type: "thread",
                subject_id: "t1",
                summary: "comment.created by Ada",
                data: { x: 1 },
                occurred_at: "2026-10-06T12:00:00Z",
              },
            ],
          },
        },
      ],
    ]);
    await sink.send([event({ id: "evt-5", type: "com.acme.invoice.voided" })]);
    expect(fake.calls).toHaveLength(1);
  });
});

describe("activityListQuery", () => {
  const column = (db: string, type: string, nullable = true) => ({
    db,
    type,
    nullable,
    hasDefault: false,
  });
  const table = (casing: "camel" | "snake") => {
    const name = (snake: string, camel: string) =>
      casing === "camel" ? camel : snake;
    return defineSupabase(
      defineSchema<AnyModels>({
        version: 1,
        casing,
        tables: {
          activity: {
            key: "activity",
            name: "activity_entries",
            schema: "better_supabase",
            kind: "table",
            columns: {
              id: column("id", "uuid", false),
              type: column("type", "text", false),
              [name("actor_id", "actorId")]: column("actor_id", "uuid"),
              [name("subject_type", "subjectType")]: column(
                "subject_type",
                "text",
              ),
              [name("occurred_at", "occurredAt")]: column(
                "occurred_at",
                "timestamptz",
                false,
              ),
            },
            primaryKey: ["id"],
            uniqueKeys: {},
            relations: {},
            flags: {},
          },
        },
        functions: {},
      } as never),
    );
  };

  it("pages newest first by the facets the table has, in either casing", () => {
    for (const casing of ["camel", "snake"] as const) {
      const list = activityListQuery(table(casing), "activity", {
        pageSize: 25,
        maxPageSize: 50,
      });
      expect(list.facets.map((facet) => facet.key)).toEqual([
        "type",
        "actor",
        "subjectType",
      ]);
      const query = list.parse({});
      expect(query.ok).toBe(true);
      const occurredAt = casing === "camel" ? "occurredAt" : "occurred_at";
      expect(list.args(query.value!)).toMatchObject({
        orderBy: [{ [occurredAt]: "desc" }, { id: "desc" }],
        size: 25,
      });
    }
    expect(() => activityListQuery(table("camel"), "missing")).toThrow(
      /unknown table "missing"/,
    );
  });
});
