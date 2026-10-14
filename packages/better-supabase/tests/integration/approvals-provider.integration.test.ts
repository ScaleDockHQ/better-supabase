import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { ModuleLayout } from "../../src/sql/module-types.ts";

import {
  createApprovals,
  sqlTransport,
} from "../../src/blocks/approvals/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("approvals with the provider's isApprover", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("lets the user isApprover allows decide, never the requester", async () => {
    const s = await BlockSession.open(pool);
    try {
      const owner = await s.user("owner");
      const requester = await s.user("requester");
      const reviewer = await s.user("reviewer");
      const outsider = await s.user("outsider");
      const schema = `approver_${crypto.randomUUID().slice(0, 8)}`;
      await s.client.query(`
        create schema ${schema};
        create table ${schema}.reviewers (user_id uuid primary key);
        insert into ${schema}.reviewers values ('${reviewer.id}'), ('${requester.id}');
        create function ${schema}.is_approver(kind text, subject text, tenant uuid) returns boolean
          language sql stable security definer set search_path = '' as $$
            select kind = 'refund.approve' and subject is not null
              and exists (select 1 from ${schema}.reviewers r where r.user_id = auth.uid())
          $$;
        create function ${schema}.ids_with(permission text) returns setof uuid
          language sql stable as $$ select null::uuid where false $$;
        create function ${schema}.is_platform(permission text) returns boolean
          language sql stable as $$ select false $$;
        grant usage on schema ${schema} to authenticated;
      `);
      const layout: ModuleLayout = {
        modules: {
          access: { model: "provider" },
          approvals: {
            options: {
              policies: {
                refund: {
                  approve: {
                    steps: [{ approvers: { users: [owner.id] } }],
                    selfApproval: true,
                  },
                },
              },
            },
          },
        },
        accessProvider: {
          name: "test",
          scope: "organization",
          idType: "uuid",
          functions: {
            idsWith: `${schema}.ids_with({permission})`,
            isPlatform: `${schema}.is_platform({permission})`,
            isApprover: `${schema}.is_approver({kind}, {subject}, {tenant})`,
          },
        },
      };
      await s.install(["organizations", "approvals"], layout);
      const tenant = await s.organization(owner, {
        member: requester,
        viewer: reviewer,
      });
      const approvals = createApprovals({ transport: sqlTransport(s.sql) });

      await s.service();
      const request = await approvals
        .request({
          organizationId: tenant,
          subjectType: "refund",
          subjectId: "r-1",
          action: "approve",
        })
        .orThrow();

      const canDecide = async () =>
        (await approvals.get(request.id).orThrow()).canDecide;
      await s.asRole(outsider);
      expect(await canDecide()).toBe(false);
      await s.service();
      await s.client.query(
        "update better_supabase.approval_requests set requested_by = $1 where id = $2",
        [requester.id, request.id],
      );
      await s.asRole(requester);
      expect(await canDecide()).toBe(false);
      await s.asRole(reviewer);
      expect(await canDecide()).toBe(true);
      expect((await approvals.approve(request.id).orThrow()).status).toBe(
        "approved",
      );
    } finally {
      await s.close();
    }
  });
});
