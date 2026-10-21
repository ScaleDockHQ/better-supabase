import { Pool } from "pg";
import * as v from "valibot";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";

import { createAccessRequests } from "../../src/blocks/access-requests/index.ts";
import {
  createApprovals,
  sqlTransport,
} from "../../src/blocks/approvals/index.ts";
import { temporal } from "../../src/core/temporal-required.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = [
  "organizations",
  "outbox",
  "notifications",
  "approvals",
  "access-requests",
];

describe.skipIf(!live)("access requests", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  const hint = (result: Result<unknown>) =>
    result.ok ? "ok" : result.error.hint;

  it("grants a requested role on approval and puts it back when it ends", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const requester = await s.user("requester");
      const viewer = await s.user("viewer");
      await s.install(MODULES, {
        modules: { "access-requests": { options: { maxDuration: "P7D" } } },
      });

      const tenant = await s.organization(owner, { member: requester, viewer });

      const transport = sqlTransport(s.sql);
      const access = createAccessRequests({ transport });
      const approvals = createApprovals({ transport });

      const roleOf = (user: string) =>
        s.value<string>(
          "(select role from better_supabase.memberships where organization_id = $1 and user_id = $2)",
          [tenant, user],
        );

      await s.asRole(requester);
      expect(
        await access
          .request({ organizationId: tenant, role: "owner" })
          .then(hint),
      ).toBe("ACCESS_ROLE_INVALID");
      expect(
        await access
          .request({ organizationId: tenant, role: "member" })
          .then(hint),
      ).toBe("ACCESS_ROLE_HELD");
      expect(
        await access
          .request({
            organizationId: tenant,
            role: "admin",
            duration: temporal().Duration.from({ days: 30 }),
          })
          .then(hint),
      ).toBe("ACCESS_DURATION_INVALID");

      const request = await access
        .request({ organizationId: tenant, role: "admin", reason: "month end" })
        .orThrow();

      expect(request).toMatchObject({ status: "pending", role: "admin" });
      expect(request.duration?.toString()).toBe("P7D");
      expect(
        await access
          .request({ organizationId: tenant, role: "admin" })
          .then(hint),
      ).toBe("ACCESS_REQUEST_PENDING");

      await s.asRole(viewer);
      expect(
        await access
          .request({ organizationId: tenant, role: "admin" })
          .then(hint),
      ).toBe("ACCESS_REQUEST_FORBIDDEN");

      await s.service();
      expect(
        await s.rows<{ user_id: string }>(
          `select r.user_id::text from better_supabase.notification_recipients r
           join better_supabase.notification_events e on e.id = r.event_id
           where e.type = 'approval.requested' and e.subject_id = $1`,
          [request.id],
        ),
      ).toEqual([{ user_id: owner.id }]);

      await s.asRole(requester);
      expect(await approvals.approve(request.approvalId!).then(hint)).toBe(
        "APPROVAL_FORBIDDEN",
      );
      await s.asRole(owner);
      await approvals.approve(request.approvalId!).orThrow();
      const granted = await access.get(request.id).orThrow();
      expect(granted).toMatchObject({
        status: "granted",
        previousRole: "member",
      });
      expect(granted.expiresAt).toBeDefined();
      expect(await roleOf(requester.id)).toBe("admin");

      await s.asRole(viewer);
      expect(await access.end(request.id).then(hint)).toBe(
        "ACCESS_REQUEST_FORBIDDEN",
      );
      expect(await access.list(tenant).orThrow()).toEqual([]);

      await s.service();
      await s.client.query(
        "update better_supabase.access_requests set expires_at = now() - interval '1 minute' where id = $1",
        [request.id],
      );
      expect(
        await s.value<number>("better_supabase.expire_access_grants()"),
      ).toBe(1);
      expect(await roleOf(requester.id)).toBe("member");

      await s.asRole(requester);
      expect((await access.get(request.id).orThrow()).status).toBe("ended");
      expect(await access.end(request.id).then(hint)).toBe(
        "ACCESS_NOT_GRANTED",
      );

      await s.service();
      expect(
        await s.rows<{ type: string }>(
          `select type from better_supabase.outbox_events
           where subject = $1 order by type`,
          [`access-requests/${request.id}`],
        ),
      ).toEqual([
        { type: "access.ended" },
        { type: "access.request_approved" },
        { type: "access.requested" },
      ]);
    } finally {
      await s.close();
    }
  });

  it("lets outsiders ask to join and follows a rejection", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const outsider = await s.user("outsider");
      const other = await s.user("other");
      await s.install(MODULES, {
        modules: { "access-requests": { options: { join: true } } },
      });
      const tenant = await s.organization(owner);
      const transport = sqlTransport(s.sql);
      const access = createAccessRequests({ transport });
      const approvals = createApprovals({ transport });

      await s.asRole(outsider);

      const join = await access
        .request({ organizationId: tenant, role: "member" })
        .orThrow();

      await s.asRole(other);

      const rejected = await access
        .request({ organizationId: tenant, role: "viewer" })
        .orThrow();

      await s.asRole(owner);
      expect(
        await access.list(tenant, { status: "pending" }).orThrow(),
      ).toHaveLength(2);
      await approvals.reject(rejected.approvalId!).orThrow();
      await approvals.approve(join.approvalId!).orThrow();
      const ended = await access.end(join.id).orThrow();
      expect(ended).toMatchObject({ status: "ended" });

      await s.asRole(other);
      expect((await access.get(rejected.id).orThrow()).status).toBe("rejected");
      expect(
        (await access.list(tenant).orThrow()).map((row) => row.id),
      ).toEqual([rejected.id]);

      await s.service();
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.memberships where organization_id = $1 and user_id = $2)",
          [tenant, outsider.id],
        ),
      ).toBe(0);
    } finally {
      await s.close();
    }
  });

  it("stores, validates and returns extra columns", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const requester = await s.user("requester");
      await s.install(MODULES, {
        modules: {
          "access-requests": {
            options: { extraColumns: { ticket: "text", priority: "integer" } },
          },
        },
      });
      const tenant = await s.organization(owner, { member: requester });

      const access = createAccessRequests({
        transport: sqlTransport(s.sql),
        fields: v.object({
          ticket: v.nullable(v.string()),
          priority: v.nullable(v.pipe(v.number(), v.minValue(1))),
        }),
      });

      await s.asRole(requester);
      expect(
        await access
          .request({ organizationId: tenant, role: "admin", priority: 0 })
          .then((result) => (result.ok ? "ok" : result.error.kind)),
      ).toBe("validation");

      const request = await access
        .request({ organizationId: tenant, role: "admin", ticket: "OPS-1" })
        .orThrow();

      expect(request).toMatchObject({
        role: "admin",
        ticket: "OPS-1",
        priority: null,
      });
      const [listed] = await access.list(tenant).orThrow();
      expect(listed).toMatchObject({ id: request.id, ticket: "OPS-1" });
    } finally {
      await s.close();
    }
  });
});
