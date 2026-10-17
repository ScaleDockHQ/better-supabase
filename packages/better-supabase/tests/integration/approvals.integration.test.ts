import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { ModuleLayout } from "../../src/sql/module-types.ts";

import {
  createApprovals,
  sqlTransport,
} from "../../src/blocks/approvals/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const TABLES = `create schema approvals_it;
create table approvals_it.invoices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  status text
);
alter table approvals_it.invoices enable row level security;
create policy invoices_read on approvals_it.invoices for select to authenticated using (true);
create policy invoices_update on approvals_it.invoices for update to authenticated using (true);
grant usage on schema approvals_it to authenticated;
grant select, update on approvals_it.invoices to authenticated;`;

const MODULES = [
  "organizations",
  "outbox",
  "notifications",
  "state-machine",
  "approvals",
];

const layoutFor = (finance: string): ModuleLayout => ({
  subjects: { invoice: { table: "approvals_it.invoices", idType: "uuid" } },
  modules: {
    approvals: {
      options: {
        policies: {
          invoice: {
            send: {
              steps: [
                { approvers: { role: "owner" } },
                { approvers: { users: [finance] } },
              ],
              run: { transition: "sent" },
            },
            void: {
              steps: [{ approvers: { permission: "approvals.manage" } }],
              expiresIn: "P1D",
            },
          },
        },
      },
    },
    "state-machine": {
      options: {
        machines: {
          invoice: {
            table: "approvals_it.invoices",
            column: "status",
            tenant: "organization_id",
            initial: "draft",
            transitions: { draft: ["sent", "void"] },
            requiresApproval: { draft: ["sent"] },
          },
        },
      },
    },
  },
});

describe.skipIf(!live)("approvals", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("walks a request through its steps and runs the gated transition", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.client.query(TABLES);
      const owner = await s.user("owner");
      const requester = await s.user("requester");
      const finance = await s.user("finance");
      const deputy = await s.user("deputy");
      await s.install(MODULES, layoutFor(finance.id));

      const tenant = await s.organization(owner, {
        member: requester,
        admin: finance,
        viewer: deputy,
      });

      const approvals = createApprovals({ transport: sqlTransport(s.sql) });
      await s.service();

      const invoice = (
        await s.rows<{ id: string }>(
          "insert into approvals_it.invoices (organization_id) values ($1) returning id",
          [tenant],
        )
      )[0]!.id;

      const status = () =>
        s.value<string>(
          "(select status from approvals_it.invoices where id = $1)",
          [invoice],
        );

      const hint = (result: Result<unknown>) =>
        result.ok ? "ok" : result.error.hint;

      await s.asRole(requester);
      expect(
        await s.hint(
          "better_supabase.transition('invoice', $1, 'sent', null)",
          [invoice],
        ),
      ).toBe("STATE_APPROVAL_REQUIRED");

      const request = await approvals
        .request({
          organizationId: tenant,
          subjectType: "invoice",
          subjectId: invoice,
          action: "send",
          reason: "Q3",
        })
        .orThrow();

      expect(request).toMatchObject({ status: "pending", step: 0 });
      expect(
        await approvals
          .request({
            organizationId: tenant,
            subjectType: "invoice",
            subjectId: invoice,
            action: "send",
          })
          .then(hint),
      ).toBe("APPROVAL_PENDING");
      expect(
        await approvals
          .request({
            organizationId: tenant,
            subjectType: "invoice",
            subjectId: invoice,
            action: "archive",
          })
          .then(hint),
      ).toBe("APPROVAL_POLICY_UNKNOWN");
      expect(await approvals.approve(request.id).then(hint)).toBe(
        "APPROVAL_FORBIDDEN",
      );

      await s.service();
      expect(
        await s.rows<{ user_id: string }>(
          `select r.user_id::text from better_supabase.notification_recipients r
           join better_supabase.notification_events e on e.id = r.event_id
           where e.type = 'approval.requested' and e.subject_id = $1`,
          [invoice],
        ),
      ).toEqual([{ user_id: owner.id }]);

      await s.asRole(finance);
      expect(await approvals.approve(request.id).then(hint)).toBe(
        "APPROVAL_FORBIDDEN",
      );
      await s.asRole(owner);
      expect((await approvals.get(request.id).orThrow()).canDecide).toBe(true);
      const second = await approvals.approve(request.id, "fine").orThrow();
      expect(second).toMatchObject({ status: "pending", step: 1 });
      expect(await approvals.approve(request.id).then(hint)).toBe(
        "APPROVAL_FORBIDDEN",
      );

      await s.asRole(finance);
      expect(
        (await approvals.list(tenant, { assigned: true }).orThrow()).map(
          (row) => row.id,
        ),
      ).toEqual([request.id]);
      expect(
        await approvals.delegate(request.id, requester.id).then(hint),
      ).toBe("APPROVAL_DELEGATE_INVALID");
      await approvals.delegate(request.id, deputy.id, "on leave").orThrow();

      await s.asRole(deputy);
      const done = await approvals.approve(request.id).orThrow();
      expect(done.status).toBe("approved");
      expect(await status()).toBe("sent");
      expect(
        await approvals.isApproved("invoice", invoice, "send").orThrow(),
      ).toBe(true);

      await s.asRole(requester);
      const detail = await approvals.get(request.id).orThrow();
      expect(detail.canDecide).toBe(false);
      expect(detail.decisions.map((row) => [row.step, row.decision])).toEqual([
        [0, "approved"],
        [1, "delegated"],
        [1, "approved"],
      ]);

      await s.service();

      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where organization_id = $1 and type like 'approval.%' order by created_at, type",
        [tenant],
      );

      expect(new Set(events.map((event) => event.type))).toEqual(
        new Set([
          "approval.requested",
          "approval.delegated",
          "approval.approved",
        ]),
      );
      expect(
        await s.value<number>(
          `(select count(*)::int from better_supabase.notification_recipients r
            join better_supabase.notification_events e on e.id = r.event_id
            where e.type = 'approval.approved' and r.user_id = $1)`,
          [requester.id],
        ),
      ).toBe(1);
    } finally {
      await s.close();
    }
  });

  it("rejects, cancels, expires and reminds", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.client.query(TABLES);
      const owner = await s.user("owner");
      const requester = await s.user("requester");
      await s.install(MODULES, layoutFor(owner.id));
      const tenant = await s.organization(owner, { member: requester });
      const approvals = createApprovals({ transport: sqlTransport(s.sql) });
      await s.service();

      const [a, b, c] = await s.rows<{ id: string }>(
        "insert into approvals_it.invoices (organization_id) select $1 from generate_series(1, 3) returning id",
        [tenant],
      );

      const ask = (subjectId: string) =>
        approvals
          .request({
            organizationId: tenant,
            subjectType: "invoice",
            subjectId,
            action: "void",
          })
          .orThrow();

      await s.asRole(requester);
      const rejected = await ask(a!.id);
      const cancelled = await ask(b!.id);
      const expired = await ask(c!.id);
      expect(expired.expiresAt).toBeDefined();
      expect((await approvals.cancel(cancelled.id).orThrow()).status).toBe(
        "cancelled",
      );
      await s.asRole(owner);
      expect(
        (await approvals.reject(rejected.id, "duplicate").orThrow()).status,
      ).toBe("rejected");
      expect(
        await approvals.approve(rejected.id).then((r) => !r.ok && r.error.hint),
      ).toBe("APPROVAL_CLOSED");

      await s.service();
      await s.client.query(
        "update better_supabase.approval_requests set created_at = now() - interval '2 days', expires_at = now() + interval '1 hour' where id = $1",
        [expired.id],
      );
      expect(await s.value<number>("better_supabase.remind_approvals()")).toBe(
        1,
      );
      expect(await s.value<number>("better_supabase.remind_approvals()")).toBe(
        0,
      );
      await s.client.query(
        "update better_supabase.approval_requests set expires_at = now() - interval '1 minute' where id = $1",
        [expired.id],
      );
      expect(await s.value<number>("better_supabase.expire_approvals()")).toBe(
        1,
      );

      await s.asRole(requester);
      expect(
        (await approvals.list(tenant, { status: null }).orThrow())
          .map((row) => `${row.id}:${row.status}`)
          .toSorted((a, b) => a.localeCompare(b)),
      ).toEqual(
        [
          `${rejected.id}:rejected`,
          `${cancelled.id}:cancelled`,
          `${expired.id}:expired`,
        ].toSorted((a, b) => a.localeCompare(b)),
      );
      expect(await approvals.list(tenant).orThrow()).toEqual([]);
    } finally {
      await s.close();
    }
  });
});
