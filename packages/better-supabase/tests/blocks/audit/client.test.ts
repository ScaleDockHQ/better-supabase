import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../../src/core/block-transport.ts";

import { createAuditLog } from "../../../src/blocks/audit/index.ts";

const entry = (id: string, extra: Record<string, unknown> = {}) => ({
  id,
  occurredAt: `2026-10-06T12:00:0${id}Z`,
  op: "event",
  eventType: "invoice.sent",
  tenant: "org",
  ...extra,
});

function fake(pages: unknown[][], fail = false) {
  const calls: [string, Record<string, unknown>][] = [];
  const transport: BlockTransport = {
    async call(_schema, fn, args) {
      calls.push([fn, { ...args }]);
      if (fail) throw Object.assign(new Error("denied"), { code: "42501" });
      if (fn === "reveal_audit_entry")
        return {
          entry: args["entry"],
          old: { a: 1 },
          ip: "1.2.3.4",
          changes: { a: { old: 1, new: 2 } },
          metadata: "not an object",
        };
      return pages.shift() ?? [];
    },
  };
  return { transport, calls };
}

describe("createAuditLog", () => {
  it("lists entries with typed fields and a cursor for the next page", async () => {
    const { transport, calls } = fake([
      [
        entry("2", {
          changed: ["title"],
          metadata: { k: 1 },
          new: { title: "b" },
          actorId: null,
        }),
        entry("1"),
      ],
      [entry("0")],
    ]);
    const audit = createAuditLog({ transport, schema: "api" });
    const page = await audit
      .list({ organizationId: "org", limit: 2 })
      .orThrow();
    expect(page.entries[0]).toMatchObject({
      id: "2",
      changed: ["title"],
      metadata: { k: 1 },
      new: { title: "b" },
    });
    expect(page.entries[0]).not.toHaveProperty("actorId");
    expect(page.next).toEqual({
      occurredAt: page.entries[1]!.occurredAt,
      id: "1",
    });
    const last = await audit.list({ before: page.next, limit: 2 }).orThrow();
    expect(last.next).toBeUndefined();
    expect(calls[1]![1]).toMatchObject({
      before_at: "2026-10-06T12:00:01Z",
      before_id: "1",
      max_items: 2,
    });
  });

  it("reveals details and maps errors", async () => {
    const audit = createAuditLog({ transport: fake([]).transport });
    expect(await audit.reveal("7").orThrow()).toEqual({
      entry: "7",
      old: { a: 1 },
      ip: "1.2.3.4",
      changes: { a: { old: 1, new: 2 } },
    });
    const denied = createAuditLog({ transport: fake([], true).transport });
    expect((await denied.list()).ok).toBe(false);
  });

  it("exports NDJSON, OCSF and CSV page by page", async () => {
    const pages = () => [
      [entry("2"), entry("1")],
      [entry("0", { summary: "=1" })],
    ];
    const text = (format: "ndjson" | "csv" | "ocsf") =>
      new Response(
        createAuditLog({ transport: fake(pages()).transport }).export({
          format,
          batch: 2,
          product: { name: "Example" },
        }),
      ).text();
    expect((await text("ndjson")).trim().split("\n")).toHaveLength(3);
    const csv = await text("csv");
    expect(csv.split("\r\n")).toHaveLength(5);
    expect(csv).toContain("'=1");
    const ocsf = JSON.parse((await text("ocsf")).split("\n")[0]!) as Record<
      string,
      unknown
    >;
    expect(ocsf["class_uid"]).toBe(6003);
    expect(() =>
      createAuditLog({ transport: fake([]).transport }).export({
        format: "ocsf",
      }),
    ).toThrow(/needs product/);
    await expect(
      new Response(
        createAuditLog({ transport: fake([], true).transport }).export(),
      ).text(),
    ).rejects.toThrow(/denied/);
  });

  it("stores an export and reports upload failures", async () => {
    const audit = (fail = false) =>
      createAuditLog({ transport: fake([[entry("1")]], fail).transport });
    const storage = (error: unknown) => ({
      from: () => ({
        upload: async () => ({ data: null, error }),
      }),
    });
    expect(
      await audit()
        .exportToStorage({
          storage: storage(null),
          bucket: "b",
          path: "p.csv",
          format: "csv",
          signedUrlTtl: 60,
        })
        .orThrow(),
    ).toEqual({ path: "p.csv", url: undefined });
    expect(
      await audit().exportToStorage({
        storage: storage(new Error("no")),
        bucket: "b",
        path: "p",
      }),
    ).toMatchObject({ ok: false, error: { hint: "AUDIT_EXPORT_FAILED" } });
    expect(
      await audit(true).exportToStorage({
        storage: storage(null),
        bucket: "b",
        path: "p",
      }),
    ).toMatchObject({ ok: false, error: { hint: "AUDIT_EXPORT_FAILED" } });
  });
});
