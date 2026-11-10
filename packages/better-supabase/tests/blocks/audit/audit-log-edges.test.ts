import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../../src/core/block-transport.ts";

import { createAudit } from "../../../src/blocks/audit/index.ts";

type Calls = [string, Record<string, unknown>][];

/** A transport that answers each function from `answers`, or an empty list. */
function transport(answers: Record<string, unknown> = {}) {
  const calls: Calls = [];

  const t: BlockTransport = {
    call(_schema, fn, args) {
      calls.push([fn, { ...args }]);

      if (fn in answers) {
        const answer = answers[fn];

        return typeof answer === "function"
          ? Promise.resolve(answer(args))
          : Promise.resolve(answer);
      }

      return Promise.resolve([]);
    },
  };

  return { t, calls };
}

const FULL = {
  id: "7",
  occurredAt: "2026-10-06T12:00:00Z",
  op: "update",
  table: "invoices",
  record: "inv-1",
  actorId: "u1",
  actorRole: "admin",
  actorKind: "user",
  actorLabel: "Ada",
  tenant: "org",
  tenantLabel: "Org",
  eventType: "invoice.sent",
  category: "billing",
  outcome: "success",
  source: "api",
  targetType: "invoice",
  targetLabel: "INV-1",
  summary: "Sent",
  requestId: "req",
  correlationId: "corr",
  scope: "tenant",
  impersonatedBy: "u2",
  impersonationReason: "support",
  supportSession: "s1",
  changed: ["status"],
  old: { status: "draft" },
  new: { status: "sent" },
  metadata: { a: 1 },
  columns: { ticket: "t1" },
};

describe("audit log edges", () => {
  it("keeps every field of a full entry and maps it to OCSF", async () => {
    const { t } = transport({ list_audit_events: [FULL] });
    const audit = createAudit<{ ticket: string }>({ transport: t });

    const page = await audit.list().orThrow();
    expect(page.entries[0]).toMatchObject({
      ...FULL,
      occurredAt: expect.anything(),
    });
    expect(page.entries[0]!.occurredAt.toString()).toBe("2026-10-06T12:00:00Z");

    const line = await new Response(
      audit.export({ format: "ocsf", product: { name: "Example" } }),
    ).text();

    const ocsf: unknown = JSON.parse(line.trim());
    expect(JSON.stringify(ocsf)).toContain("invoices");
  });

  it("falls back to the epoch and an empty entry for incomplete rows", async () => {
    const lenient = transport({ list_audit_events: [{ id: "1" }] });
    const page = await createAudit({ transport: lenient.t }).list().orThrow();

    expect(page.entries[0]!.occurredAt.epochMilliseconds).toBe(0);
    expect(page.entries[0]).not.toHaveProperty("old");
    expect(page.entries[0]).not.toHaveProperty("changed");
  });

  it("exports an entry with only an id as an event", async () => {
    const { t } = transport({ list_audit_events: [{ id: "1" }] });

    const line = await new Response(
      createAudit({ transport: t }).export({
        format: "ocsf",
        product: { name: "Example" },
      }),
    ).text();

    expect(JSON.parse(line.trim())).toMatchObject({ class_uid: 6003 });
  });

  it("reverts with defaults when the module answers with something else", async () => {
    for (const answer of [null, "x", { reverted: "many", entries: "none" }]) {
      const { t } = transport({ revert_audit_entries: answer });

      expect(
        await createAudit({ transport: t }).revert(["1"]).orThrow(),
      ).toEqual({ reverted: 0, undo: null });
    }
  });

  it("reveals an entry that carries every detail", async () => {
    const { t } = transport({
      reveal_audit_entry: {
        old: { a: 1 },
        new: { a: 2 },
        metadata: { m: true },
        ip: "1.1.1.1",
        userAgent: "ua",
        sessionId: "s",
        changes: { a: { old: 1, new: 2 } },
      },
    });

    expect(await createAudit({ transport: t }).reveal("9").orThrow()).toEqual({
      entry: "9",
      old: { a: 1 },
      new: { a: 2 },
      metadata: { m: true },
      ip: "1.1.1.1",
      userAgent: "ua",
      sessionId: "s",
      changes: { a: { old: 1, new: 2 } },
    });

    const bare = transport({ reveal_audit_entry: { changes: null } });
    expect(
      await createAudit({ transport: bare.t }).reveal("9").orThrow(),
    ).toEqual({ entry: "9" });

    const nothing = transport({ reveal_audit_entry: null });
    expect(
      await createAudit({ transport: nothing.t }).reveal("9").orThrow(),
    ).toEqual({ entry: "9" });
  });

  it("passes every filter, accepting one value or a list", async () => {
    const { t, calls } = transport();
    const audit = createAudit({ transport: t });

    await audit
      .list({
        organizationId: ["o1", "o2"],
        eventType: "a",
        actorId: ["u"],
        targetType: "t",
        record: "r",
        category: "c",
        outcome: "o",
        source: "s",
        actorKind: "k",
        correlationId: "x",
        search: "q",
        order: "asc",
        count: true,
      })
      .orThrow();

    expect(calls[0]![1]).toMatchObject({
      for_tenants: ["o1", "o2"],
      for_event_types: ["a"],
      for_actors: ["u"],
      for_target_types: ["t"],
      for_records: ["r"],
      for_categories: ["c"],
      for_outcomes: ["o"],
      for_sources: ["s"],
      for_actor_kinds: ["k"],
      for_correlation_ids: ["x"],
      search: "q",
      ascending: true,
      max_items: 50,
    });
  });

  it("records an event with every field and many events in one call", async () => {
    const { t, calls } = transport({
      audit_event: 5,
      audit_event_many: [{ id: 1 }, { error: { message: "bad" } }, {}],
    });

    const audit = createAudit({ transport: t });

    await audit
      .record({
        eventType: "e",
        category: "c",
        outcome: "o",
        source: "s",
        targetType: "t",
        record: "r",
        organizationId: "org",
        metadata: { a: 1 },
        idempotencyKey: "k",
        restricted: { ip: "1.1.1.1" },
        actorId: "u",
        summary: "sum",
        targetLabel: "tl",
        correlationId: "corr",
        actorKind: "user",
        actorLabel: "Ada",
        ip: "1.1.1.1",
        userAgent: "ua",
        sessionId: "sess",
        requestId: "req",
        scope: "tenant",
        supportSessionId: "ss",
        impersonatedBy: "u2",
        impersonationReason: "why",
      })
      .orThrow();

    expect(calls[0]![1]).toMatchObject({
      event_type: "e",
      record_id: "r",
      tenant: "org",
      idempotency_key: "k",
      support_session: "ss",
      impersonation_reason: "why",
      user_agent: "ua",
    });

    expect(await audit.recordMany([]).orThrow()).toEqual([]);

    const results = await audit
      .recordMany([{ eventType: "a" }, { eventType: "b" }, { eventType: "c" }])
      .orThrow();

    expect(results.map((result) => result.ok)).toEqual([true, false, false]);
    expect(calls.at(-1)![0]).toBe("audit_event_many");
  });

  it("names the actor on a page and reports the page's size without a total", async () => {
    const { t } = transport({
      list_audit_events: [
        { id: "1", occurredAt: "2026-10-06T12:00:00Z", actorLabel: "Ada" },
        { id: "2", occurredAt: "2026-10-06T12:00:01Z" },
      ],
      count_audit_events: 9,
    });

    const page = await createAudit({ transport: t }).page().orThrow();

    expect(page.total).toBe(9);
    expect(page.entries.map((entry) => entry.actorName)).toEqual(["Ada", null]);
  });

  it("correlates inside an organization and stops at a failed page", async () => {
    const { t, calls } = transport({
      list_audit_events: [{ id: "1", occurredAt: "2026-10-06T12:00:00Z" }],
    });

    const audit = createAudit({ transport: t });

    expect(
      await audit
        .correlated({ correlationId: "c", organizationId: "org" })
        .orThrow(),
    ).toHaveLength(1);
    expect(calls[0]![1]).toMatchObject({ for_tenants: ["org"] });

    const failing: BlockTransport = {
      call: () => Promise.reject(new Error("down")),
    };

    const failed = await createAudit({ transport: failing }).correlated({
      correlationId: "c",
    });

    expect(failed.ok).toBe(false);
  });

  it("exports to Storage with a signed URL, and without one when the bucket cannot sign", async () => {
    const { t } = transport({
      list_audit_events: [{ id: "1", occurredAt: "2026-10-06T12:00:00Z" }],
    });

    const audit = createAudit({ transport: t });
    const uploads: string[] = [];

    const signing = {
      from: () => ({
        upload: (path: string) => {
          uploads.push(path);

          return Promise.resolve({ data: null, error: null });
        },
        createSignedUrl: () =>
          Promise.resolve({
            data: { signedUrl: "https://signed" },
            error: null,
          }),
      }),
    };

    expect(
      await audit
        .exportToStorage({
          storage: signing,
          bucket: "b",
          path: "a.ndjson",
          signedUrlTtl: 60,
        })
        .orThrow(),
    ).toEqual({ path: "a.ndjson", url: "https://signed" });

    const plain = {
      from: () => ({
        upload: () => Promise.resolve({ data: null, error: null }),
      }),
    };

    expect(
      await audit
        .exportToStorage({
          storage: plain,
          bucket: "b",
          path: "a",
          signedUrlTtl: 60,
        })
        .orThrow(),
    ).toEqual({ path: "a", url: undefined });
    expect(uploads).toEqual(["a.ndjson"]);
  });

  it("starts a CSV export at an offset and reads restricted details", async () => {
    const { t } = transport({
      list_audit_events: [{ id: "1", occurredAt: "2026-10-06T12:00:00Z" }],
      reveal_audit_entries: [{ entry: "1", ip: "9.9.9.9" }],
    });

    const csv = await new Response(
      createAudit({ transport: t }).export({
        format: "csv",
        columns: ["id", "restricted.ip"],
        offset: 3,
      }),
    ).text();

    expect(csv).toContain("1,9.9.9.9");
  });

  it("reads a list that is not an array as empty and a non-record row as a bare entry", async () => {
    const none = transport({ list_audit_events: null });
    const page = await createAudit({ transport: none.t }).list().orThrow();
    expect(page).toEqual({ entries: [], next: undefined });

    const bare = transport({ list_audit_events: [null] });
    const rows = await createAudit({ transport: bare.t }).list().orThrow();
    expect(rows.entries[0]!.occurredAt.epochMilliseconds).toBe(0);
  });

  it("leaves restricted columns empty when the reveal answer is not a list", async () => {
    const { t } = transport({
      list_audit_events: [{ id: "1", occurredAt: "2026-10-06T12:00:00Z" }],
      reveal_audit_entries: null,
    });

    const csv = await new Response(
      createAudit({ transport: t }).export({
        format: "csv",
        columns: ["id", "restricted.ip"],
      }),
    ).text();

    expect(csv.split("\r\n")[1]).toBe("1,");
  });

  it("builds a sink and hands the logger to the hooks", async () => {
    const { t } = transport({ audit_event_many: [{ id: 1 }] });
    const errors: string[] = [];

    const audit = createAudit({
      transport: t,
      logger: {
        debug: () => {},
        info: () => {},
        warn: () => {},
        error: (message) => errors.push(message),
      },
      hooks: {
        reveal: {
          after: () => {
            throw new Error("after failed");
          },
        },
      },
    });

    expect(typeof audit.sink().send).toBe("function");
    await audit.reveal("1").orThrow();
    expect(errors).toHaveLength(1);
  });
});

describe("createAudit answers that are not what a database returns", () => {
  it("reads a missing entry as null and an unusable type list as empty", async () => {
    const { t } = transport({
      get_audit_event: null,
      audit_event_types: "none",
    });

    const audit = createAudit({ transport: t });

    expect(await audit.get("9").orThrow()).toBeNull();
    expect(await audit.eventTypes().orThrow()).toEqual([]);
  });

  it("keeps only the string event types", async () => {
    const { t } = transport({ audit_event_types: ["a.b", 3, "c.d"] });

    expect(await createAudit({ transport: t }).eventTypes().orThrow()).toEqual([
      "a.b",
      "c.d",
    ]);
  });
});
