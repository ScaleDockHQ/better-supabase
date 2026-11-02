import { describe, expect, it } from "vitest";

import { createBookings } from "../../src/blocks/bookings/index.ts";
import { createConsents } from "../../src/blocks/consents/index.ts";
import { createLeave } from "../../src/blocks/leave/index.ts";
import { createQualifications } from "../../src/blocks/qualifications/index.ts";
import { createShifts } from "../../src/blocks/shifts/index.ts";
import { fieldsTransport } from "./fields-transport.ts";

describe("consents.require", () => {
  it("succeeds when the consent is active", async () => {
    const consents = createConsents({
      transport: fieldsTransport({ consent_active: () => true }),
    });

    expect(
      await consents
        .require({
          subject: { type: "patient", id: "p1" },
          purposeKey: "research",
        })
        .orThrow(),
    ).toBe(true);
  });

  it("fails with forbidden and the consent permission otherwise", async () => {
    const consents = createConsents({
      transport: fieldsTransport({ consent_active: () => false }),
    });

    const result = await consents.require({
      subject: { type: "patient", id: "p1" },
      purposeKey: "research",
    });

    expect(result.ok ? undefined : result.error.kind).toBe("forbidden");
  });
});

describe("qualifications.check", () => {
  it("is true when the holder is among the qualified holders", async () => {
    const t = fieldsTransport({ qualified_holders: () => ["u1", "u2"] });

    const qualifications = createQualifications({ transport: t });

    expect(
      await qualifications
        .check({ organizationId: "o", typeKey: "first-aid", holderId: "u2" })
        .orThrow(),
    ).toBe(true);

    expect(
      await qualifications
        .check({ organizationId: "o", typeKey: "first-aid", holderId: "u9" })
        .orThrow(),
    ).toBe(false);
  });
});

describe("leave.pending, approve and reject", () => {
  it("lists pending requests", async () => {
    const t = fieldsTransport({ list_leave_requests: () => [] });

    const leave = createLeave({ transport: t });

    await leave.pending({ organizationId: "o", everyone: true }).orThrow();

    expect(t.calls[0]?.[1]).toMatchObject({
      status: "pending",
      everyone: true,
    });
  });
});

describe("shifts.rollout", () => {
  it("generates and publishes the range when asked", async () => {
    const t = fieldsTransport({
      generate_shifts: () => [],
      publish_shifts: () => 3,
    });

    const shifts = createShifts({ transport: t });

    const rolled = await shifts
      .rollout({
        organizationId: "o",
        templateId: "t",
        from: Temporal.PlainDate.from("2026-11-02"),
        until: Temporal.PlainDate.from("2026-11-08"),
        publish: true,
      })
      .orThrow();

    expect(rolled.published).toBe(3);
    expect(t.calls.map(([fn]) => fn)).toEqual([
      "generate_shifts",
      "publish_shifts",
    ]);
  });

  it("does not publish by default", async () => {
    const t = fieldsTransport({ generate_shifts: () => [] });

    const shifts = createShifts({ transport: t });

    const rolled = await shifts
      .rollout({
        organizationId: "o",
        templateId: "t",
        from: Temporal.PlainDate.from("2026-11-02"),
        until: Temporal.PlainDate.from("2026-11-08"),
      })
      .orThrow();

    expect(rolled.published).toBe(0);
    expect(t.calls).toHaveLength(1);
  });
});

describe("bookings.book", () => {
  it("fails with not_found when no resource is free", async () => {
    const bookings = createBookings({
      transport: fieldsTransport({ available_slots: () => [] }),
    });

    const result = await bookings.book({
      serviceId: "s",
      startsAt: Temporal.Instant.from("2026-11-02T10:00:00Z"),
    });

    expect(result.ok ? undefined : result.error.kind).toBe("not_found");
  });
});
