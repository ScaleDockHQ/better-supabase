/* oxlint-disable typescript/no-deprecated -- these tests cover the deprecated list until 0.70 (ADR 1077). */
import { describe, expect, it } from "vitest";

import { createImpersonation } from "../../../src/blocks/impersonation/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-22T10:00:00Z";

const SESSION = {
  id: "s1",
  admin_id: "a1",
  target_user_id: "u1",
  reason: "support ticket",
  read_only: true,
  tenant: null,
  started_at: AT,
  expires_at: AT,
  ended_at: AT,
  ended_by: "admin",
  metadata: { ticket: 7 },
};

describe("support session pages", () => {
  it("maps the rows of the page and the get", async () => {
    const transport = fieldsTransport({
      page_support_sessions: () => ({ items: [SESSION], hasMore: false }),
      get_support_session: () => SESSION,
    });

    const impersonation = createImpersonation({ transport });
    const page = await impersonation.sessionPage().orThrow();

    expect(page.items[0]).toMatchObject({
      id: "s1",
      endedBy: "admin",
      metadata: { ticket: 7 },
    });
    expect((await impersonation.getSession("s1").orThrow()).readOnly).toBe(
      true,
    );
    expect(transport.calls[0]).toEqual([
      "page_support_sessions",
      { filters: { paged: true } },
    ]);
  });

  it("reads the facets and the count of the sessions", async () => {
    const transport = fieldsTransport({
      page_support_sessions: (args) => {
        const filters = args["filters"] as Record<string, unknown>;

        return filters["facet"] === undefined
          ? { value: 3, exact: true }
          : {
              facet: filters["facet"],
              values: [{ value: true, count: { value: 3, exact: true } }],
            };
      },
    });

    const impersonation = createImpersonation({ transport });
    const facets = await impersonation.sessionFacets().orThrow();

    expect(await impersonation.sessionCount().orThrow()).toEqual({
      value: 3,
      exact: true,
    });
    expect(Array.isArray(facets)).toBe(true);
  });
});

describe("support requests and sessions", () => {
  const REQUEST = {
    id: "r1",
    admin_id: "a1",
    target_user_id: "u1",
    reason: null,
    read_only: false,
    tenant: "org-1",
    metadata: "x",
    requested_at: AT,
    expires_at: AT,
    approved_by: "a2",
    approved_at: AT,
    session_id: "s1",
  };

  it("requests and approves a support session", async () => {
    const transport = fieldsTransport({
      request_support_session: () => ({
        ...REQUEST,
        approved_by: null,
        approved_at: null,
        session_id: null,
      }),
      approve_support_request: () => REQUEST,
    });

    const impersonation = createImpersonation({ transport });

    const requested = await impersonation
      .request({
        target: "u1",
        reason: "ticket 7",
        readOnly: false,
        tenant: "org-1",
      })
      .orThrow();

    const approved = await impersonation.approve("r1").orThrow();

    await impersonation.request({ target: "u1" }).orThrow();

    expect(requested).toMatchObject({
      reason: "",
      readOnly: false,
      tenant: "org-1",
      metadata: {},
      approvedBy: undefined,
      approvedAt: undefined,
      sessionId: undefined,
    });
    expect(approved).toMatchObject({ approvedBy: "a2", sessionId: "s1" });
    expect(approved.approvedAt?.toString()).toBe(AT);
    expect(transport.calls.map((call) => call[1])).toEqual([
      {
        target: "u1",
        reason: "ticket 7",
        read_only: false,
        metadata: {},
        tenant: "org-1",
      },
      { request_id: "r1" },
      {
        target: "u1",
        reason: null,
        read_only: true,
        metadata: {},
        tenant: null,
      },
    ]);
  });

  it("starts, ends and lists sessions", async () => {
    const live = { ...SESSION, ended_at: null, ended_by: "someone" };

    const transport = fieldsTransport({
      start_support_session: () => live,
      end_support_session: () => true,
      list_support_sessions: () => [live, SESSION],
    });

    const impersonation = createImpersonation({ transport });

    const started = await impersonation
      .start({
        target: "u1",
        reason: "ticket 7",
        ttlSeconds: 60,
        readOnly: false,
        metadata: { ticket: 7 },
        tenant: "org-1",
      })
      .orThrow();

    await impersonation.start({ target: "u1" }).orThrow();
    expect(await impersonation.end("s1").orThrow()).toBe(true);

    const listed = await impersonation
      .list({ adminId: "a1", targetUserId: "u1", active: true, limit: 5 })
      .orThrow();

    await impersonation.list().orThrow();

    expect(started).toMatchObject({ endedAt: undefined, endedBy: undefined });
    expect(listed.map((session) => session.endedBy)).toEqual([
      undefined,
      "admin",
    ]);
    expect(transport.calls.map((call) => call[1])).toEqual([
      {
        target: "u1",
        reason: "ticket 7",
        ttl: "60 seconds",
        read_only: false,
        metadata: { ticket: 7 },
        tenant: "org-1",
      },
      {
        target: "u1",
        reason: null,
        ttl: "1800 seconds",
        read_only: true,
        metadata: {},
        tenant: null,
      },
      { session_id: "s1" },
      { admin_id: "a1", target: "u1", active: true, max_rows: 5 },
      { admin_id: null, target: null, active: null, max_rows: 50 },
    ]);
  });
});
