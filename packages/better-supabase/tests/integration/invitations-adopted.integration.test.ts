import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { ModuleLayout } from "../../src/sql/registry.ts";

import {
  BlockSession,
  dbUrl,
  reachable,
  type TestUser,
} from "./block-session.ts";

const live = await reachable();

/**
 * A PermDock-shaped schema: memberships with text roles, declared roles
 * (`owner`, `admin`, `member`) and tenant custom roles, and the helpers the
 * permdock access model calls.
 */
async function permdockSchema(
  s: BlockSession,
  organization: string,
  members: Readonly<Record<string, TestUser>>,
): Promise<string> {
  const schema = `bs_pd_${crypto.randomUUID().slice(0, 8)}`;
  await s.client.query(`
    create schema ${schema};
    create table ${schema}.team_members (
      organization_id uuid not null,
      user_id uuid not null references auth.users (id) on delete cascade,
      role text not null,
      primary key (organization_id, user_id)
    );
    create table ${schema}.custom_roles (organization_id uuid, key text);
    insert into ${schema}.custom_roles values ('${organization}', 'auditor');
    create function ${schema}.permitted_organization_ids(permission text) returns setof uuid
      language sql stable as $$
        select m.organization_id from ${schema}.team_members m
        where m.user_id = auth.uid() and m.role in ('owner', 'admin') $$;
    create function ${schema}.permdock_has(permission text) returns boolean
      language sql stable as $$ select false $$;
    create function ${schema}.permdock_can_assign(p_role text, p_scope_id text) returns boolean
      language sql stable as $$ select p_role <> 'owner' $$;
    -- Knows only the declared roles, as PermDock's helper does.
    create function ${schema}.permdock_can_assign_for(p_user uuid, p_role text, p_scope_id text) returns boolean
      language sql stable as $$ select p_role in ('admin', 'member') $$;
    create function ${schema}.permdock_can_assign_any_for(p_user uuid, p_role text, p_tenant uuid, p_scope text, p_scope_id text) returns boolean
      language sql stable as $$
        select p_scope = 'organization' and p_scope_id = p_tenant::text
          and (p_role in ('admin', 'member')
            or exists (select 1 from ${schema}.custom_roles r where r.organization_id = p_tenant and r.key = p_role)) $$;
  `);
  for (const [role, user] of Object.entries(members))
    await s.client.query(
      `insert into ${schema}.team_members values ($1, $2, $3)`,
      [organization, user.id, role],
    );
  return schema;
}

function permdockLayout(
  schema: string,
  forUser: { canAssign: boolean; canAssignAny: boolean },
): ModuleLayout {
  return {
    accessPermdock: {
      schema,
      scope: "organization",
      idType: "uuid",
      forUser: { has: false, permitted: false, ...forUser },
    },
    modules: {
      access: {
        model: "permdock",
        functions: {
          canAssign: `${schema}.permdock_can_assign({role}, {tenant}::text)`,
        },
      },
      tenant: {
        schema,
        mode: "adopt",
        tables: { memberships: `${schema}.team_members` },
        columns: { memberships: { updatedAt: null, lastUsedAt: null } },
      },
      invitations: { schema },
    },
  };
}

describe.skipIf(!live)("invitations in adopted tables", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("accepts an invitation to a tenant custom role through permdock_can_assign_any_for", async () => {
    const s = await BlockSession.open(pool);
    try {
      const owner = await s.user("owner");
      const invitee = await s.user("invitee");
      const late = await s.user("late");
      const organization = crypto.randomUUID();
      const schema = await permdockSchema(s, organization, { owner });

      await s.install(
        ["invitations"],
        permdockLayout(schema, { canAssign: true, canAssignAny: false }),
      );
      await s.as(owner);
      const refused = await s.value<{ token: string }>(
        `${schema}.invite_member($1, $2, 'auditor')`,
        [organization, late.email],
      );
      await s.as(late);
      expect(
        await s.hint(`${schema}.accept_invitation($1)`, [refused.token]),
      ).toBe("INVITATION_INVITER_REVOKED");

      await s.install(
        ["invitations"],
        permdockLayout(schema, { canAssign: true, canAssignAny: true }),
      );
      await s.as(owner);
      const invite = await s.value<{ token: string }>(
        `${schema}.invite_member($1, $2, 'auditor')`,
        [organization, invitee.email],
      );
      await s.as(invitee);
      expect(
        await s.value(`${schema}.accept_invitation($1)`, [invite.token]),
      ).toBe(organization);
      expect(
        await s.value(
          `(select role from ${schema}.team_members where organization_id = $1 and user_id = $2)`,
          [organization, invitee.id],
        ),
      ).toBe("auditor");
      await s.as(late);
      expect(
        await s.value(`${schema}.accept_invitation($1)`, [refused.token]),
      ).toBe(organization);
    } finally {
      await s.close();
    }
  });

  it("checks the inviter with sql.modules.access.functions.canAssignFor", async () => {
    const s = await BlockSession.open(pool);
    try {
      const owner = await s.user("owner");
      const invitee = await s.user("invitee");
      const organization = crypto.randomUUID();
      const schema = await permdockSchema(s, organization, { owner });
      const layout = permdockLayout(schema, {
        canAssign: false,
        canAssignAny: false,
      });
      await s.install(["invitations"], {
        ...layout,
        modules: {
          ...layout.modules,
          access: {
            model: "permdock",
            functions: {
              canAssign: `${schema}.permdock_can_assign({role}, {tenant}::text)`,
              canAssignFor: `{role} <> 'auditor' and {user} is not null and {tenant} is not null`,
            },
          },
        },
      });
      await s.as(owner);
      const invite = await s.value<{ token: string }>(
        `${schema}.invite_member($1, $2, 'auditor')`,
        [organization, invitee.email],
      );
      await s.as(invitee);
      expect(
        await s.hint(`${schema}.accept_invitation($1)`, [invite.token]),
      ).toBe("INVITATION_INVITER_REVOKED");
    } finally {
      await s.close();
    }
  });
});
