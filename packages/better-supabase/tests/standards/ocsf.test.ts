import { describe, expect, it } from "vitest";

import { toOcsf } from "../../src/blocks/audit/index.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

// OCSF 1.9.0: base attributes every event carries, and the attributes the
// classes exportAuditLog emits require (schema.ocsf.io/1.9.0/classes).
const BASE = [
  "activity_id",
  "category_uid",
  "class_uid",
  "metadata",
  "severity_id",
  "time",
  "type_uid",
] as const;
const CLASS_REQUIRED: Readonly<Record<number, readonly string[]>> = {
  3004: ["entity"],
  6003: ["actor", "api", "src_endpoint"],
};
const CATEGORY: Readonly<Record<number, number>> = { 3004: 3, 6003: 6 };
const ACTIVITIES: Readonly<Record<number, readonly number[]>> = {
  3004: [1, 2, 3, 4, 99],
  6003: [1, 2, 3, 4, 99],
};

const at = Temporal.Instant.from("2026-10-06T12:00:00Z");
const ENTRIES = [
  {
    id: "1",
    occurredAt: at,
    op: "insert",
    table: "public.deals",
    record: "d1",
  },
  {
    id: "2",
    occurredAt: at,
    op: "update",
    table: "public.deals",
    record: "d1",
    changed: ["stage"],
  },
  {
    id: "3",
    occurredAt: at,
    op: "delete",
    table: "public.deals",
    record: "d1",
  },
  {
    id: "4",
    occurredAt: at,
    op: "event",
    eventType: "api_key.created",
    actor: "u1",
  },
  {
    id: "5",
    occurredAt: at,
    op: "event",
    eventType: "report.exported",
    outcome: "success",
  },
  {
    id: "6",
    occurredAt: at,
    op: "event",
    eventType: "deal.renamed",
    outcome: "failure",
  },
  { id: "7", occurredAt: at, op: "event", eventType: "member.removed" },
  {
    id: "8",
    occurredAt: at,
    op: "event",
    eventType: "sso.enforced",
    outcome: "skipped",
  },
];

describe("OCSF events from exportAuditLog", () => {
  it(`pins OCSF ${SPEC_PINS.ocsf}`, () => {
    expect(SPEC_PINS.ocsf).toBe("1.9.0");
  });

  it.each(ENTRIES.map((entry) => [entry.id, entry] as const))(
    "entry %s has the base and class attributes",
    (_id, entry) => {
      const event = toOcsf(entry, { name: "Acme", vendor_name: "Acme Inc." });
      for (const attribute of BASE) expect(event).toHaveProperty(attribute);
      const classUid = Number(event["class_uid"]);
      const activity = Number(event["activity_id"]);
      expect(event["category_uid"]).toBe(CATEGORY[classUid]);
      for (const attribute of CLASS_REQUIRED[classUid] ?? [])
        expect(event).toHaveProperty(attribute);
      expect(ACTIVITIES[classUid]).toContain(activity);
      // type_uid is class_uid * 100 + activity_id.
      expect(event["type_uid"]).toBe(classUid * 100 + activity);
      // 99 (Other) needs its sibling string.
      expect(
        activity !== 99 || typeof event["activity_name"] === "string",
      ).toBe(true);
      expect(
        event["status_id"] !== 99 || typeof event["status"] === "string",
      ).toBe(true);
      expect(event["metadata"]).toMatchObject({
        version: SPEC_PINS.ocsf,
        product: { name: "Acme" },
      });
      expect([0, 1, 2, 3, 4, 5, 6, 99]).toContain(event["severity_id"]);
      expect(Number.isInteger(event["time"])).toBe(true);
      expect(
        classUid !== 6003 ||
          typeof (event["api"] as { operation?: unknown }).operation ===
            "string",
      ).toBe(true);
    },
  );
});
