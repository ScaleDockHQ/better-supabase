import { Pool, type PoolClient } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { InvitationSent } from "../../src/orgs/index.ts";
import type { SqlClient } from "../../src/postgres/executor.ts";
import type { KitLayout } from "../../src/sql/kit.ts";

import { EventHub } from "../../src/core/events.ts";
import { createOrgs, sqlTransport } from "../../src/orgs/index.ts";
import { renderKit } from "../../src/sql/kit.ts";

const dbUrl =
  process.env["SUPABASE_DB_URL"] ??
  "postgresql://postgres:postgres@127.0.0.1:55422/postgres";

async function reachable(): Promise<boolean> {
  const pool = new Pool({
    connectionString: dbUrl,
    max: 1,
    connectionTimeoutMillis: 1000,
  });
  try {
    await pool.query("select 1");
    return true;
  } catch {
    return false;
  } finally {
    await pool.end();
  }
}

const live = await reachable();

const USERS = {
  owner: crypto.randomUUID(),
  admin: crypto.randomUUID(),
  member: crypto.randomUUID(),
  outsider: crypto.randomUUID(),
} as const;
type Who = keyof typeof USERS;
const email = (who: Who) => `${who}-${USERS[who]}@example.test`;

const LAYOUT: KitLayout = {
  kits: {
    organizations: { options: { reservedSlugs: ["admin"] } },
    invitations: { options: { prefill: true } },
  },
};

class Session {
  private readonly client: PoolClient;

  constructor(client: PoolClient) {
    this.client = client;
  }

  async as(who: Who | "anon"): Promise<void> {
    const claims =
      who === "anon"
        ? { role: "anon" }
        : { sub: USERS[who], role: "authenticated", email: email(who) };
    await this.client.query(
      "select set_config('request.jwt.claims', $1, true)",
      [JSON.stringify(claims)],
    );
  }

  async value<T>(sql: string, params: unknown[] = []): Promise<T> {
    const { rows } = await this.client.query<{ value: T }>(
      `select ${sql} as value`,
      params,
    );
    return rows[0]!.value;
  }

  /** The hint of the error `sql` raises, rolled back to a savepoint. */
  async hint(sql: string, params: unknown[] = []): Promise<string> {
    await this.client.query("savepoint attempt");
    try {
      await this.client.query(`select ${sql}`, params);
      await this.client.query("set constraints all immediate");
    } catch (error) {
      await this.client.query("rollback to savepoint attempt");
      return (error as { hint?: string }).hint ?? (error as Error).message;
    }
    await this.client.query("release savepoint attempt");
    return "no error";
  }

  role(org: string, who: Who): Promise<string | null> {
    return this.value(
      "(select role from better_supabase.memberships where org_id = $1 and user_id = $2)",
      [org, USERS[who]],
    );
  }
}

describe.skipIf(!live)("organizations and invitations", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("runs the organization lifecycle on the access contract", async () => {
    const client = await pool.connect();
    const s = new Session(client);
    try {
      await client.query("begin");
      for (const who of Object.keys(USERS) as Who[]) {
        await client.query(
          `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at)
           values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now())`,
          [USERS[who], email(who)],
        );
      }
      for (const file of renderKit(["organizations", "invitations"], LAYOUT))
        await client.query(file.contents);

      await s.as("owner");
      const slug = `acme-${USERS.owner.slice(0, 8)}`;
      const org = await s.value<string>(
        "better_supabase.create_organization($1)",
        [{ name: "Acme", slug }],
      );
      expect(await s.role(org, "owner")).toBe("owner");
      expect(
        await s.hint("better_supabase.create_organization($1)", [
          { name: "x", slug: "admin" },
        ]),
      ).toBe("ORG_SLUG_RESERVED");
      expect(
        await s.hint("better_supabase.create_organization($1)", [
          { name: "x", slug: "Bad Slug" },
        ]),
      ).toBe("ORG_SLUG_INVALID");
      expect(
        await s.hint("better_supabase.create_organization($1)", [
          { name: "x", slug },
        ]),
      ).toBe("ORG_SLUG_TAKEN");

      const invite = async (who: Who, role: string) =>
        s.value<{ token: string; id: string }>(
          "better_supabase.invite_member($1, $2, $3)",
          [org, email(who), role],
        );
      const memberInvite = await invite("member", "member");
      await s.as("anon");
      const preview = await s.value<Record<string, unknown>>(
        "better_supabase.invitation_preview($1)",
        [memberInvite.token],
      );
      expect(preview).toMatchObject({
        status: "pending",
        role: "member",
        organization: { id: org, name: "Acme" },
      });

      await s.as("member");
      expect(
        await s.value("better_supabase.accept_invitation($1)", [
          memberInvite.token,
        ]),
      ).toBe(org);
      expect(
        await s.hint("better_supabase.accept_invitation($1)", [
          memberInvite.token,
        ]),
      ).toBe("INVITATION_INVALID");
      expect(
        await s.hint("better_supabase.update_member_role($1, $2, 'member')", [
          org,
          USERS.owner,
        ]),
      ).toBe("ORG_FORBIDDEN");

      await s.as("owner");
      expect(
        await s.hint("better_supabase.invite_member($1, $2, 'member')", [
          org,
          email("member"),
        ]),
      ).toBe("INVITATION_ALREADY_MEMBER");
      const adminInvite = await invite("admin", "admin");
      await s.as("admin");
      await s.value("better_supabase.accept_invitation($1)", [
        adminInvite.token,
      ]);
      expect(
        await s.hint("better_supabase.update_member_role($1, $2, 'owner')", [
          org,
          USERS.member,
        ]),
      ).toBe("ORG_ROLE_CEILING");
      expect(
        await s.hint("better_supabase.update_member_role($1, $2, 'member')", [
          org,
          USERS.admin,
        ]),
      ).toBe("ORG_SELF_ROLE");
      expect(
        await s.value("better_supabase.update_member_role($1, $2, 'viewer')", [
          org,
          USERS.member,
        ]),
      ).toBe(true);
      expect(await s.role(org, "member")).toBe("viewer");

      const outsiderInvite = await invite("outsider", "member");
      await s.as("owner");
      await s.value("better_supabase.update_member_role($1, $2, 'member')", [
        org,
        USERS.admin,
      ]);
      await s.as("outsider");
      expect(
        await s.hint("better_supabase.accept_invitation($1)", [
          outsiderInvite.token,
        ]),
      ).toBe("INVITATION_INVITER_REVOKED");
      expect(
        await s.value("better_supabase.decline_invitation($1)", [
          outsiderInvite.token,
        ]),
      ).toBe(true);
      expect(
        await s.value("better_supabase.invitation_preview($1) ->> 'status'", [
          outsiderInvite.token,
        ]),
      ).toBe("declined");

      await s.as("owner");
      expect(
        await s.hint("better_supabase.leave_organization($1)", [org]),
      ).toBe("ORG_OWNER_REQUIRED");
      await s.value("better_supabase.transfer_ownership($1, $2)", [
        org,
        USERS.admin,
      ]);
      expect(await s.role(org, "admin")).toBe("owner");
      expect(await s.role(org, "owner")).toBe("admin");
      await client.query("set constraints all immediate");

      await s.as("admin");
      expect(await s.value("better_supabase.mark_used($1)", [org])).toBe(true);
      expect(
        await s.value("better_supabase.delete_organization($1)", [org]),
      ).toBe(true);
      expect(await s.role(org, "member")).toBeNull();
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("fails closed on stale tenant claims, disabled organizations and non-owner transfers", async () => {
    const client = await pool.connect();
    const s = new Session(client);
    try {
      await client.query("begin");
      for (const who of ["owner", "admin", "member"] as const) {
        await client.query(
          `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at)
           values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now())`,
          [USERS[who], email(who)],
        );
      }
      const layout: KitLayout = {
        kits: {
          access: {
            activeTenant: "claim",
            roles: {
              owner: ["*"],
              admin: ["ownership.transfer", "members.*"],
              member: [],
            },
          },
        },
      };
      for (const file of renderKit(["organizations"], layout))
        await client.query(file.contents);

      await s.as("owner");
      const org = await s.value<string>(
        "better_supabase.create_organization($1)",
        [{ name: "Stale", slug: `stale-${USERS.owner.slice(0, 8)}` }],
      );
      await client.query(
        `insert into better_supabase.memberships (org_id, user_id, role)
         values ($1, $2, 'admin'), ($1, $3, 'member')`,
        [org, USERS.admin, USERS.member],
      );

      await s.as("member");
      await s.value("better_supabase.switch_organization($1)", [org]);
      expect(
        await s.value(
          "(select raw_app_meta_data ->> 'tenant_id' from auth.users where id = $1)",
          [USERS.member],
        ),
      ).toBe(org);
      await client.query("select set_config('request.jwt.claims', $1, true)", [
        JSON.stringify({
          sub: USERS.member,
          role: "authenticated",
          tenant_id: org,
        }),
      ]);
      expect(await s.value("better_supabase.current_tenant_id()")).toBe(org);

      await s.as("owner");
      await s.value("better_supabase.remove_member($1, $2)", [
        org,
        USERS.member,
      ]);
      expect(
        await s.value(
          "(select raw_app_meta_data ->> 'tenant_id' from auth.users where id = $1)",
          [USERS.member],
        ),
      ).toBeNull();
      await client.query("select set_config('request.jwt.claims', $1, true)", [
        JSON.stringify({
          sub: USERS.member,
          role: "authenticated",
          tenant_id: org,
        }),
      ]);
      expect(await s.value("better_supabase.current_tenant_id()")).toBeNull();

      await s.as("admin");
      expect(
        await s.hint("better_supabase.transfer_ownership($1, $2)", [
          org,
          USERS.admin,
        ]),
      ).toBe("ORG_FORBIDDEN");

      await client.query(
        "update better_supabase.organizations set disabled_at = now() where id = $1",
        [org],
      );
      await s.as("owner");
      expect(
        await s.value("better_supabase.has_org_role($1, '{owner}')", [org]),
      ).toBe(false);
      expect(
        await s.value(
          "better_supabase.can('organization', $1, 'organization.read')",
          [org],
        ),
      ).toBe(false);
      expect(
        await s.value("array(select better_supabase.member_org_ids())::text[]"),
      ).toEqual([]);
      await client.query("set local role authenticated");
      expect(
        await s.hint("better_supabase.tenant_disabled($1)", [org]),
      ).toMatch(/permission denied/);
      await client.query("reset role");
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("stores catalog role ids and resolves role keys", async () => {
    const client = await pool.connect();
    const s = new Session(client);
    const schema = `bs_catalog_${USERS.owner.slice(0, 8)}`;
    const kit = { schema };
    try {
      await client.query("begin");
      for (const who of ["owner", "member"] as const) {
        await client.query(
          `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at)
           values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now())`,
          [USERS[who], email(who)],
        );
      }
      const layout: KitLayout = {
        kits: {
          access: { ...kit, model: "catalog" },
          tenant: kit,
          organizations: kit,
          invitations: kit,
        },
      };
      for (const file of renderKit(["organizations", "invitations"], layout))
        await client.query(file.contents);
      await client.query(`
        insert into ${schema}.roles (id, key) values
          ('00000000-0000-4000-8000-00000000f001', 'owner'),
          ('00000000-0000-4000-8000-00000000f002', 'member');
        insert into ${schema}.permissions (id, key) values
          ('00000000-0000-4000-8000-00000000f101', 'members.invite');
        insert into ${schema}.role_permissions (role_id, permission_id) values
          ('00000000-0000-4000-8000-00000000f001', '00000000-0000-4000-8000-00000000f101');
      `);

      await s.as("owner");
      const org = await s.value<string>(`${schema}.create_organization($1)`, [
        { name: "Catalog", slug: `catalog-${USERS.owner.slice(0, 8)}` },
      ]);
      const invite = await s.value<{ token: string; role: string }>(
        `${schema}.invite_member($1, $2, 'member')`,
        [org, email("member")],
      );
      expect(invite.role).toBe("00000000-0000-4000-8000-00000000f002");
      await s.as("member");
      await s.value(`${schema}.accept_invitation($1)`, [invite.token]);
      expect(
        await s.value(
          `(select role::text from ${schema}.memberships where org_id = $1 and user_id = $2)`,
          [org, USERS.member],
        ),
      ).toBe("00000000-0000-4000-8000-00000000f002");

      // A role still held by a member can't be deleted, and the
      // organization's rows go with it.
      await s.as("owner");
      await client.query("savepoint role_delete");
      await expect(
        client.query(`delete from ${schema}.roles where key = 'member'`),
      ).rejects.toMatchObject({ code: "23503" });
      await client.query("rollback to savepoint role_delete");
      await s.value(`${schema}.invite_member($1, $2, 'member')`, [
        org,
        "later@example.test",
      ]);
      await client.query(`delete from ${schema}.organizations where id = $1`, [
        org,
      ]);
      expect(
        await s.value(
          `(select (select count(*) from ${schema}.memberships where org_id = $1) + (select count(*) from ${schema}.invitations where org_id = $1))::int`,
          [org],
        ),
      ).toBe(0);
      await client.query("select set_config('request.jwt.claims', $1, true)", [
        JSON.stringify({ role: "service_role" }),
      ]);
      expect(
        await s.hint(`${schema}.invite_member($1, $2, 'member')`, [
          org,
          "late@example.test",
        ]),
      ).toBe("INVITATION_INVALID");
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("caps platform and tenant invitations at the inviter's authority, then and at accept", async () => {
    const client = await pool.connect();
    const s = new Session(client);
    const schema = `bs_platform_${USERS.owner.slice(0, 8)}`;
    const kit = { schema };
    const role = (n: number) => `00000000-0000-4000-8000-00000000f00${n}`;
    const permission = (n: number) => `00000000-0000-4000-8000-00000000f10${n}`;
    try {
      await client.query("begin");
      for (const who of ["owner", "outsider"] as const) {
        await client.query(
          `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at)
           values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now())`,
          [USERS[who], email(who)],
        );
      }
      const layout: KitLayout = {
        kits: {
          access: { ...kit, model: "catalog" },
          tenant: kit,
          organizations: kit,
          invitations: kit,
        },
      };
      for (const file of renderKit(["organizations", "invitations"], layout))
        await client.query(file.contents);
      await client.query(`
        insert into ${schema}.roles (id, key, scope) values
          ('${role(1)}', 'owner', 'tenant'), ('${role(2)}', 'member', 'tenant'),
          ('${role(3)}', 'lead', 'tenant'), ('${role(4)}', 'inviter', 'platform'),
          ('${role(5)}', 'support', 'platform');
        insert into ${schema}.permissions (id, key) values
          ('${permission(1)}', 'members.invite'), ('${permission(2)}', 'reports.view'),
          ('${permission(3)}', 'platform.invite'), ('${permission(4)}', 'support.view');
        insert into ${schema}.role_permissions (role_id, permission_id) values
          ('${role(1)}', '${permission(1)}'), ('${role(1)}', '${permission(2)}'),
          ('${role(3)}', '${permission(1)}'), ('${role(3)}', '${permission(2)}'),
          ('${role(4)}', '${permission(3)}'),
          ('${role(5)}', '${permission(3)}'), ('${role(5)}', '${permission(4)}');
        insert into ${schema}.platform_roles (user_id, role_id) values ('${USERS.owner}', '${role(4)}');
      `);

      await s.as("owner");
      const org = await s.value<string>(`${schema}.create_organization($1)`, [
        { name: "Platform", slug: `platform-${USERS.owner.slice(0, 8)}` },
      ]);
      expect(
        await s.hint(`${schema}.invite_member($1, $2, 'member', '90 days')`, [
          org,
          email("outsider"),
        ]),
      ).toBe("INVITATION_VALIDITY");
      const lead = await s.value<{ token: string }>(
        `${schema}.invite_member($1, $2, 'lead')`,
        [org, email("outsider")],
      );
      expect(
        await s.hint(`${schema}.invite_member(null, $1, 'support')`, [
          email("outsider"),
        ]),
      ).toBe("INVITATION_ROLE_FORBIDDEN");
      expect(
        await s.hint(`${schema}.invite_member(null, $1, 'member')`, [
          email("outsider"),
        ]),
      ).toBe("INVITATION_ROLE_UNKNOWN");
      const platform = await s.value<{ token: string; tenant: null }>(
        `${schema}.invite_member(null, $1, 'inviter')`,
        [email("outsider")],
      );
      expect(platform.tenant).toBeNull();
      expect(
        await s.value(
          `(select count(*)::int from ${schema}.platform_invitations)`,
        ),
      ).toBe(1);

      await client.query("select set_config('request.jwt.claims', $1, true)", [
        JSON.stringify({
          sub: USERS.owner,
          role: "authenticated",
          act: { sub: USERS.outsider },
        }),
      ]);
      expect(
        await s.value("better_supabase.is_platform('platform.invite')"),
      ).toBe(false);

      await client.query(
        `delete from ${schema}.role_permissions where role_id = $1 and permission_id = $2`,
        [role(1), permission(2)],
      );
      await client.query(`delete from ${schema}.platform_roles`);
      await s.as("outsider");
      expect(
        await s.hint(`${schema}.accept_invitation($1)`, [lead.token]),
      ).toBe("INVITATION_INVITER_REVOKED");
      expect(
        await s.hint(`${schema}.accept_invitation($1)`, [platform.token]),
      ).toBe("INVITATION_INVITER_REVOKED");

      await client.query(
        `insert into ${schema}.platform_roles (user_id, role_id) values ($1, $2)`,
        [USERS.owner, role(4)],
      );
      expect(
        await s.value(`${schema}.accept_invitation($1)`, [platform.token]),
      ).toBeNull();
      expect(
        await s.value(
          `(select role_id::text from ${schema}.platform_roles where user_id = $1)`,
          [USERS.outsider],
        ),
      ).toBe(role(4));
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("drives the modules through createOrgs and sqlTransport", async () => {
    const client = await pool.connect();
    const s = new Session(client);
    // Each call runs in a savepoint, so a refused call leaves the test transaction usable.
    const sql = {
      async queryRaw(text: string, params: readonly unknown[] = []) {
        await client.query("savepoint call");
        try {
          const { rows } = await client.query(text, [...params]);
          await client.query("release savepoint call");
          return rows;
        } catch (error) {
          await client.query("rollback to savepoint call");
          throw error;
        }
      },
    } as unknown as SqlClient;
    try {
      await client.query("begin");
      for (const who of ["owner", "member"] as const) {
        await client.query(
          `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at)
           values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now())`,
          [USERS[who], email(who)],
        );
      }
      for (const file of renderKit(["organizations", "invitations"], LAYOUT))
        await client.query(file.contents);

      const events = new EventHub();
      const seen: string[] = [];
      events.on("kit", (event) => seen.push(event.type));
      const mail: InvitationSent[] = [];
      const orgs = createOrgs({
        transport: sqlTransport(sql),
        events,
        onInvite: (sent) => {
          mail.push(sent);
        },
      });

      await s.as("owner");
      const slug = `api-${USERS.owner.slice(0, 8)}`;
      const created = await orgs.create({ name: "Api", slug }).orThrow();
      expect((await orgs.slugProblem(slug)).data).toBe("taken");
      expect((await orgs.slugProblem(slug, created.id)).data).toBeUndefined();
      const taken = await orgs.create({ name: "Again", slug });
      expect(taken.error).toMatchObject({ hint: "ORG_SLUG_TAKEN" });

      const switched = await orgs.switch(created.id).orThrow();
      expect(switched).toEqual({ organizationId: created.id, refresh: false });

      const sent = await orgs
        .invite({
          organizationId: created.id,
          email: email("member"),
          role: "member",
          prefill: { name: "Member" },
        })
        .orThrow();
      expect(mail).toEqual([sent]);
      expect(sent.invitation.prefill).toEqual({ name: "Member" });

      await s.as("anon");
      const preview = await orgs.previewInvitation(sent.token).orThrow();
      expect(preview).toMatchObject({
        status: "pending",
        organizationId: created.id,
        organization: { name: "Api" },
      });

      await s.as("member");
      const forbidden = await orgs.update(created.id, { name: "Mine" });
      expect(forbidden.error).toMatchObject({ hint: "ORG_FORBIDDEN" });
      expect(await orgs.acceptInvitation(sent.token).orThrow()).toEqual({
        organizationId: created.id,
      });
      expect(await s.role(created.id, "member")).toBe("member");
      await orgs.leave(created.id).orThrow();
      expect(await s.role(created.id, "member")).toBeNull();

      await s.as("owner");
      await orgs.update(created.id, { name: "Api 2" }).orThrow();
      expect(await orgs.delete(created.id).orThrow()).toBe(true);
      expect(seen).toEqual([
        "org.created",
        "org.switched",
        "invitation.created",
        "org.member_added",
        "org.member_left",
        "org.updated",
        "org.deleted",
      ]);
    } finally {
      await client.query("rollback");
      client.release();
    }
  });
});
