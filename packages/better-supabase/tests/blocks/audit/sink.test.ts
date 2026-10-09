import { describe, expect, it, vi } from "vitest";

import type { AuditEventInput } from "../../../src/blocks/audit/index.ts";

import { auditEventOf, auditSink } from "../../../src/blocks/audit/index.ts";
import { dbError, DbException } from "../../../src/core/errors.ts";
import { AsyncResult } from "../../../src/core/result.ts";

const base = {
  specversion: "1.0",
  id: "e1",
  source: "/crm",
} as const;

describe("auditEventOf", () => {
  it("maps type, subject, tenant, actor and data", () => {
    expect(
      auditEventOf({
        ...base,
        type: "dev.better-supabase.invoice.sent",
        subject: "invoices/42",
        partitionkey: "org-1",
        data: { actorId: "u1", total: 5 },
      }),
    ).toEqual({
      eventType: "invoice.sent",
      idempotencyKey: "/crm#e1",
      record: "invoices/42",
      organizationId: "org-1",
      actorId: "u1",
      metadata: { actorId: "u1", total: 5 },
    });
  });

  it("reads the tenant from the extension, then the data", () => {
    expect(
      auditEventOf({
        ...base,
        type: "com.acme.thing",
        tenant: "org-2",
        data: { organizationId: "org-3" },
      }).organizationId,
    ).toBe("org-2");
    expect(
      auditEventOf(
        { ...base, type: "com.acme.thing", data: { organizationId: "org-3" } },
        { typePrefix: "com.acme" },
      ),
    ).toMatchObject({ eventType: "thing", organizationId: "org-3" });
    expect(auditEventOf({ ...base, type: "x", data: 7 })).toMatchObject({
      eventType: "x",
      metadata: { data: 7 },
    });
    expect(auditEventOf({ ...base, type: "x" })).not.toHaveProperty("metadata");
  });
});

describe("auditSink", () => {
  it("records every event, then throws the first failure", async () => {
    const record = vi.fn((event: AuditEventInput) =>
      event.eventType === "bad"
        ? AsyncResult.err<string>(dbError("network", "down"))
        : AsyncResult.ok("entry"),
    );
    const sink = auditSink(record);
    await sink.send([{ ...base, type: "good" }]);
    await expect(
      sink.send([
        { ...base, type: "bad" },
        { ...base, id: "e2", type: "good" },
      ]),
    ).rejects.toBeInstanceOf(DbException);
    expect(record).toHaveBeenCalledTimes(3);
  });
});
