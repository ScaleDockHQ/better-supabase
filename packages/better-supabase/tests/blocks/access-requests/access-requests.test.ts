import { describe, expect, it } from "vitest";

import { createAccessRequests } from "../../../src/blocks/access-requests/index.ts";
import { temporal } from "../../../src/core/temporal-required.ts";

const PENDING = {
  id: "r1",
  organizationId: "o",
  userId: "u1",
  role: "admin",
  status: "pending",
  approvalId: "a1",
  reason: "Incident",
  duration: "PT2H",
  createdAt: "2026-10-01T00:00:00Z",
};

const GRANTED = {
  ...PENDING,
  status: "granted",
  previousRole: "member",
  grantedAt: "2026-10-01T00:05:00Z",
  expiresAt: "2026-10-01T02:05:00Z",
  endedAt: null,
};

function transport(results: Record<string, (args: unknown) => unknown>) {
  const calls: [string, unknown][] = [];

  return {
    calls,
    call(schema: string, fn: string, args: unknown) {
      expect(schema).toBe("app");
      calls.push([fn, args]);
      const result = results[fn];

      if (!result) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }

      return Promise.resolve(result(args));
    },
  };
}

describe("access requests client", () => {
  it("requests, reads, lists and ends a role", async () => {
    const fake = transport({
      request_access: () => PENDING,
      get_access_request: () => GRANTED,
      list_access_requests: () => [
        GRANTED,
        {
          id: "r0",
          organizationId: "o",
          userId: "u1",
          role: "admin",
          status: "ended",
          createdAt: "2026-09-01T00:00:00Z",
          endedAt: "2026-09-01T01:00:00Z",
        },
      ],
      end_access: () => ({ ...GRANTED, status: "ended" }),
    });

    const access = createAccessRequests({ transport: fake, schema: "app" });

    const requested = await access
      .request({
        organizationId: "o",
        role: "admin",
        reason: "Incident",
        duration: temporal().Duration.from({ hours: 2 }),
      })
      .orThrow();

    expect(requested).toMatchObject({
      status: "pending",
      approvalId: "a1",
      reason: "Incident",
    });
    expect(requested.duration?.toString()).toBe("PT2H");
    expect(requested).not.toHaveProperty("grantedAt");

    const granted = await access.get("r1").orThrow();
    expect(granted).toMatchObject({ target: "role", previousRole: "member" });
    expect(granted.expiresAt?.toString()).toBe("2026-10-01T02:05:00Z");
    expect(granted).not.toHaveProperty("endedAt");

    const listed = await access
      .list("o", {
        status: "granted",
        mine: true,
        pageSize: 5,
        before: temporal().Instant.from("2026-10-02T00:00:00Z"),
      })
      .orThrow();

    expect(listed[1]).not.toHaveProperty("reason");
    expect(listed[1]).not.toHaveProperty("duration");
    expect(listed[1]!.endedAt?.toString()).toBe("2026-09-01T01:00:00Z");
    await access.list("o").orThrow();

    expect((await access.end("r1").orThrow()).status).toBe("ended");
    expect(fake.calls).toEqual([
      [
        "request_access",
        { tenant: "o", role: "admin", reason: "Incident", duration: "PT2H" },
      ],
      ["get_access_request", { request_id: "r1" }],
      [
        "list_access_requests",
        {
          tenant: "o",
          status: "granted",
          mine: true,
          page_size: 5,
          before: "2026-10-02T00:00:00Z",
        },
      ],
      [
        "list_access_requests",
        {
          tenant: "o",
          status: null,
          mine: false,
          page_size: null,
          before: null,
        },
      ],
      ["end_access", { request_id: "r1" }],
    ]);
  });

  it("sends nulls for an open-ended request and rejects an unknown status", async () => {
    const fake = transport({
      request_access: () => ({ ...PENDING, status: "lost" }),
    });

    const access = createAccessRequests({ transport: fake, schema: "app" });
    const result = await access.request({ organizationId: "o", role: "admin" });
    expect(result.ok).toBe(false);
    expect(fake.calls[0]![1]).toEqual({
      tenant: "o",
      role: "admin",
      reason: null,
      duration: null,
    });
  });

  it("requests record access, opens and reviews emergency access", async () => {
    const RECORD = {
      id: "r2",
      organizationId: "o",
      userId: "u1",
      role: null,
      target: "record",
      subjectType: "client",
      subjectId: "c1",
      action: "read",
      emergency: false,
      review: null,
      status: "pending",
      approvalId: "a2",
      duration: "P7D",
      createdAt: "2026-10-01T00:00:00Z",
    };

    const EMERGENCY = {
      ...RECORD,
      id: "r3",
      emergency: true,
      status: "granted",
      approvalId: null,
      reason: "Patient in the ER",
      duration: "PT8H",
      grantedAt: "2026-10-01T00:00:00Z",
      expiresAt: "2026-10-01T08:00:00Z",
    };

    const REVIEWED = {
      ...EMERGENCY,
      review: {
        verdict: "justified",
        note: "Checked the chart",
        reviewedBy: "u2",
        reviewedAt: "2026-10-02T00:00:00Z",
      },
    };

    const fake = transport({
      request_record_access: () => RECORD,
      open_emergency_access: () => EMERGENCY,
      review_emergency_access: () => REVIEWED,
      list_emergency_access: () => [
        EMERGENCY,
        { ...REVIEWED, review: { ...REVIEWED.review, note: null } },
      ],
    });

    const access = createAccessRequests({ transport: fake, schema: "app" });

    const requested = await access
      .requestRecord({ subjectType: "client", subjectId: "c1" })
      .orThrow();

    expect(requested).toMatchObject({
      target: "record",
      subjectType: "client",
      subjectId: "c1",
      action: "read",
      emergency: false,
    });
    expect(requested).not.toHaveProperty("role");
    expect(requested).not.toHaveProperty("review");

    const opened = await access
      .openEmergency({
        subjectType: "client",
        subjectId: "c1",
        reason: "Patient in the ER",
      })
      .orThrow();

    expect(opened.emergency).toBe(true);
    expect(opened.expiresAt?.toString()).toBe("2026-10-01T08:00:00Z");

    const reviewed = await access
      .reviewEmergency("r3", {
        verdict: "justified",
        note: "Checked the chart",
      })
      .orThrow();

    expect(reviewed.review).toMatchObject({
      verdict: "justified",
      note: "Checked the chart",
      reviewedBy: "u2",
    });
    expect(reviewed.review?.reviewedAt.toString()).toBe("2026-10-02T00:00:00Z");

    const listed = await access.emergencies("o").orThrow();
    expect(listed).toHaveLength(2);
    expect(listed[1]!.review).not.toHaveProperty("note");
    await access
      .emergencies("o", {
        unreviewed: false,
        pageSize: 10,
        before: temporal().Instant.from("2026-10-03T00:00:00Z"),
      })
      .orThrow();
    await access.requestRecord({
      subjectType: "client",
      subjectId: "c1",
      action: "write",
      reason: "Audit",
      duration: temporal().Duration.from({ days: 1 }),
    });
    await access.reviewEmergency("r3", { verdict: "unjustified" });

    expect(fake.calls).toEqual([
      [
        "request_record_access",
        {
          subject_type: "client",
          subject_id: "c1",
          action: "read",
          reason: null,
          duration: null,
        },
      ],
      [
        "open_emergency_access",
        {
          subject_type: "client",
          subject_id: "c1",
          reason: "Patient in the ER",
        },
      ],
      [
        "review_emergency_access",
        { request_id: "r3", verdict: "justified", note: "Checked the chart" },
      ],
      [
        "list_emergency_access",
        { tenant: "o", unreviewed: true, page_size: null, before: null },
      ],
      [
        "list_emergency_access",
        {
          tenant: "o",
          unreviewed: false,
          page_size: 10,
          before: "2026-10-03T00:00:00Z",
        },
      ],
      [
        "request_record_access",
        {
          subject_type: "client",
          subject_id: "c1",
          action: "write",
          reason: "Audit",
          duration: "P1D",
        },
      ],
      [
        "review_emergency_access",
        { request_id: "r3", verdict: "unjustified", note: null },
      ],
    ]);
  });

  it("rejects a reply of the wrong kind or with an unknown verdict", async () => {
    const access = createAccessRequests({
      transport: transport({
        request_access: () => ({
          ...PENDING,
          target: "record",
          subjectType: "client",
          subjectId: "c1",
          action: "read",
        }),
        request_record_access: () => PENDING,
        review_emergency_access: () => ({
          ...PENDING,
          target: "record",
          subjectType: "client",
          subjectId: "c1",
          action: "read",
          emergency: true,
          review: {
            verdict: "maybe",
            reviewedBy: "u2",
            reviewedAt: "2026-10-02T00:00:00Z",
          },
        }),
      }),
      schema: "app",
    });

    expect(
      (await access.request({ organizationId: "o", role: "admin" })).ok,
    ).toBe(false);
    expect(
      (await access.requestRecord({ subjectType: "client", subjectId: "c1" }))
        .ok,
    ).toBe(false);
    expect(
      (await access.reviewEmergency("r1", { verdict: "justified" })).ok,
    ).toBe(false);
  });
});
