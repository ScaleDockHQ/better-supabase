import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

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

const layoutFor = (finance: string): BlockSqlLayout => ({
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

describe.skipIf(!live)("approval items", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("decides items with their own permissions, dependencies and created records", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.client.query(TABLES);
      const owner = await s.user("owner");
      const requester = await s.user("requester");
      const finance = await s.user("finance");
      await s.install(MODULES, layoutFor(finance.id));

      const tenant = await s.organization(owner, {
        member: requester,
        admin: finance,
      });

      const approvals = createApprovals({
        transport: sqlTransport(s.sql),
        tenant,
      });

      await s.service();

      const invoice = (
        await s.rows<{ id: string }>(
          "insert into approvals_it.invoices (organization_id) values ($1) returning id",
          [tenant],
        )
      )[0]!.id;

      const hint = (result: Result<unknown>) =>
        result.ok ? "ok" : result.error.hint;

      await s.asRole(requester);

      const request = await approvals
        .request({
          subject: { type: "invoice", id: invoice },
          input: {
            action: "void",
            items: [
              { key: "credit", label: "Credit note" },
              { key: "refund", label: "Refund", dependsOn: ["credit"] },
            ],
          },
        })
        .orThrow();

      expect(request.status).toBe("pending");
      expect(
        await approvals
          .decideItems({
            id: request.id,
            decisions: [{ key: "credit", decision: "approve" }],
          })
          .then(hint),
      ).not.toBe("ok");

      await s.asRole(owner);
      expect(
        await approvals
          .decideItems({
            id: request.id,
            decisions: [{ key: "refund", decision: "approve" }],
          })
          .then(hint),
      ).not.toBe("ok");

      const first = await approvals
        .decideItems({
          id: request.id,
          decisions: [{ key: "credit", decision: "approve" }],
        })
        .orThrow();

      expect(first.status).toBe("pending");
      expect(first.items.map((item) => [item.key, item.status])).toEqual([
        ["credit", "approved"],
        ["refund", "pending"],
      ]);

      const noted = await approvals
        .recordCreated({
          id: request.id,
          key: "credit",
          type: "credit_note",
          recordId: "cn-1",
        })
        .orThrow();

      expect(noted.created).toEqual({ type: "credit_note", id: "cn-1" });

      const done = await approvals
        .decideItems({
          id: request.id,
          decisions: [{ key: "refund", decision: "approve" }],
        })
        .orThrow();

      expect(done.status).toBe("approved");
    } finally {
      await s.close();
    }
  });

  it("settles a pending request for the system and refuses a member", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.client.query(TABLES);
      const owner = await s.user("owner");
      const requester = await s.user("requester");
      await s.install(MODULES, layoutFor(owner.id));
      const tenant = await s.organization(owner, { member: requester });

      const approvals = createApprovals({
        transport: sqlTransport(s.sql),
        tenant,
      });

      await s.service();

      const invoice = (
        await s.rows<{ id: string }>(
          "insert into approvals_it.invoices (organization_id) values ($1) returning id",
          [tenant],
        )
      )[0]!.id;

      await s.asRole(requester);

      const request = await approvals
        .request({
          subject: { type: "invoice", id: invoice },
          input: { action: "void", items: [{ key: "only" }] },
        })
        .orThrow();

      expect(
        (await approvals.settle({ id: request.id, outcome: "rejected" })).ok,
      ).toBe(false);

      await s.service();

      const settled = await approvals
        .settle({ id: request.id, outcome: "rejected", reason: "timed out" })
        .orThrow();

      expect(settled.status).toBe("rejected");
      expect(settled.items.map((item) => item.status)).toEqual(["rejected"]);
    } finally {
      await s.close();
    }
  });
});
