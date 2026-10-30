import { Pool } from "pg";
import * as v from "valibot";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { TestUser } from "./block-session.ts";

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

  it("grants a record through its lead and opens emergency access for review", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.rows(
        `create table public.bsb_clients (
           id uuid primary key default gen_random_uuid(),
           organization_id uuid not null,
           name text not null
         )`,
      );
      await s.rows("grant select on public.bsb_clients to authenticated");
      await s.install([...MODULES, "subjects"], {
        subjects: {
          client: {
            table: "public.bsb_clients",
            idType: "uuid",
            title: "name",
            permissions: { read: "clients.read" },
            team: { actions: ["read"] },
          },
        },
      });

      const owner = await s.user("owner");
      const admin = await s.user("admin");
      const lead = await s.user("lead");
      const requester = await s.user("requester");

      const tenant = await s.organization(owner, {
        admin,
        member: lead,
        member2: requester,
      });

      await s.service();

      const [row] = await s.rows<{ id: string }>(
        "insert into public.bsb_clients (organization_id, name) values ($1, 'Ada') returning id",
        [tenant],
      );

      const client = row!.id;

      await s.asRole(owner);
      await s.value(
        "better_supabase.add_subject_member('client', $1, $2, role => 'lead')",
        [client, lead.id],
      );

      const transport = sqlTransport(s.sql);
      const access = createAccessRequests({ transport });
      const approvals = createApprovals({ transport });

      const canRead = async (user: TestUser) => {
        await s.asRole(user);

        const allowed = await s.value<boolean>(
          "better_supabase.can_subject('client', $1, 'read')",
          [client],
        );

        await s.service();

        return allowed;
      };

      const recipients = async (type: string, subject: string) => {
        await s.service();

        const rows = await s.rows<{ user_id: string }>(
          `select r.user_id::text from better_supabase.notification_recipients r
           join better_supabase.notification_events e on e.id = r.event_id
           where e.type = $1 and e.subject_id = $2 order by 1`,
          [type, subject],
        );

        return rows.map((each) => each.user_id).toSorted();
      };

      await s.asRole(requester);
      expect(
        await access
          .requestRecord({
            subjectType: "client",
            subjectId: client,
            action: "write",
          })
          .then(hint),
      ).toBe("ACCESS_REQUEST_RECORD_INVALID");

      const request = await access
        .requestRecord({
          subjectType: "client",
          subjectId: client,
          reason: "Covering for the lead",
          duration: temporal().Duration.from({ days: 2 }),
        })
        .orThrow();

      expect(request).toMatchObject({
        target: "record",
        subjectType: "client",
        subjectId: client,
        action: "read",
        status: "pending",
      });
      expect(
        await access
          .requestRecord({ subjectType: "client", subjectId: client })
          .then(hint),
      ).toBe("ACCESS_REQUEST_PENDING");
      expect(await recipients("approval.requested", request.id)).toEqual([
        lead.id,
      ]);

      await s.asRole(lead);
      await approvals.approve(request.approvalId!).orThrow();
      expect(await canRead(requester)).toBe(true);

      await s.asRole(requester);
      expect((await access.end(request.id).orThrow()).status).toBe("ended");
      expect(await canRead(requester)).toBe(false);
      expect(await canRead(lead)).toBe(true);

      await s.asRole(requester);
      expect(
        await access
          .openEmergency({
            subjectType: "client",
            subjectId: client,
            reason: "The client is in the ward now",
          })
          .then(hint),
      ).toBe("ACCESS_REQUEST_FORBIDDEN");

      await s.asRole(admin);
      expect(
        await access
          .openEmergency({
            subjectType: "client",
            subjectId: client,
            reason: "now",
          })
          .then(hint),
      ).toBe("ACCESS_REQUEST_REASON_REQUIRED");

      const emergency = await access
        .openEmergency({
          subjectType: "client",
          subjectId: client,
          reason: "The client is in the ward now",
        })
        .orThrow();

      expect(emergency).toMatchObject({
        target: "record",
        emergency: true,
        status: "granted",
      });
      expect(await canRead(admin)).toBe(true);
      expect(
        await recipients("access_request.emergency_opened", client),
      ).toEqual([owner.id, lead.id].toSorted());

      await s.asRole(admin);
      expect(
        await access
          .reviewEmergency(emergency.id, { verdict: "justified" })
          .then(hint),
      ).toBe("ACCESS_REQUEST_REVIEW_INVALID");

      await s.asRole(owner);
      expect(await access.emergencies(tenant).orThrow()).toHaveLength(1);

      const reviewed = await access
        .reviewEmergency(emergency.id, {
          verdict: "unjustified",
          note: "No ward visit that day",
        })
        .orThrow();

      expect(reviewed.review).toMatchObject({
        verdict: "unjustified",
        note: "No ward visit that day",
        reviewedBy: owner.id,
      });
      expect(await access.emergencies(tenant).orThrow()).toEqual([]);
      expect(
        await access.emergencies(tenant, { unreviewed: false }).orThrow(),
      ).toHaveLength(1);
    } finally {
      await s.close();
    }
  });
});
