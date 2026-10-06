import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../../src/core/block-transport.ts";

import { createAuditLog, csvField } from "../../../src/blocks/audit/index.ts";

type Handler = (args: Readonly<Record<string, unknown>>) => unknown;

function fakeTransport(handlers: Record<string, Handler> = {}) {
  const calls: { schema: string; fn: string; args: Record<string, unknown> }[] =
    [];
  const transport: BlockTransport = {
    async call(schema, fn, args) {
      calls.push({ schema, fn, args: { ...args } });
      const handler = handlers[fn];
      return handler ? handler(args) : null;
    },
  };
  return { transport, calls };
}

const entry = (id: number, extra: Record<string, unknown> = {}) => ({
  id,
  occurredAt: "2026-01-01T00:00:00Z",
  eventType: "invoices.updated",
  summary: 'Changed, the "total"',
  metadata: { a: 1 },
  ...extra,
});

describe("createAuditLog", () => {
  it("lists entries with filters and pages", async () => {
    const { transport, calls } = fakeTransport({
      list_audit_events: () => [
        entry(9),
        entry(8, { occurredAt: new Date("2026-01-02T00:00:00Z") }),
        "skip",
      ],
    });
    const audit = createAuditLog({ transport, schema: "app" });
    const entries = await audit
      .list({
        tenant: "t1",
        eventType: "invoices.updated",
        actorId: "u1",
        targetType: "invoice",
        record: "42",
        since: Temporal.Instant.from("2026-01-01T00:00:00Z"),
        until: Temporal.Instant.from("2026-02-01T00:00:00Z"),
        before: {
          id: "10",
          occurredAt: Temporal.Instant.from("2026-01-03T00:00:00Z"),
        },
        limit: 2,
      })
      .orThrow();
    expect(entries.map((item) => item.id)).toEqual(["9", "8"]);
    expect(entries[1]!.occurredAt.toString()).toBe("2026-01-02T00:00:00Z");
    expect(calls[0]).toEqual({
      schema: "app",
      fn: "list_audit_events",
      args: {
        for_tenant: "t1",
        for_event_type: "invoices.updated",
        for_actor: "u1",
        for_target_type: "invoice",
        for_record: "42",
        since: "2026-01-01T00:00:00Z",
        until: "2026-02-01T00:00:00Z",
        before_at: "2026-01-03T00:00:00Z",
        before_id: "10",
        max_items: 2,
      },
    });
    await audit.list().orThrow();
    expect(calls[1]!.args).toMatchObject({
      for_tenant: null,
      before_at: null,
      before_id: null,
    });
    expect(await createAuditLog(fakeTransport()).list().orThrow()).toEqual([]);
  });

  it("reveals restricted details and maps errors", async () => {
    const { transport, calls } = fakeTransport({
      reveal_audit_entry: (args: Readonly<Record<string, unknown>>) =>
        args["entry"] === "1"
          ? { entry: 1, changes: { title: { old: "a", new: "b" } } }
          : null,
    });
    const audit = createAuditLog({ transport });
    expect(await audit.reveal({ id: "1" }).orThrow()).toEqual({
      entry: "1",
      changes: { title: { old: "a", new: "b" } },
    });
    expect(calls[0]!.args).toEqual({ entry: "1" });
    expect(await audit.reveal("2")).toMatchObject({
      ok: false,
      error: { kind: "not_found" },
    });
    const failing = createAuditLog(
      fakeTransport({
        reveal_audit_entry: () => {
          throw Object.assign(new Error("No audit entry 3"), {
            code: "P0002",
            hint: "AUDIT_ENTRY_NOT_FOUND",
          });
        },
        list_audit_events: () => {
          throw new Error("down");
        },
      }),
    );
    expect(await failing.reveal("3")).toMatchObject({
      ok: false,
      error: { hint: "AUDIT_ENTRY_NOT_FOUND" },
    });
    expect(await failing.list()).toMatchObject({ ok: false });
  });

  it("exports a tenant's entries as CSV to Storage", async () => {
    let served = 0;
    const { transport, calls } = fakeTransport({
      list_audit_events: () => {
        served += 1;
        return served === 1
          ? Array.from({ length: 1000 }, (_, i) => entry(2000 - i))
          : [entry(5, { record: "x,y" })];
      },
    });
    const uploads: { path: string; text: string }[] = [];
    const bucket = {
      async upload(path: string, body: Blob) {
        uploads.push({ path, text: await body.text() });
        return { error: null };
      },
      createSignedUrl: async (path: string, expiresIn: number) => ({
        data: { signedUrl: `https://s.test/${path}?e=${expiresIn}` },
        error: null,
      }),
    };
    const audit = createAuditLog({ transport });
    const result = await audit
      .exportCsv({
        tenant: "t1",
        bucket,
        path: "t1/audit.csv",
        expiresIn: 60,
        columns: ["id", "summary", "record", "metadata", "occurredAt"],
      })
      .orThrow();
    expect(result).toEqual({
      path: "t1/audit.csv",
      signedUrl: "https://s.test/t1/audit.csv?e=60",
      rows: 1001,
    });
    const lines = uploads[0]!.text.trim().split("\r\n");
    expect(lines[0]).toBe("id,summary,record,metadata,occurredAt");
    expect(lines[1]).toBe(
      '2000,"Changed, the ""total""",,"{""a"":1}",2026-01-01T00:00:00Z',
    );
    expect(lines.at(-1)).toContain('"x,y"');
    expect(calls[1]!.args).toMatchObject({
      before_id: "1001",
      for_tenant: "t1",
    });

    const capped = await audit
      .exportCsv({ tenant: "t1", bucket, maxRows: 0 })
      .orThrow();
    expect(capped.rows).toBe(0);
    expect(uploads[1]!.path).toMatch(/^t1\/audit-\d+\.csv$/);
  });

  it("reports storage and query failures", async () => {
    const audit = createAuditLog(
      fakeTransport({ list_audit_events: () => [] }),
    );
    const failed = {
      upload: async () => ({ error: new Error("full") }),
      createSignedUrl: async () => ({ data: null, error: null }),
    };
    expect(
      await audit.exportCsv({ tenant: "t", bucket: failed }),
    ).toMatchObject({ ok: false, error: { message: "full" } });
    const unsigned = { ...failed, upload: async () => ({ error: null }) };
    expect(
      await audit.exportCsv({ tenant: "t", bucket: unsigned }),
    ).toMatchObject({ ok: false, error: { message: "No signed URL" } });
    const broken = createAuditLog(
      fakeTransport({
        list_audit_events: () => {
          throw new Error("down");
        },
      }),
    );
    expect(
      await broken.exportCsv({ tenant: "t", bucket: unsigned }),
    ).toMatchObject({ ok: false });
  });

  it("quotes CSV fields", () => {
    expect(csvField(null)).toBe("");
    expect(csvField(undefined)).toBe("");
    expect(csvField("a\nb")).toBe('"a\nb"');
    expect(csvField(["x"])).toBe('"[""x""]"');
    expect(csvField(Temporal.Instant.from("2026-01-01T00:00:00Z"))).toBe(
      "2026-01-01T00:00:00Z",
    );
    expect(csvField(3)).toBe("3");
  });
});
