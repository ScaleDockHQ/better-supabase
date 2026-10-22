import { describe, expect, it } from "vitest";

import type { AnyModels } from "../../../src/schema/types.ts";

import {
  activityListQuery,
  activitySink,
  createActivity,
} from "../../../src/blocks/activity/index.ts";
import { defineSupabase } from "../../../src/core/define.ts";
import { defineSchema } from "../../../src/schema/define.ts";

const ADA = "8c5a3d3e-0000-4000-8000-000000000001";
const BOB = "8c5a3d3e-0000-4000-8000-000000000002";

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

describe("createActivity", () => {
  it("lists a record's timeline from every source, newest first", async () => {
    const fake = fakeTransport({
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
        {
          id: "42",
          source: "audit",
          organization_id: "org-1",
          event_id: null,
          type: "quotes.updated",
          actor_id: ADA,
          subject_type: "quote",
          subject_id: "q1",
          summary: null,
          data: { op: "update", changed: ["total"], table: "public.quotes" },
          occurred_at: "2026-10-06T10:00:00Z",
        },
      ],
    });

    const activity = createActivity({
      transport: fake.transport,
      tenant: "org-1",
    });

    const history = await activity
      .list(
        { type: "quote", id: "q1" },
        {
          cursor: Temporal.Instant.from("2026-10-07T00:00:00Z"),
          limit: 2,
          sources: ["event", "audit"],
        },
      )
      .orThrow();

    expect(history[0]).toMatchObject({
      source: "event",
      type: "quote.sent",
      actorId: ADA,
      subject: { type: "quote", id: "q1" },
      data: { total: 10 },
    });
    expect(history[1]).toMatchObject({
      actorId: undefined,
      subject: undefined,
      data: {},
    });
    expect(history[2]).toMatchObject({
      id: "42",
      source: "audit",
      type: "quotes.updated",
      data: { op: "update", changed: ["total"] },
    });
    expect(fake.calls[0]).toEqual([
      "better_supabase",
      "list_activity",
      {
        tenant: "org-1",
        subject_type: "quote",
        subject_id: "q1",
        before: "2026-10-07T00:00:00Z",
        max_rows: 2,
        sources: ["event", "audit"],
      },
    ]);

    await activity.list().orThrow();
    expect(fake.calls[1]![2]).toMatchObject({
      subject_type: undefined,
      subject_id: undefined,
    });
  });

  it("fails without a tenant", async () => {
    const fake = fakeTransport({});
    expect(
      await createActivity({ transport: fake.transport }).list(),
    ).toMatchObject({
      ok: false,
      error: { kind: "invalid_request", hint: "TENANT_REQUIRED" },
    });
    expect(fake.calls).toHaveLength(0);
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

  it("files a comment under the record its conversation is on", async () => {
    const fake = fakeTransport({ record_activity: 1 });
    await activitySink({ transport: fake.transport }).send([
      event({
        type: "dev.better-supabase.message.sent",
        subject: "messages/m1",
        data: {
          messageId: "m1",
          conversationId: "conv-1",
          conversationKind: "subject",
          recordType: "project",
          recordId: "p1",
          subjectType: "conversation",
          subjectId: "conv-1",
          authorId: ADA,
        },
      }),
    ]);
    expect(fake.calls[0]![2]).toMatchObject({
      batch: {
        entries: [
          {
            type: "message.sent",
            actor_id: ADA,
            subject_type: "project",
            subject_id: "p1",
          },
        ],
      },
    });
  });

  it("keeps a subject type that isn't a plural", async () => {
    const fake = fakeTransport({ record_activity: 1 });
    await activitySink({ transport: fake.transport }).send([
      event({ type: "dev.better-supabase.staff.joined", subject: "staff/s1" }),
    ]);
    expect(fake.calls[0]![2]).toMatchObject({
      batch: { entries: [{ subject_type: "staff", subject_id: "s1" }] },
    });
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

    const defaults = activityListQuery(table("snake"), "activity");
    const query = defaults.parse({});
    expect(defaults.args(query.value!)).toMatchObject({
      orderBy: [{ occurred_at: "desc" }, { id: "desc" }],
    });

    expect(() => activityListQuery(table("camel"), "missing")).toThrow(
      /unknown table "missing"/,
    );
  });
});
