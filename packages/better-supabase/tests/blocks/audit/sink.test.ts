import { describe, expect, it, vi } from "vitest";

import type { AuditEventInput } from "../../../src/blocks/audit/index.ts";
import type { Result } from "../../../src/core/result.ts";

import { auditEventOf, auditSink } from "../../../src/blocks/audit/index.ts";
import { MAX_BATCH } from "../../../src/core/batch-limit.ts";
import { dbError, DbException } from "../../../src/core/errors.ts";
import { AsyncResult, err, ok } from "../../../src/core/result.ts";

const base = { specversion: "1.0", id: "e1", source: "/crm" } as const;

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

  it("files account and support events under security by default", () => {
    expect(
      auditEventOf({ ...base, type: "dev.better-supabase.account.suspended" }),
    ).toMatchObject({ category: "security" });
    expect(
      auditEventOf({ ...base, type: "dev.better-supabase.support.denied" }),
    ).toMatchObject({ category: "security" });
    expect(auditEventOf({ ...base, type: "invoice.sent" })).not.toHaveProperty(
      "category",
    );
    expect(
      auditEventOf(
        { ...base, type: "invoice.sent" },
        {
          category: (type) => (type === "invoice.sent" ? "billing" : undefined),
        },
      ),
    ).toMatchObject({ category: "billing" });
  });
});

describe("auditEventOf for support events", () => {
  it("fills the impersonation fields from the session, admin and reason", () => {
    expect(
      auditEventOf({
        ...base,
        type: "dev.better-supabase.support.ended",
        data: {
          sessionId: "s1",
          adminId: "admin-1",
          targetUserId: "user-1",
          reason: "ticket 9",
          endedBy: "expired",
        },
      }),
    ).toMatchObject({
      eventType: "support.ended",
      supportSessionId: "s1",
      impersonatedBy: "admin-1",
      impersonationReason: "ticket 9",
    });
  });

  it("leaves them out for other events and for missing values", () => {
    const other = auditEventOf({
      ...base,
      type: "invoice.sent",
      data: { sessionId: "s1", adminId: "a" },
    });

    expect(other).not.toHaveProperty("supportSessionId");
    expect(other).not.toHaveProperty("impersonatedBy");

    const denied = auditEventOf({
      ...base,
      type: "dev.better-supabase.support.denied",
      data: { adminId: "admin-1", targetUserId: "user-1" },
    });

    expect(denied).toMatchObject({ impersonatedBy: "admin-1" });
    expect(denied).not.toHaveProperty("supportSessionId");
    expect(denied).not.toHaveProperty("impersonationReason");
    expect(
      auditEventOf({ ...base, type: "dev.better-supabase.support.started" }),
    ).not.toHaveProperty("impersonatedBy");
  });
});

describe("auditSink", () => {
  const recordMany = () =>
    vi.fn((events: readonly AuditEventInput[]) =>
      AsyncResult.ok<readonly Result<string>[]>(
        events.map((event) =>
          event.eventType === "bad"
            ? err(dbError("network", "down"))
            : ok("entry"),
        ),
      ),
    );

  it("records every event, then throws the first failure", async () => {
    const record = recordMany();
    const sink = auditSink(record);
    await sink.send([{ ...base, type: "good" }]);
    await expect(
      sink.send([
        { ...base, type: "bad" },
        { ...base, id: "e2", type: "good" },
      ]),
    ).rejects.toBeInstanceOf(DbException);
    expect(record).toHaveBeenCalledTimes(2);
    expect(record.mock.calls[1]?.[0]).toHaveLength(2);
  });

  it("sends one call per batch of MAX_BATCH events", async () => {
    const record = recordMany();
    const sink = auditSink(record);

    const events = Array.from({ length: MAX_BATCH + 1 }, (_, index) => ({
      ...base,
      id: `e${index}`,
      type: "good",
    }));

    await sink.send(events);
    expect(record).toHaveBeenCalledTimes(2);
    expect(record.mock.calls[0]?.[0]).toHaveLength(MAX_BATCH);
    expect(record.mock.calls[1]?.[0]).toHaveLength(1);
  });

  it("throws when a whole batch fails, after the other batches run", async () => {
    let calls = 0;

    const record = vi.fn((events: readonly AuditEventInput[]) => {
      calls += 1;

      return calls === 1
        ? AsyncResult.err<readonly Result<string>[]>(dbError("network", "down"))
        : AsyncResult.ok<readonly Result<string>[]>(
            events.map(() => ok("entry")),
          );
    });

    const events = Array.from({ length: MAX_BATCH + 1 }, (_, index) => ({
      ...base,
      id: `e${index}`,
      type: "good",
    }));

    await expect(auditSink(record).send(events)).rejects.toBeInstanceOf(
      DbException,
    );
    expect(record).toHaveBeenCalledTimes(2);
  });
});
