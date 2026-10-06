import type { PostgresApi } from "@supabase/server/middleware/postgres";

import { pipeline } from "@supabase/middleware";
import { withPostgresAdminClient } from "@supabase/server/middleware/postgres-admin";
import { Pool } from "pg";
import * as v from "valibot";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { SqlClient } from "../../src/postgres/executor.ts";
import type { AnyModels } from "../../src/schema/types.ts";

import { purgeAuditLog } from "../../src/blocks/audit/index.ts";
import {
  ENTITLEMENTS_UPDATED,
  entitlementMembers,
} from "../../src/blocks/entitlements/index.ts";
import {
  createIdempotency,
  createInbox,
  createJobs,
  createRateLimit,
  sqlQueueBackend,
} from "../../src/blocks/jobs/index.ts";
import { signWebhook } from "../../src/blocks/webhooks/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { mapDbError, type RawDbError } from "../../src/core/errors.ts";
import { defineReadSet } from "../../src/core/read-set.ts";
import { actor } from "../../src/plugins/actor/index.ts";
import { createPostgres } from "../../src/postgres/pool.ts";
import { defineSchema } from "../../src/schema/define.ts";
import { withBlock } from "../../src/server/entries/block.ts";
import { auditRegistrations } from "../../src/sql/audit-registrations.ts";
import { compileReadSet } from "../../src/sql/read-sets.ts";
import {
  moduleBody,
  renderModules,
  SQL_MODULES,
} from "../../src/sql/registry.ts";
import { asUser } from "../../src/testing/as-user.ts";
import { testQueueBackend } from "../../src/testing/conformance.ts";
import { signLocalJwt } from "../../src/testing/local-key.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { deleteAudit } from "./audit-cleanup.ts";
import { FIXTURE_TENANT_SQL } from "./fixture-tenant.ts";

const url = process.env["SUPABASE_URL"] ?? "http://127.0.0.1:55421";
const dbUrl =
  process.env["SUPABASE_DB_URL"] ??
  "postgresql://postgres:postgres@127.0.0.1:55422/postgres";
const publishableKey =
  process.env["SUPABASE_PUBLISHABLE_KEY"] ??
  "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH";

const ACME = "00000000-0000-4000-8000-000000000001";
const RUN = String(Date.now());

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

async function installSchemaModules(pool: Pool): Promise<void> {
  const client = await pool.connect();
  try {
    await client.query("begin");
    const names = Object.values(SQL_MODULES)
      .filter((module) => module.target === "schema")
      .map((module) => module.name);
    for (const file of renderModules(names))
      if (file.kind !== "test") await client.query(file.contents);
    await client.query(FIXTURE_TENANT_SQL);
    await client.query("commit");
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}

interface PlainRow {
  id: string;
  name: string | null;
  createdBy: string | null;
  updatedBy: string | null;
  impersonatedBy: string | null;
}

type PlainModels = {
  plain: {
    Row: PlainRow;
    Insert: Partial<PlainRow>;
    Update: Partial<PlainRow>;
    Relations: Record<never, never>;
    PrimaryKey: "id";
    UniqueKeys: Record<never, never>;
    Flags: { actor: true };
  };
};

describe.skipIf(!live)("SQL modules against the local database", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 4 });
  const postgres = createPostgres({ connectionString: dbUrl, max: 4 });
  const table = `public.bs_block_${RUN}`;

  beforeAll(async () => {
    await installSchemaModules(pool);
    await pool.query(`
      create table ${table} (
        id uuid primary key default gen_random_uuid(),
        organization_id uuid,
        slug text,
        name text,
        created_by uuid,
        updated_by uuid,
        impersonated_by uuid,
        updated_at timestamptz
      );
      grant all on ${table} to authenticated;
      select better_supabase.track_updated_at('${table}');
      select better_supabase.track_actor('${table}', impersonated_by => 'impersonated_by');
      select better_supabase.track_slug('${table}');
      select better_supabase.audit('${table}', ignore => '{updated_at}');
    `);
  });
  afterAll(async () => {
    await pool.query(`drop table if exists ${table}`);
    await pool.query(
      `delete from better_supabase.audited_tables where target::text = $1`,
      [table.replace("public.", "")],
    );
    await pool.query(
      `select pgmq.drop_queue(queue_name) from pgmq.list_queues() where queue_name like $1`,
      [`block_${RUN}%`],
    );
    await pool.query(
      `delete from better_supabase.webhook_inbox where source = $1`,
      [`module-${RUN}`],
    );
    await pool.query(
      `delete from better_supabase.idempotency_keys where scope = $1`,
      [RUN],
    );
    await pool.end();
    await postgres.end();
  });

  it("is idempotent", async () => {
    await installSchemaModules(pool);
  });

  it("passes plpgsql_check (supabase db lint) without the app's hook functions", async () => {
    const hooks = Object.values(SQL_MODULES).flatMap(
      (module) => module.names?.hooks ?? [],
    );
    const client = await pool.connect();
    try {
      await client.query("begin");
      await client.query("create extension if not exists plpgsql_check");
      const existing = await client.query<{ sql: string }>(
        `select format('drop function %s', p.oid::regprocedure) as sql
         from pg_proc p
         where p.pronamespace = 'public'::regnamespace and p.proname = any($1)`,
        [hooks],
      );
      for (const row of existing.rows) await client.query(row.sql);
      const { rows } = await client.query<{
        fn: string;
        level: string;
        message: string;
      }>(`
        select p.oid::regprocedure::text as fn, r.level, r.message
        from pg_proc p,
        lateral plpgsql_check_function_tb(p.oid, fatal_errors => false, extra_warnings => true) r
        where p.pronamespace = 'better_supabase'::regnamespace
          and p.prolang = (select oid from pg_language where lanname = 'plpgsql')
          and p.prorettype not in ('trigger'::regtype, 'event_trigger'::regtype)`);
      expect(
        rows.filter(
          (row) =>
            row.level === "error" &&
            hooks.some((hook) => row.message.includes(`.${hook}(`)),
        ),
      ).toEqual([]);
      expect(
        rows.filter((row) =>
          /^better_supabase\.(audit_event|purge_audit_log)\(/.test(row.fn),
        ),
      ).toEqual([]);
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("warns about equivalent triggers and replaces them on request", async () => {
    const name = `public.bs_dup_${RUN}`;
    const notices: string[] = [];
    const client = await pool.connect();
    client.on("notice", (notice) => notices.push(notice.message ?? ""));
    try {
      await client.query(`
        create table ${name} (id int primary key, updated_at timestamptz);
        create function public.touch_${RUN}() returns trigger language plpgsql as $$
        begin new.updated_at := now(); return new; end $$;
        create trigger touch_row before update on ${name}
          for each row execute function public.touch_${RUN}();
      `);
      await client.query(`select better_supabase.track_updated_at('${name}')`);
      expect(notices.join("\n")).toContain("touch_row");
      const triggers = async () =>
        (
          await client.query<{ tgname: string }>(
            `select tgname from pg_trigger where tgrelid = $1::regclass and not tgisinternal order by 1`,
            [name],
          )
        ).rows.map((row) => row.tgname);
      expect(await triggers()).toEqual(["bs_updated_at", "touch_row"]);
      await client.query(
        `select better_supabase.track_updated_at('${name}', replace_trigger => true)`,
      );
      expect(await triggers()).toEqual(["bs_updated_at"]);
    } finally {
      await client.query(`drop table if exists ${name}`);
      await client.query(`drop function if exists public.touch_${RUN}()`);
      client.release();
    }
  });

  it("grants tables in expose to the Data API roles", async () => {
    const name = `bs_grants_${RUN}`;
    const read = async (): Promise<Response> => {
      for (let attempt = 0; ; attempt++) {
        const response = await fetch(`${url}/rest/v1/${name}?select=id`, {
          headers: { apikey: publishableKey },
        });
        const body = (await response.clone().json()) as { code?: string };
        if (body.code !== "PGRST205" || attempt === 20) return response;
        await new Promise((done) => {
          setTimeout(done, 250);
        });
      }
    };
    try {
      await pool.query(`
        create table public.${name} (id int primary key);
        alter table public.${name} enable row level security;
        create policy "read" on public.${name} for select using (true);
        revoke all on public.${name} from anon, authenticated;
        notify pgrst, 'reload schema';
      `);
      const denied = await read();
      const raw = (await denied.json()) as RawDbError;
      expect(raw.code).toBe("42501");
      expect(mapDbError(raw)).toMatchObject({
        kind: "forbidden",
        hint: expect.stringContaining("expose"),
      });

      const [file] = renderModules(["grants"], {
        grants: [{ table: name, role: "anon", privileges: ["select"] }],
      });
      await pool.query(file!.contents);
      const allowed = await read();
      expect(allowed.status).toBe(200);
      expect(await allowed.json()).toEqual([]);
    } finally {
      await pool.query(`drop table if exists public.${name}`);
    }
  });

  it("stamps updated_at and actors, enforces slugs and audits changes", async () => {
    const user = crypto.randomUUID();
    const claims = { sub: user, role: "authenticated" };
    const as = postgres.asUser(claims);
    const [row] = await as.queryRaw<{
      id: string;
      created_by: string;
      updated_by: string;
    }>(
      `insert into ${table} (organization_id, slug, name) values ($1, 'acme', 'Acme') returning *`,
      [ACME],
    );
    expect(row).toMatchObject({ created_by: user, updated_by: user });

    const [updated] = await as.queryRaw<{ updated_at: Date | null }>(
      `update ${table} set name = 'Acme 2' where id = $1 returning updated_at`,
      [row!.id],
    );
    expect(updated!.updated_at).toBeInstanceOf(Date);

    await expect(
      as.queryRaw(`insert into ${table} (slug) values ('admin')`),
    ).rejects.toMatchObject({ code: "23514", hint: "SLUG_RESERVED" });
    await expect(
      as.queryRaw(`insert into ${table} (slug) values ('Bad Slug')`),
    ).rejects.toMatchObject({ hint: "SLUG_INVALID" });

    const log = await pool.query<{
      op: string;
      changed: string[] | null;
      actor_id: string;
      organization_id: string;
    }>(
      `select op, changed, actor_id, organization_id from better_supabase.audit_events
       where table_name = $1 and record_id = $2 order by id`,
      [table, row!.id],
    );
    expect(log.rows).toEqual([
      { op: "insert", changed: null, actor_id: user, organization_id: ACME },
      {
        op: "update",
        changed: ["name"],
        actor_id: user,
        organization_id: ACME,
      },
    ]);
    await expect(
      as.queryRaw("select * from better_supabase.audit_events limit 1"),
    ).rejects.toMatchObject({ code: "42501" });
  });

  it("stamps impersonated_by from the act claim", async () => {
    const user = crypto.randomUUID();
    const admin = crypto.randomUUID();
    const acting = postgres.asUser({
      sub: user,
      role: "authenticated",
      act: { sub: admin, reason: "support" },
    });
    const [row] = await acting.queryRaw<{
      id: string;
      created_by: string;
      impersonated_by: string | null;
    }>(`insert into ${table} (name) values ('Impersonated') returning *`);
    expect(row).toMatchObject({ created_by: user, impersonated_by: admin });

    const [own] = await postgres
      .asUser({ sub: user, role: "authenticated" })
      .queryRaw<{ impersonated_by: string | null }>(
        `update ${table} set name = 'Own' where id = $1 returning impersonated_by`,
        [row!.id],
      );
    expect(own!.impersonated_by).toBe(admin);
    const log = await pool.query(
      `select impersonated_by, impersonation_reason from better_supabase.audit_events
       where table_name = $1 and record_id = $2 order by id`,
      [table, row!.id],
    );
    expect(log.rows).toEqual([
      { impersonated_by: admin, impersonation_reason: "support" },
      { impersonated_by: null, impersonation_reason: null },
    ]);
  });

  it("actor() stamps the same actor columns as track_actor", async () => {
    const plain = `bs_block_plain_${RUN}`;
    const uuid = { type: "uuid", nullable: true, hasDefault: false } as const;
    const stamped = defineSupabase(
      defineSchema<PlainModels>({
        version: 1,
        casing: "camel",
        enums: {},
        functions: {},
        tables: {
          plain: {
            key: "plain",
            name: plain,
            schema: "public",
            kind: "table",
            columns: {
              id: { db: "id", type: "uuid", nullable: false, hasDefault: true },
              name: {
                db: "name",
                type: "text",
                nullable: true,
                hasDefault: false,
              },
              createdBy: { db: "created_by", ...uuid },
              updatedBy: { db: "updated_by", ...uuid },
              impersonatedBy: { db: "impersonated_by", ...uuid },
            },
            primaryKey: ["id"],
            uniqueKeys: {},
            relations: {},
            flags: {
              actor: {
                createdBy: "createdBy",
                updatedBy: "updatedBy",
                impersonatedBy: "impersonatedBy",
              },
            },
          },
        },
      }),
    ).use(actor());
    const user = crypto.randomUUID();
    const admin = crypto.randomUUID();
    const columns = "created_by, updated_by, impersonated_by";
    await pool.query(
      `create table public.${plain} (id uuid primary key default gen_random_uuid(),
         name text, created_by uuid, updated_by uuid, impersonated_by uuid);
       grant all on public.${plain} to authenticated`,
    );
    try {
      const claims = { sub: user, role: "authenticated" };
      const act = { ...claims, act: { sub: admin } };
      const [trigger] = await postgres
        .asUser(act)
        .queryRaw<{ id: string }>(
          `insert into ${table} (name) values ('Parity') returning id, ${columns}`,
        );
      await stamped
        .connect(postgres.executorFor(act), {
          actor: { id: user, kind: "user", impersonator: admin },
        })
        .$table("plain")
        .create({ name: "Parity" })
        .orThrow();
      const read = async (): Promise<unknown[]> =>
        (await pool.query(`select ${columns} from public.${plain}`)).rows;
      const { id: _id, ...triggerInsert } = trigger!;
      expect(await read()).toEqual([triggerInsert]);
      expect(triggerInsert).toEqual({
        created_by: user,
        updated_by: user,
        impersonated_by: admin,
      });
      const [triggerUpdate] = await postgres
        .asUser(claims)
        .queryRaw(
          `update ${table} set name = 'Own' where id = $1 returning ${columns}`,
          [trigger!.id],
        );
      await stamped
        .connect(postgres.executorFor(claims), {
          actor: { id: user, kind: "user" },
        })
        .$table("plain")
        .update(
          (await pool.query<{ id: string }>(`select id from public.${plain}`))
            .rows[0]!.id,
          { name: "Own" },
        )
        .orThrow();
      expect(await read()).toEqual([triggerUpdate]);
      expect(triggerUpdate).toEqual({
        created_by: user,
        updated_by: user,
        impersonated_by: admin,
      });
    } finally {
      await pool.query(`drop table if exists public.${plain}`);
    }
  });

  it("keys audit entries by the table's primary key, composite ones too", async () => {
    const composite = `public.bs_block_pk_${RUN}`;
    try {
      await pool.query(`
        create table ${composite} (tenant int, code text, name text, primary key (tenant, code));
        select better_supabase.audit('${composite}');
        insert into ${composite} values (7, 'x', 'Seven');
      `);
      const log = await pool.query<{ record_id: string }>(
        `select record_id from better_supabase.audit_events where table_name = $1`,
        [composite],
      );
      expect(log.rows).toEqual([{ record_id: "7,x" }]);
    } finally {
      await pool.query(`select better_supabase.unaudit('${composite}')`);
      await pool.query(`drop table if exists ${composite}`);
      await pool.query(deleteAudit(`table_name = $1`), [composite]);
    }
  });

  it("runs invitations through memberships and has_organization_role", async () => {
    const createUser = async (
      email: string,
      confirmed: boolean,
    ): Promise<string> => {
      const created = await pool.query<{ id: string }>(
        `insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at) values (gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', $1, case when $2 then now() end) returning id`,
        [email, confirmed],
      );
      return created.rows[0]!.id;
    };
    const ownerId = await createUser(`owner-${RUN}@example.com`, true);
    const inviteeId = await createUser(`invitee-${RUN}@example.com`, true);
    const unconfirmedId = await createUser(
      `unconfirmed-${RUN}@example.com`,
      false,
    );
    const organization = crypto.randomUUID();
    try {
      await pool.query(
        "insert into better_supabase.organizations (id, name, slug) values ($1::uuid, 'Test', 'test-' || left($1::text, 8)) on conflict do nothing",
        [organization],
      );
      await pool.query(
        `insert into better_supabase.memberships (organization_id, user_id, role) values ($1, $2, 'owner')`,
        [organization, ownerId],
      );
      const asOwner = postgres.asUser({
        sub: ownerId,
        email: `owner-${RUN}@example.com`,
      });
      const asInvitee = postgres.asUser({
        sub: inviteeId,
        email: `invitee-${RUN}@example.com`,
      });

      await expect(
        asInvitee.queryRaw("select better_supabase.create_invitation($1, $2)", [
          organization,
          "x@example.com",
        ]),
      ).rejects.toMatchObject({ code: "42501" });
      const [{ token }] = (await asOwner.queryRaw<{ token: string }>(
        `select better_supabase.create_invitation($1, $2, 'admin') as token`,
        [organization, `invitee-${RUN}@example.com`],
      )) as [{ token: string }];

      const [accepted] = await asInvitee.queryRaw<{ organization: string }>(
        "select better_supabase.accept_invitation($1) as organization",
        [token],
      );
      expect(accepted!.organization).toBe(organization);
      const [role] = await asInvitee.queryRaw<{ admin: boolean }>(
        `select better_supabase.has_organization_role($1, '{admin}') as admin`,
        [organization],
      );
      expect(role!.admin).toBe(true);
      await expect(
        asInvitee.queryRaw("select better_supabase.accept_invitation($1)", [
          token,
        ]),
      ).rejects.toMatchObject({ hint: "INVITATION_INVALID" });

      await expect(
        asInvitee.queryRaw(
          `select better_supabase.create_invitation($1, $2, 'owner')`,
          [organization, "x@example.com"],
        ),
      ).rejects.toMatchObject({ hint: "INVITATION_ROLE_FORBIDDEN" });
      await expect(
        asOwner.queryRaw(
          `select better_supabase.create_invitation($1, $2, 'superuser')`,
          [organization, "x@example.com"],
        ),
      ).rejects.toMatchObject({ code: "23514" });
      const [owned] = await asOwner.queryRaw<{ token: string }>(
        `select better_supabase.create_invitation($1, $2, 'owner') as token`,
        [organization, `unconfirmed-${RUN}@example.com`],
      );
      await expect(
        postgres
          .asUser({
            sub: unconfirmedId,
            email: `unconfirmed-${RUN}@example.com`,
          })
          .queryRaw("select better_supabase.accept_invitation($1)", [
            owned!.token,
          ]),
      ).rejects.toMatchObject({ hint: "INVITATION_EMAIL_UNCONFIRMED" });

      for (const fn of [
        `better_supabase.has_organization_role('${organization}')`,
        "better_supabase.member_organization_ids()",
      ])
        await expect(
          postgres.anon.queryRaw(`select ${fn}`),
        ).rejects.toMatchObject({ code: "42501" });
      const ids = await asInvitee.queryRaw<{ id: string }>(
        `select better_supabase.member_organization_ids('{admin}') as id`,
      );
      expect(ids).toEqual([{ id: organization }]);
    } finally {
      await pool.query(
        "delete from better_supabase.organizations where id = $1",
        [organization],
      );
      await pool.query("delete from auth.users where id = any($1)", [
        [ownerId, inviteeId, unconfirmedId],
      ]);
    }
  });

  it("mfa_satisfied gates restrictive policies on aal2 once a factor is verified", async () => {
    const user = await pool.query<{ id: string }>(
      `insert into auth.users (id, instance_id, aud, role, email) values (gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', $1) returning id`,
      [`mfa-${RUN}@example.com`],
    );
    const sub = user.rows[0]!.id;
    const secrets = `public.bs_mfa_${RUN}`;
    const satisfied = async (aal: "aal1" | "aal2"): Promise<boolean> => {
      const [row] = await postgres
        .asUser({ sub, aal })
        .queryRaw<{ ok: boolean }>(
          "select better_supabase.mfa_satisfied() as ok",
        );
      return row!.ok;
    };
    try {
      await pool.query(`
        create table ${secrets} (id int primary key);
        insert into ${secrets} values (1);
        alter table ${secrets} enable row level security;
        create policy read on ${secrets} for select to authenticated using (true);
        create policy mfa_required on ${secrets} as restrictive
          for all to authenticated
          using ((select better_supabase.mfa_satisfied()));
        grant select on ${secrets} to authenticated;
      `);
      expect(await satisfied("aal1")).toBe(true);

      await pool.query(
        `insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
         values (gen_random_uuid(), $1, 'phone', 'totp', 'verified', now(), now())`,
        [sub],
      );
      expect(await satisfied("aal1")).toBe(false);
      expect(await satisfied("aal2")).toBe(true);

      const visible = async (aal: "aal1" | "aal2") =>
        (
          await postgres
            .asUser({ sub, aal })
            .queryRaw<{ n: number }>(
              `select count(*)::int as n from ${secrets}`,
            )
        )[0]!.n;
      expect(await visible("aal1")).toBe(0);
      expect(await visible("aal2")).toBe(1);

      await expect(
        postgres
          .asUser({ sub, role: "anon" })
          .queryRaw("select better_supabase.mfa_satisfied()"),
      ).rejects.toMatchObject({ code: "42501" });
    } finally {
      await pool.query(`drop table if exists ${secrets}`);
      await pool.query("delete from auth.users where id = $1", [sub]);
    }
  });

  it("session_active rejects tokens whose session was revoked", async () => {
    const user = await pool.query<{ id: string }>(
      `insert into auth.users (id, instance_id, aud, role, email) values (gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', $1) returning id`,
      [`session-${RUN}@example.com`],
    );
    const sub = user.rows[0]!.id;
    const session = crypto.randomUUID();
    await pool.query(
      `insert into auth.sessions (id, user_id, created_at, updated_at) values ($1, $2, now(), now())`,
      [session, sub],
    );
    const active = async (
      claims: Record<string, unknown>,
    ): Promise<boolean> => {
      const [row] = await postgres
        .asUser({ sub, ...claims })
        .queryRaw<{ ok: boolean }>(
          "select better_supabase.session_active() as ok",
        );
      return row!.ok;
    };
    try {
      expect(await active({ session_id: session })).toBe(true);
      expect(await active({ session_id: crypto.randomUUID() })).toBe(false);
      expect(await active({ session_id: "not-a-uuid" })).toBe(false);
      expect(await active({})).toBe(true);
      expect(
        await active({
          session_id: crypto.randomUUID(),
          act: { sub: crypto.randomUUID() },
        }),
      ).toBe(true);

      await pool.query(
        "update auth.users set banned_until = now() + interval '1 day' where id = $1",
        [sub],
      );
      expect(await active({ session_id: session })).toBe(false);
      await pool.query(
        "update auth.users set banned_until = null where id = $1",
        [sub],
      );
      await pool.query("delete from auth.sessions where id = $1", [session]);
      expect(await active({ session_id: session })).toBe(false);

      await expect(
        postgres
          .asUser({ sub, role: "anon" })
          .queryRaw("select better_supabase.session_active()"),
      ).rejects.toMatchObject({ code: "42501" });
    } finally {
      await pool.query("delete from auth.users where id = $1", [sub]);
    }
  });

  it("puts memberships and Stripe features in separate claims and RLS", async () => {
    const billing = `bs_billing_${RUN}`;
    const hook = `public.bs_hook_${RUN}`;
    const organization = crypto.randomUUID();
    const customer = `cus_${RUN}`;
    const users = await pool.query<{ id: string }>(
      `insert into auth.users (id, instance_id, aud, role, email)
       select gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', e
       from unnest($1::text[]) e returning id`,
      [[`ent-a-${RUN}@example.com`, `ent-b-${RUN}@example.com`]],
    );
    const [member, outsider] = users.rows.map((row) => row.id) as [
      string,
      string,
    ];
    const { rows: existing } = await pool.query(
      "select to_regclass('stripe.active_entitlements') as t",
    );
    const ownsStripe = existing[0].t === null;
    const module = renderModules(["entitlements"], {
      entitlements: { table: billing, column: "customer_id", key: "org_id" },
    }).find((file) => file.module === "entitlements");
    try {
      if (ownsStripe) {
        // Stripe Sync Engine 0.48.5, migration 0038.
        await pool.query(`
          create schema if not exists stripe;
          create table stripe.active_entitlements (
            id text primary key, object text, livemode boolean, feature text,
            customer text, lookup_key text,
            updated_at timestamptz not null default now(), last_synced_at timestamptz
          );`);
      }
      await pool.query(`
        create table public.${billing} (org_id uuid primary key, customer_id text unique);
        insert into public.${billing} values ('${organization}', '${customer}');
        insert into better_supabase.organizations (id, name, slug) values ('${organization}', 'Test', 'test-${organization.slice(0, 8)}');
        insert into better_supabase.memberships (organization_id, user_id, role) values ('${organization}', '${member}', 'admin');
        insert into stripe.active_entitlements (id, customer, lookup_key) values
          ('ent_b_${RUN}', '${customer}', 'sso'), ('ent_a_${RUN}', '${customer}', 'exports'),
          ('ent_c_${RUN}', 'cus_other_${RUN}', 'audit');
      `);
      await pool.query(module!.contents);
      await pool.query(`
        create function ${hook}(event jsonb) returns jsonb language plpgsql stable set search_path = '' as $$
        declare uid uuid := (event ->> 'user_id')::uuid;
        begin
          event := jsonb_set(event, '{claims,memberships}', better_supabase.membership_claims(uid));
          return jsonb_set(event, '{claims,features}', better_supabase.feature_claims(uid));
        end $$;
        grant execute on function ${hook}(jsonb) to supabase_auth_admin;
      `);

      // `postgres` can't become supabase_auth_admin locally: check its grants.
      const { rows: grants } = await pool.query(
        `select has_schema_privilege('supabase_auth_admin', 'better_supabase', 'usage') as schema,
          has_function_privilege('supabase_auth_admin', 'better_supabase.membership_claims(uuid)', 'execute') as fn,
          has_function_privilege('supabase_auth_admin', 'better_supabase.feature_claims(uuid)', 'execute') as features`,
      );
      expect(grants[0]).toEqual({ schema: true, fn: true, features: true });
      const claimsFor = async (sub: string) =>
        (
          await pool.query<{ event: { claims: unknown } }>(
            `select ${hook}(jsonb_build_object('user_id', $1::text, 'claims', '{}'::jsonb)) as event`,
            [sub],
          )
        ).rows[0]!.event.claims;
      expect(await claimsFor(member)).toEqual({
        memberships: [{ scope: "tenant", id: organization, roles: ["admin"] }],
        features: { [organization]: ["exports", "sso"] },
      });
      expect(await claimsFor(outsider)).toEqual({
        memberships: [],
        features: {},
      });

      const has = async (sub: string, key: string) =>
        (
          await postgres
            .asUser({ sub })
            .queryRaw<{ ok: boolean }>(
              "select better_supabase.has_entitlement($1, $2) as ok",
              [organization, key],
            )
        )[0]!.ok;
      expect(await has(member, "exports")).toBe(true);
      expect(await has(member, "audit")).toBe(false);
      expect(await has(outsider, "exports")).toBe(false);
      const tenantsWith = async (sub: string, key: string) =>
        (
          await postgres
            .asUser({ sub })
            .queryRaw<{ id: string }>(
              "select id from better_supabase.tenant_ids_with_entitlement($1) as t(id)",
              [key],
            )
        ).map((row) => row.id);
      expect(await tenantsWith(member, "sso")).toEqual([organization]);
      expect(await tenantsWith(member, "audit")).toEqual([]);
      expect(await tenantsWith(outsider, "sso")).toEqual([]);
      await expect(
        postgres
          .asUser({ sub: member })
          .queryRaw("select better_supabase.membership_claims($1)", [member]),
      ).rejects.toMatchObject({ code: "42501" });
      await expect(
        postgres
          .asUser({ sub: member })
          .queryRaw("select better_supabase.feature_claims($1)", [member]),
      ).rejects.toMatchObject({ code: "42501" });

      const invalidate = await entitlementMembers(postgres.admin, {
        type: ENTITLEMENTS_UPDATED,
        data: { object: { customer } },
      }).orThrow();
      expect(invalidate).toEqual([member]);
    } finally {
      await pool.query(`
        drop function if exists ${hook}(jsonb);
        drop function if exists better_supabase.entitlement_members(text);
        drop function if exists better_supabase.stripe_customer_tenants(text);
        drop function if exists better_supabase.tenant_stripe_customer(uuid);
        drop table if exists public.${billing};
        delete from better_supabase.organizations where id = '${organization}';
      `);
      await pool.query(
        ownsStripe
          ? "drop schema stripe cascade"
          : `delete from stripe.active_entitlements where id like '%_${RUN}'`,
      );
      await pool.query("delete from auth.users where id = any($1)", [
        [member, outsider],
      ]);
    }
  });

  it("reads entitlements from a plan catalog", async () => {
    const client = await pool.connect();
    const organization = crypto.randomUUID();
    const member = crypto.randomUUID();
    const as = async (sql: string, params: unknown[]) => {
      await client.query("savepoint plans");
      await client.query(
        "select set_config('request.jwt.claims', $1, true), set_config('role', 'authenticated', true)",
        [JSON.stringify({ sub: member, role: "authenticated" })],
      );
      const { rows } = await client.query(sql, params);
      await client.query("rollback to savepoint plans");
      return rows;
    };
    try {
      await client.query("begin");
      await client.query(
        `insert into auth.users (id, instance_id, aud, role, email)
         values ($1, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', $2)`,
        [member, `plans-${RUN}@example.com`],
      );
      await client.query(`
        create table public.bs_subs_${RUN} (team_id uuid, plan_key text, status text);
        create table public.bs_plan_features_${RUN} (plan_key text, feature_key text, included boolean);
        insert into public.bs_subs_${RUN} values
          ('${organization}', 'pro', 'active'), ('${organization}', 'old', 'canceled');
        insert into public.bs_plan_features_${RUN} values
          ('pro', 'exports', true), ('pro', 'sso', false), ('old', 'audit', true);
        insert into better_supabase.organizations (id, name, slug) values ('${organization}', 'Plans', 'plans-${organization.slice(0, 8)}');
        insert into better_supabase.memberships (organization_id, user_id, role) values ('${organization}', '${member}', 'member');
      `);
      const module = renderModules(["entitlements"], {
        entitlements: {
          key: "id",
          source: {
            plans: {
              subscriptions: {
                table: `public.bs_subs_${RUN}`,
                tenant: "team_id",
                plan: "plan_key",
                status: "status",
              },
              features: {
                table: `public.bs_plan_features_${RUN}`,
                plan: "plan_key",
                feature: "feature_key",
                included: "included",
              },
            },
          },
        },
      }).find(
        (file) => file.module === "entitlements" && file.kind === "schema",
      )!;
      await client.query(module.contents);
      const { rows } = await client.query<{ claims: unknown }>(
        "select better_supabase.feature_claims($1) as claims",
        [member],
      );
      expect(rows[0]!.claims).toEqual({ [organization]: ["exports"] });
      expect(
        await as(
          "select better_supabase.has_entitlement($1, 'exports') as a, better_supabase.has_entitlement($1, 'audit') as b",
          [organization],
        ),
      ).toEqual([{ a: true, b: false }]);
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("reads PermDock's member helpers in PermDock mode", async () => {
    const pd = `bs_pd_${RUN}`;
    const billing = `bs_billing_pd_${RUN}`;
    const organization = crypto.randomUUID();
    const customer = `cus_pd_${RUN}`;
    const users = await pool.query<{ id: string }>(
      `insert into auth.users (id, instance_id, aud, role, email)
       select gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', e
       from unnest($1::text[]) e returning id`,
      [
        [
          `pd-a-${RUN}@example.com`,
          `pd-b-${RUN}@example.com`,
          `pd-c-${RUN}@example.com`,
        ],
      ],
    );
    const [member, expired, outsider] = users.rows.map((row) => row.id) as [
      string,
      string,
      string,
    ];
    const entitlements = {
      table: billing,
      column: "customer_id",
      key: "org_id",
    } as const;
    const permdock = {
      schema: pd,
      scope: "organization",
      idType: "uuid",
      memberships: [
        {
          table: `${pd}.memberships`,
          userColumn: "user_id",
          scope: { column: "scope" },
          idColumn: "scope_id",
        },
      ],
    } as const;
    const module = renderModules(["entitlements"], { entitlements, permdock });
    expect(module.map((file) => [file.module, file.kind])).toEqual([
      ["entitlements", "schema"],
      ["entitlements", "data"],
    ]);
    const { rows: existing } = await pool.query(
      "select to_regclass('stripe.active_entitlements') as t",
    );
    const ownsStripe = existing[0].t === null;
    try {
      if (ownsStripe) {
        await pool.query(`
          create schema if not exists stripe;
          create table stripe.active_entitlements (
            id text primary key, object text, livemode boolean, feature text,
            customer text, lookup_key text,
            updated_at timestamptz not null default now(), last_synced_at timestamptz
          );`);
      }
      // Stand-ins with the shape of PermDock's generated helpers: security
      // definer, an active-membership filter, and _for revoked from users.
      await pool.query(`
        create schema ${pd};
        create table ${pd}.memberships (
          user_id uuid not null, scope text not null, scope_id uuid not null,
          role text not null, expires_at timestamptz
        );
        insert into ${pd}.memberships values
          ('${member}', 'organization', '${organization}', 'admin', null),
          ('${expired}', 'organization', '${organization}', 'admin', now() - interval '1 day'),
          ('${outsider}', 'customer', '${organization}', 'contact', null);
        create function ${pd}.member_organization_ids() returns setof uuid
        language sql stable security definer set search_path = '' as $$
          select scope_id from ${pd}.memberships
          where user_id = (select auth.uid()) and scope = 'organization'
            and (expires_at is null or expires_at > now())
        $$;
        create function ${pd}.member_organization_ids_for(p_user uuid) returns setof uuid
        language sql stable security definer set search_path = '' as $$
          select scope_id from ${pd}.memberships
          where user_id = p_user and scope = 'organization'
            and (expires_at is null or expires_at > now())
        $$;
        grant usage on schema ${pd} to authenticated, supabase_auth_admin;
        revoke execute on function ${pd}.member_organization_ids_for(uuid) from public, anon, authenticated;
        grant execute on function ${pd}.member_organization_ids_for(uuid) to supabase_auth_admin;
        create table public.${billing} (org_id uuid primary key, customer_id text unique);
        insert into public.${billing} values ('${organization}', '${customer}');
        insert into stripe.active_entitlements (id, customer, lookup_key) values
          ('ent_pd_a_${RUN}', '${customer}', 'exports');
      `);
      await pool.query(module[0]!.contents);

      // As supabase_auth_admin calls it from the hook: no auth.uid().
      const features = async (sub: string) =>
        (
          await pool.query<{ claims: unknown }>(
            "select better_supabase.feature_claims($1) as claims",
            [sub],
          )
        ).rows[0]!.claims;
      expect(await features(member)).toEqual({ [organization]: ["exports"] });
      expect(await features(expired)).toEqual({});
      expect(await features(outsider)).toEqual({});

      const has = async (sub: string) =>
        (
          await postgres
            .asUser({ sub })
            .queryRaw<{ ok: boolean }>(
              "select better_supabase.has_entitlement($1, 'exports') as ok",
              [organization],
            )
        )[0]!.ok;
      expect(await has(member)).toBe(true);
      expect(await has(expired)).toBe(false);
      expect(await has(outsider)).toBe(false);

      const invalidate = await entitlementMembers(postgres.admin, {
        type: ENTITLEMENTS_UPDATED,
        data: { object: { customer } },
      }).orThrow();
      expect([...invalidate].sort()).toEqual([member, expired].sort());
    } finally {
      // Put back the tenant-mode functions the other suites expect.
      await pool.query(
        renderModules(["entitlements"], { entitlements }).find(
          (file) => file.module === "entitlements",
        )!.contents,
      );
      await pool.query(`
        drop function if exists better_supabase.entitlement_members(text);
        drop function if exists better_supabase.stripe_customer_tenants(text);
        drop function if exists better_supabase.tenant_stripe_customer(uuid);
        drop table if exists public.${billing};
        drop schema if exists ${pd} cascade;
      `);
      await pool.query(
        ownsStripe
          ? "drop schema stripe cascade"
          : `delete from stripe.active_entitlements where id like '%_${RUN}'`,
      );
      await pool.query("delete from auth.users where id = any($1)", [
        [member, expired, outsider],
      ]);
    }
  });

  it("answers for the caller only under the permdock access model", async () => {
    const pd = `pd_access_${RUN}`;
    const me = "00000000-0000-4000-8000-0000000000a1";
    const other = "00000000-0000-4000-8000-0000000000a2";
    const sql = moduleBody("access", {
      modules: {
        access: {
          model: "permdock",
          permdock: { schema: pd, scope: "organization" },
        },
      },
    })!;
    const client = await pool.connect();
    const raises = async (query: string, params: unknown[]) => {
      await client.query("savepoint caller_only");
      await expect(client.query(query, params)).rejects.toMatchObject({
        code: "0A000",
        hint: "ACCESS_CALLER_ONLY",
      });
      await client.query("rollback to savepoint caller_only");
    };
    try {
      // The module's functions are shared, so this runs in a transaction that
      // rolls back and never replaces them for the other tests.
      await client.query("begin");
      await client.query(`
        create schema ${pd};
        create function ${pd}.permitted_organization_ids(permission text) returns setof uuid
        language sql stable as $$ select '${ACME}'::uuid where permission = 'members.read' $$;
        create function ${pd}.permdock_has(permission text) returns boolean
        language sql stable as $$ select false $$;`);
      await client.query(sql);
      await client.query("select set_config('request.jwt.claims', $1, true)", [
        JSON.stringify({ sub: me, role: "authenticated" }),
      ]);
      const answer = async (query: string, params: unknown[]) =>
        (await client.query<{ ok: boolean }>(query, params)).rows[0]!.ok;
      expect(
        await answer(
          "select better_supabase.member_can($1, $2, 'members.read') as ok",
          [me, ACME],
        ),
      ).toBe(true);
      expect(
        await answer(
          "select better_supabase.can_user($1, 'tenant', $2, 'members.update') as ok",
          [me, ACME],
        ),
      ).toBe(false);
      await raises(
        "select better_supabase.member_can($1, $2, 'members.read')",
        [other, ACME],
      );
      await raises(
        "select better_supabase.can_user($1, 'platform', null, 'support.start')",
        [other],
      );
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("queues, retries, dedupes and dead-letters jobs on pgmq", async () => {
    const queue = `block_${RUN}`;
    const jobs = createJobs(postgres.admin, {
      [queue]: v.object({ to: v.pipe(v.string(), v.email()) }),
    });
    const invalid = await jobs.enqueue(queue, { to: "nope" });
    expect(invalid).toMatchObject({ ok: false, error: { kind: "validation" } });

    const first = await jobs
      .enqueue(queue, { to: "a@example.com" }, { dedupeKey: "a" })
      .orThrow();
    const again = await jobs
      .enqueue(queue, { to: "a@example.com" }, { dedupeKey: "a" })
      .orThrow();
    expect(again).toBe(first);
    const index = await pool.query<{ indexdef: string }>(
      "select indexdef from pg_indexes where schemaname = 'pgmq' and indexname = $1",
      [`q_${queue}_dedupe_idx`],
    );
    expect(index.rows[0]!.indexdef).toContain("WHERE (message ? 'dedupe_key'");
    await jobs
      .enqueue(queue, { to: "b@example.com" }, { maxAttempts: 1 })
      .orThrow();
    await jobs
      .enqueue(queue, { to: "later@example.com" }, { delay: 3600 })
      .orThrow();

    const other = createJobs(postgres.admin, {
      [queue]: v.object({ to: v.pipe(v.string(), v.email()) }),
    });
    const [mine, theirs] = await Promise.all([
      jobs.claim(queue, { batch: 1 }).orThrow(),
      other.claim(queue, { batch: 1 }).orThrow(),
    ]);
    expect(mine).toHaveLength(1);
    expect(theirs).toHaveLength(1);
    expect(mine[0]!.id).not.toBe(theirs[0]!.id);
    expect(await jobs.complete({ ...mine[0]!, attempts: 99 }).orThrow()).toBe(
      false,
    );
    expect(
      await jobs.fail(mine[0]!, new Error("boom"), { retryIn: 0 }).orThrow(),
    ).toMatch(/queued|dead/);
    expect(
      await other.fail(theirs[0]!, "boom", { retryIn: 0 }).orThrow(),
    ).toMatch(/queued|dead/);

    const seen: string[] = [];
    const drained = await jobs.drain(queue, (payload, job) => {
      seen.push(payload.to);
      if (job.attempts < 3 && payload.to === "a@example.com")
        throw new Error("retry me");
      return;
    });
    expect(drained.succeeded + drained.failed).toBeGreaterThan(0);
    const waiting = await pool.query<{
      message: { payload: { to: string }; last_error?: string };
      read_ct: number;
    }>(`select message, read_ct from pgmq.q_${queue} order by msg_id`);
    const archived = await pool.query<{
      message: { payload: { to: string }; dead?: boolean };
      read_ct: number;
    }>(`select message, read_ct from pgmq.a_${queue} order by msg_id`);
    const waitingBy = new Map(
      waiting.rows.map((row) => [row.message.payload.to, row]),
    );
    const archivedBy = new Map(
      archived.rows.map((row) => [row.message.payload.to, row]),
    );
    expect(archivedBy.get("b@example.com")).toMatchObject({
      read_ct: 1,
      message: { dead: true },
    });
    expect(waitingBy.get("later@example.com")).toMatchObject({ read_ct: 0 });
    expect(waitingBy.get("a@example.com")?.message.last_error).toBe("retry me");

    const deadId = (
      await pool.query<{ msg_id: string }>(
        `select msg_id from pgmq.a_${queue} where message ->> 'dead' = 'true'`,
      )
    ).rows[0]!.msg_id;
    const replayed = await jobs.replay(queue, Number(deadId)).orThrow();
    expect(replayed).toEqual(expect.any(Number));
    expect(await jobs.replay(queue, Number(deadId)).orThrow()).toBeNull();
    const back = await pool.query<{ message: { payload: { to: string } } }>(
      `select message from pgmq.q_${queue} where msg_id = $1`,
      [replayed],
    );
    expect(back.rows[0]!.message.payload.to).toBe("b@example.com");
  });

  it("dead-letters a pgmq job whose worker died on the last attempt", async () => {
    const queue = `block_${RUN}_lost`;
    const jobs = createJobs(postgres.admin, { [queue]: v.object({}) });
    await jobs.enqueue(queue, {}, { maxAttempts: 1 }).orThrow();
    expect(await jobs.claim(queue, { lease: 1 }).orThrow()).toHaveLength(1);
    await pool.query(
      `update pgmq.q_${queue} set vt = now() - interval '1 second'`,
    );
    expect(await jobs.claim(queue).orThrow()).toEqual([]);
    const archived = await pool.query<{
      message: { dead?: boolean; last_error?: string };
    }>(`select message from pgmq.a_${queue}`);
    expect(archived.rows[0]!.message).toMatchObject({
      dead: true,
      last_error: "The lease ran out on the last attempt",
    });
  });

  it("carries the enqueuing actor and tenant through pgmq", async () => {
    const queue = `block_${RUN}_ctx`;
    const jobs = createJobs(postgres.admin, {
      [queue]: v.object({ to: v.pipe(v.string(), v.email()) }),
    });
    const context = {
      actor: { id: "u1", kind: "user" as const },
      claims: { app_metadata: { tenant_id: "o1" } },
    };
    const id = await jobs
      .enqueue(queue, { to: "a@example.com" }, { context, dedupeKey: "a" })
      .orThrow();
    expect(
      await jobs
        .enqueue(queue, { to: "a@example.com" }, { context, dedupeKey: "a" })
        .orThrow(),
    ).toBe(id);
    const seen: unknown[] = [];
    const drained = await jobs.drain(queue, (payload, job) => {
      seen.push([payload, job.context]);
    });
    expect(drained).toEqual({ succeeded: 1, failed: 0 });
    expect(seen).toEqual([
      [{ to: "a@example.com" }, { actor: context.actor, tenant: "o1" }],
    ]);
  });

  it("schedules recurring jobs with pg_cron", async () => {
    const queue = `block_${RUN}_cron`;
    const jobs = createJobs(postgres.admin, {
      [queue]: v.object({ kind: v.string() }),
    });
    const name = `bs-module-${RUN}`;
    await pool.query(
      "create extension if not exists pg_cron with schema pg_catalog",
    );
    await jobs.schedule(name, "0 3 * * *", queue, { kind: "digest" }).orThrow();
    const { rows } = await pool.query<{ command: string }>(
      "select command from cron.job where jobname = $1",
      [name],
    );
    expect(rows[0]?.command).toContain(`enqueue_job('${queue}'`);
    expect(await jobs.unschedule(name).orThrow()).toBe(true);
  });

  it("works a queue until the signal aborts", async () => {
    const queue = `block_${RUN}_work`;
    const jobs = createJobs(postgres.admin, {
      [queue]: v.object({ n: v.number() }),
    });
    for (const n of [1, 2, 3, 4]) await jobs.enqueue(queue, { n }).orThrow();
    const controller = new AbortController();
    const done: number[] = [];
    const result = await jobs.work(
      queue,
      (payload) => {
        done.push(payload.n);
        if (done.length === 4) controller.abort();
        return;
      },
      { concurrency: 2, pollInterval: 20, signal: controller.signal },
    );
    expect(done.toSorted((a, b) => a - b)).toEqual([1, 2, 3, 4]);
    expect(result).toEqual({ succeeded: 4, failed: 0 });
  });

  it("passes the queue backend conformance kit on pgmq", async () => {
    await testQueueBackend(sqlQueueBackend(postgres.admin), {
      queue: `block_${RUN}_conf`,
    });
  });

  it("runs jobs and time-zone schedules on the table backend", async () => {
    const queue = `block_${RUN}_table`;
    const name = `bs-module-table-${RUN}`;
    await pool.query(
      moduleBody("jobs", {
        modules: {
          jobs: { options: { backend: "table", scheduler: "drain" } },
        },
      })!,
    );
    try {
      await testQueueBackend(sqlQueueBackend(postgres.admin), {
        queue: `${queue}_conf`,
      });
      const jobs = createJobs(postgres.admin, {
        [queue]: v.object({ to: v.string() }),
      });
      const first = await jobs
        .enqueue(queue, { to: "a" }, { dedupeKey: "a" })
        .orThrow();
      expect(
        await jobs.enqueue(queue, { to: "a" }, { dedupeKey: "a" }).orThrow(),
      ).toBe(first);
      await jobs.enqueue(queue, { to: "b" }, { maxAttempts: 1 }).orThrow();

      const other = createJobs(postgres.admin, {
        [queue]: v.object({ to: v.string() }),
      });
      const [mine, theirs] = await Promise.all([
        jobs.claim(queue).orThrow(),
        other.claim(queue).orThrow(),
      ]);
      expect(mine[0]!.id).not.toBe(theirs[0]!.id);
      expect(await jobs.complete({ ...mine[0]!, attempts: 99 }).orThrow()).toBe(
        false,
      );
      const states = await Promise.all(
        [...mine, ...theirs].map((job) =>
          jobs.fail(job, "boom", { retryIn: 0 }).orThrow(),
        ),
      );
      expect(
        states.toSorted((a, b) => String(a).localeCompare(String(b))),
      ).toEqual(["dead", "queued"]);
      expect(await jobs.drain(queue, () => undefined)).toEqual({
        succeeded: 1,
        failed: 0,
      });
      const rows = await pool.query<{ dead: boolean; archived: boolean }>(
        `select dead, archived_at is not null as archived
         from better_supabase.job_messages where queue = $1 order by id`,
        [queue],
      );
      expect(rows.rows).toEqual([
        { dead: false, archived: true },
        { dead: true, archived: true },
      ]);
      const deadRow = (
        await pool.query<{ id: string }>(
          "select id from better_supabase.job_messages where queue = $1 and dead",
          [queue],
        )
      ).rows[0]!.id;
      const replayed = await jobs.replay(queue, Number(deadRow)).orThrow();
      expect(replayed).not.toBeNull();
      expect(await jobs.replay(queue, Number(deadRow)).orThrow()).toBeNull();
      await pool.query(
        "update better_supabase.job_messages set attempts = 1, visible_at = now() - interval '1 second' where id = $1",
        [replayed],
      );
      expect(await jobs.claim(queue).orThrow()).toEqual([]);
      const lost = await pool.query<{ dead: boolean; error: string }>(
        "select dead, message ->> 'last_error' as error from better_supabase.job_messages where id = $1",
        [replayed],
      );
      expect(lost.rows[0]).toEqual({
        dead: true,
        error: "The lease ran out on the last attempt",
      });

      await jobs
        .schedule(
          name,
          "0 9 * * *",
          queue,
          { to: "digest" },
          {
            timeZone: "Europe/Amsterdam",
          },
        )
        .orThrow();
      const stored = await pool.query<{ timezone: string; local: string }>(
        `select timezone, to_char(next_run at time zone timezone, 'HH24:MI') as local
         from better_supabase.job_schedules where job_name = $1`,
        [name],
      );
      expect(stored.rows[0]).toEqual({
        timezone: "Europe/Amsterdam",
        local: "09:00",
      });
      await pool.query(
        `update better_supabase.job_schedules
         set next_run = date_trunc('milliseconds', now()) - interval '1 minute'
         where job_name = $1`,
        [name],
      );
      const route = jobs.drainRoute({
        secret: "s3cret",
        handlers: { [queue]: () => undefined },
      });
      const response = await route(
        new Request("https://app.test/api/jobs/drain", {
          headers: { authorization: "Bearer s3cret" },
        }),
      );
      expect(await response.json()).toMatchObject({
        schedules: 1,
        queues: { [queue]: { succeeded: 1, failed: 0 } },
      });
      const moved = await pool.query<{ due: boolean }>(
        "select next_run > now() as due from better_supabase.job_schedules where job_name = $1",
        [name],
      );
      expect(moved.rows[0]!.due).toBe(true);
      await expect(
        pool.query(
          "select better_supabase.schedule_job('x', '* * * * *', 'q', '{}', 'Mars/Base')",
        ),
      ).rejects.toThrow(/Unknown time zone/);
      expect(await jobs.unschedule(name).orThrow()).toBe(true);
    } finally {
      await pool.query(
        "delete from better_supabase.job_messages where queue like $1",
        [`${queue}%`],
      );
      await pool.query(SQL_MODULES["jobs"]!.sql);
    }
  });

  it("runs named tenant schedules from an external scheduler without pg_cron", async () => {
    const queue = `block_${RUN}_ext`;
    await pool.query(
      moduleBody("jobs", {
        modules: {
          jobs: { options: { backend: "table", scheduler: "drain" } },
        },
      })!,
    );
    try {
      const jobs = createJobs(postgres.admin, {
        [queue]: v.object({ report: v.string() }),
      });
      await jobs
        .schedule(
          `ext-${RUN}:hourly`,
          "0 * * * *",
          queue,
          { report: "hourly" },
          { context: { tenant: "tenant-a" } },
        )
        .orThrow();
      await jobs
        .schedule(
          `ext-${RUN}:daily`,
          "30 6 * * *",
          queue,
          { report: "daily" },
          { tenant: "tenant-b", timeZone: "Europe/Amsterdam" },
        )
        .orThrow();
      const listed = await jobs
        .listSchedules({ prefix: `ext-${RUN}:` })
        .orThrow();
      expect(listed.map((entry) => [entry.name, entry.tenant])).toEqual([
        [`ext-${RUN}:daily`, "tenant-b"],
        [`ext-${RUN}:hourly`, "tenant-a"],
      ]);
      expect(listed.every((entry) => entry.nextRun !== null)).toBe(true);
      expect(
        (await jobs.listSchedules({ tenant: "tenant-a" }).orThrow()).map(
          (entry) => entry.name,
        ),
      ).toContain(`ext-${RUN}:hourly`);
      await pool.query(
        `update better_supabase.job_schedules
         set next_run = date_trunc('milliseconds', now()) - interval '1 minute'
         where job_name like $1`,
        [`ext-${RUN}:%`],
      );
      const seen: [string, string | undefined][] = [];
      const finished: unknown[] = [];
      const route = jobs.drainRoute({
        secret: "s3cret",
        handlers: {
          [queue]: (payload, job) => {
            seen.push([payload.report, job.context.tenant]);
          },
        },
        monitor: { onFinish: (result) => finished.push(result) },
      });
      const response = await route(
        new Request("https://app.test/api/jobs/drain", {
          method: "POST",
          headers: { authorization: "Bearer s3cret" },
        }),
      );
      expect(await response.json()).toMatchObject({
        schedules: 2,
        queues: { [queue]: { succeeded: 2, failed: 0 } },
        errors: 0,
      });
      expect(finished).toHaveLength(1);
      expect(seen.toSorted((a, b) => a[0].localeCompare(b[0]))).toEqual([
        ["daily", undefined],
        ["hourly", "tenant-a"],
      ]);
      const again = await route(
        new Request("https://app.test/api/jobs/drain", {
          headers: { authorization: "Bearer s3cret" },
        }),
      );
      expect(await again.json()).toMatchObject({ schedules: 0 });
      expect(await jobs.unscheduleAll({ tenant: "tenant-a" }).orThrow()).toBe(
        1,
      );
      expect(
        (await jobs.listSchedules({ prefix: `ext-${RUN}:` }).orThrow()).map(
          (entry) => entry.name,
        ),
      ).toEqual([`ext-${RUN}:daily`]);
    } finally {
      await pool.query(
        "delete from better_supabase.job_messages where queue = $1",
        [queue],
      );
      await pool.query(
        "delete from better_supabase.job_schedules where job_name like $1",
        [`ext-${RUN}:%`],
      );
      await pool.query(SQL_MODULES["jobs"]!.sql);
    }
  });

  it("replays idempotent requests and rejects reuse", async () => {
    const idempotency = createIdempotency(postgres.admin, { scope: RUN });
    let runs = 0;
    const handler = async () => {
      runs += 1;
      return Response.json({ order: runs }, { status: 201 });
    };
    const request = (body: string, key = "order-1") =>
      new Request("https://api.test/orders", {
        method: "POST",
        headers: { "idempotency-key": key, "content-type": "application/json" },
        body,
      });
    const first = await idempotency.handle(request('{"sku":1}'), handler);
    expect(first.status).toBe(201);
    const replay = await idempotency.handle(request('{"sku":1}'), handler);
    expect(replay.status).toBe(201);
    expect(replay.headers.get("idempotency-replayed")).toBe("true");
    expect(await replay.json()).toEqual({ order: 1 });
    expect(runs).toBe(1);
    const reused = await idempotency.handle(request('{"sku":2}'), handler);
    expect(reused.status).toBe(422);

    const failing = await idempotency.handle(
      request("{}", "order-2"),
      () => new Response("down", { status: 503 }),
    );
    expect(failing.status).toBe(503);
    expect(
      (await idempotency.handle(request("{}", "order-2"), handler)).status,
    ).toBe(201);
  });

  it("runs blocks on @supabase/server's Postgres pool", async () => {
    const queue = `block_${RUN}_server`;
    const handler = pipeline(
      [
        withPostgresAdminClient({ connectionString: dbUrl }),
        withBlock("jobs", (ctx: { readonly postgresAdmin: PostgresApi }) =>
          createJobs(ctx.postgresAdmin, {
            [queue]: v.object({ n: v.number() }),
          }),
        ),
        withBlock(
          "idempotency",
          (ctx: { readonly postgresAdmin: PostgresApi }) =>
            createIdempotency(ctx.postgresAdmin, { scope: `server-${RUN}` }),
        ),
      ],
      async (request, ctx) =>
        ctx.idempotency.handle(request, async () => {
          const id = await ctx.jobs.enqueue(queue, { n: 1 }).orThrow();
          const slug = await sqlTransport(ctx.postgresAdmin).call(
            "better_supabase",
            "slug_problem",
            { slug: "admin" },
          );
          const seen: number[] = [];
          const drained = await ctx.jobs.drain(queue, (payload) => {
            seen.push(payload.n);
          });
          return Response.json({ id, slug, drained, seen }, { status: 201 });
        }),
    );
    const request = () =>
      new Request("https://api.test/run", {
        method: "POST",
        headers: { "idempotency-key": "run-1" },
        body: "{}",
      });
    const first = await handler(request());
    expect(first.status).toBe(201);
    const body = (await first.json()) as Record<string, unknown>;
    expect(body).toMatchObject({
      slug: "reserved",
      drained: { succeeded: 1, failed: 0 },
      seen: [1],
    });
    const replay = await handler(request());
    expect(replay.headers.get("idempotency-replayed")).toBe("true");
    expect(await replay.json()).toEqual(body);
  });

  it("stores verified webhooks once and processes them with retries", async () => {
    const secret = `whsec_${btoa("a-webhook-secret-for-the-inbox-test")}`;
    const inbox = createInbox(postgres.admin, {
      source: `module-${RUN}`,
      secrets: secret,
    });
    const deliver = async (id: string, payload: unknown) => {
      const body = JSON.stringify(payload);
      const headers = await signWebhook(secret, { id, body });
      return inbox.receive(
        new Request("https://api.test/hooks", {
          method: "POST",
          headers,
          body,
        }),
      );
    };
    expect(
      (await deliver("msg_1", { type: "invoice.paid", n: 1 })).status,
    ).toBe(202);
    expect(
      (await deliver("msg_1", { type: "invoice.paid", n: 1 })).status,
    ).toBe(200);
    expect(
      (await deliver("msg_2", { type: "invoice.failed", n: 2 })).status,
    ).toBe(202);
    const forged = await inbox.receive(
      new Request("https://api.test/hooks", {
        method: "POST",
        headers: {
          "webhook-id": "x",
          "webhook-timestamp": "1",
          "webhook-signature": "v1,AAAA",
        },
        body: "{}",
      }),
    );
    expect(forged.status).toBe(401);

    const types: string[] = [];
    const result = await inbox.process((message) => {
      types.push(message.type ?? "");
      if (message.type === "invoice.failed") throw new Error("try later");
      return;
    });
    expect(result).toEqual({ succeeded: 1, failed: 1 });
    expect(types.sort()).toEqual(["invoice.failed", "invoice.paid"]);
    expect(await inbox.process(() => undefined)).toEqual({
      succeeded: 0,
      failed: 0,
    });
  });

  it("keeps inbox messages per tenant and resumes from a checkpoint", async () => {
    const source = `tenant-${RUN}`;
    const inbox = createInbox(postgres.admin, {
      source,
      verify: () => Promise.reject(new Error("store only")),
      tenantOf: (payload) => (payload as { account?: string }).account ?? null,
    });
    expect(
      await inbox
        .store({ id: "page-1", payload: { account: "acct-a", pages: 3 } })
        .orThrow(),
    ).toMatchObject({ duplicate: false });
    expect(
      await inbox
        .store({ id: "page-1", payload: { account: "acct-a", pages: 3 } })
        .orThrow(),
    ).toMatchObject({ duplicate: true });
    await inbox
      .store({ id: "other", payload: { pages: 1 }, tenant: "acct-b" })
      .orThrow();

    const cursors: unknown[] = [];
    const first = await inbox.process<{ pages: number }>(async (message) => {
      cursors.push(message.progress["page"] ?? 0);
      if (message.tenant !== "acct-a") return;
      await message.checkpoint({ page: 2 });
      throw new Error("provider timed out on page 3");
    });
    expect(first).toEqual({ succeeded: 1, failed: 1 });
    await pool.query(
      "update better_supabase.webhook_inbox set available_at = now() where source = $1",
      [source],
    );
    const second = await inbox.process(async (message) => {
      cursors.push(message.progress["page"]);
    });
    expect(second).toEqual({ succeeded: 1, failed: 0 });
    expect(cursors.toSorted((a, b) => Number(a) - Number(b))).toEqual([
      0, 0, 2,
    ]);

    const listed = await inbox.list({ tenant: "acct-a" }).orThrow();
    expect(listed.map((entry) => [entry.messageId, entry.status])).toEqual([
      ["page-1", "processed"],
    ]);
    expect(
      await inbox.purge({ tenant: "acct-a", olderThan: 0 }).orThrow(),
    ).toBe(1);
    expect(await inbox.list({ tenant: "acct-a" }).orThrow()).toEqual([]);
    expect(await inbox.list({ tenant: "acct-b" }).orThrow()).toHaveLength(1);
  });

  it("purges old audit entries, processed webhooks and job archives", async () => {
    const old = "now() - interval '11 years'";
    const count = async (text: string, params: unknown[] = []) =>
      (await pool.query<{ n: number }>(text, params)).rows[0]!.n;
    const purge = (call: string) => count(`select ${call} as n`);

    await pool.query(
      `insert into better_supabase.audit_events (table_name, op, occurred_at)
       values ($1, 'insert', ${old}), ($1, 'update', ${old}), ($1, 'delete', now())`,
      [`purge_${RUN}`],
    );
    expect(await purge("better_supabase.purge_audit_log('10 years', 1)")).toBe(
      1,
    );
    expect(await purge("better_supabase.purge_audit_log('10 years')")).toBe(1);
    expect(await purge("better_supabase.purge_audit_log('10 years')")).toBe(0);
    expect(
      await count(
        "select count(*)::int as n from better_supabase.audit_events where table_name = $1",
        [`purge_${RUN}`],
      ),
    ).toBe(1);
    await pool.query(deleteAudit("table_name = $1"), [`purge_${RUN}`]);

    await pool.query(
      `insert into better_supabase.webhook_inbox (source, message_id, payload, status, processed_at, received_at)
       values ($1, 'old-done', '{}', 'processed', ${old}, ${old}),
              ($1, 'old-dead', '{}', 'dead', null, ${old}),
              ($1, 'old-pending', '{}', 'pending', null, ${old})`,
      [`module-${RUN}`],
    );
    expect(await purge("better_supabase.purge_webhooks('10 years')")).toBe(1);
    expect(
      await purge(
        "better_supabase.purge_webhooks('10 years', include_dead => true)",
      ),
    ).toBe(1);
    expect(
      await count(
        "select count(*)::int as n from better_supabase.webhook_inbox where source = $1 and message_id like 'old-%'",
        [`module-${RUN}`],
      ),
    ).toBe(1);

    const queue = `block_${RUN}_purge`;
    await pool.query("select better_supabase.ensure_job_queue($1)", [queue]);
    for (let index = 0; index < 2; index += 1)
      await pool.query("select pgmq.archive($1, pgmq.send($1, '{}'::jsonb))", [
        queue,
      ]);
    await pool.query(
      `update pgmq.a_${queue} set archived_at = ${old} where msg_id = (select min(msg_id) from pgmq.a_${queue})`,
    );
    expect(
      await count(
        "select better_supabase.purge_job_archive($1, '10 years') as n",
        [queue],
      ),
    ).toBe(1);
    expect(await count(`select count(*)::int as n from pgmq.a_${queue}`)).toBe(
      1,
    );
    await pool.query(
      `select pgmq.archive($1, pgmq.send($1, '{"dead": true}'::jsonb))`,
      [queue],
    );
    await pool.query(
      `update pgmq.a_${queue} set archived_at = now() - interval '20 days'`,
    );
    expect(
      await count(
        "select better_supabase.purge_job_archive($1, '10 days') as n",
        [queue],
      ),
    ).toBe(1);
    expect(
      await count(
        `select count(*)::int as n from pgmq.a_${queue} where message ? 'dead'`,
      ),
    ).toBe(1);

    const executable = await pool.query<{ role: string; allowed: boolean }>(
      `select r.role, has_function_privilege(r.role, f.fn, 'execute') as allowed
       from unnest(array['anon', 'authenticated', 'service_role']) as r(role),
            unnest(array[
              'better_supabase.purge_audit_log(interval, integer, uuid, boolean)',
              'better_supabase.audit_event(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text)',
              'better_supabase.purge_webhooks(interval, boolean, integer, text)',
              'better_supabase.purge_job_archive(text, interval, integer, interval)',
              'better_supabase.replay_dead_job(text, bigint)'
            ]) as f(fn)`,
    );
    for (const row of executable.rows)
      expect(row.allowed).toBe(row.role === "service_role");
  });

  it("passes the pgTAP file it writes for an audited table", async () => {
    const name = `public.bs_audit_tap_${RUN}`;
    const register = `select better_supabase.audit('${name}', ignore => '{updated_at}', redact => '{api_key}');`;
    await pool.query(`
      create table ${name} (
        id bigint generated always as identity primary key,
        organization_id uuid not null references public.organizations (id),
        status public.note_kind not null,
        api_key text not null check (api_key <> ''),
        settings jsonb not null default '{}',
        amount numeric(4, 2),
        due date,
        updated_at timestamptz not null default now()
      );
      ${register}
    `);
    const file = (tables: Parameters<typeof renderModules>[1]) =>
      renderModules(["audit"], tables).find((entry) => entry.kind === "test")!;
    const tap = async (contents: string): Promise<string[]> => {
      const client = await pool.connect();
      try {
        const results = await client.query(contents);
        return (Array.isArray(results) ? results : [results]).flatMap(
          (result: { rows: Record<string, unknown>[] }) =>
            result.rows.flatMap((row) => Object.values(row).map(String)),
        );
      } finally {
        client.release();
      }
    };
    try {
      const passing = await tap(
        file({ auditedTables: auditRegistrations([{ text: register }]) })
          .contents,
      );
      expect(passing.filter((line) => /^not ok/m.test(line))).toEqual([]);
      expect(passing.filter((line) => line.startsWith("ok "))).toHaveLength(7);
      const drifted = await tap(
        file({
          auditedTables: [{ target: name, ignore: [], redact: ["status"] }],
        }).contents,
      );
      expect(
        drifted
          .filter((line) => /^not ok/m.test(line))
          .map((line) => line.split("\n")[0]),
      ).toEqual([
        `not ok 3 - ${name} is registered with its ignored columns`,
        `not ok 4 - ${name} is registered with its redacted columns`,
      ]);
    } finally {
      await pool.query(`select better_supabase.unaudit('${name}')`);
      await pool.query(`drop table if exists ${name}`);
      await pool.query(deleteAudit("table_name like $1"), ["pg_temp%"]);
    }
  });

  it("redacts columns, names events and records idempotent semantic events", async () => {
    const name = `public.bs_audit_${RUN}`;
    await pool.query(`
      create table ${name} (id int primary key, organization_id uuid, api_key text, note text);
      select better_supabase.audit('${name}', redact => '{api_key}', event_prefix => 'secret',
        category => 'security', target_type => 'secret');
      insert into ${name} values (1, '${ACME}', 'sk_live', 'a');
      update ${name} set api_key = 'sk_new' where id = 1;
    `);
    try {
      const { rows } = await pool.query<{
        event_type: string;
        category: string;
        target_type: string;
        new_record: { api_key: string };
        changed: string[] | null;
        organization_id: string;
      }>(
        `select event_type, category, target_type, new_record, changed, organization_id
         from better_supabase.audit_events where table_name = $1 order by id`,
        [name],
      );
      expect(rows.map((row) => row.event_type)).toEqual([
        "secret.created",
        "secret.updated",
      ]);
      expect(rows[1]).toMatchObject({
        category: "security",
        target_type: "secret",
        new_record: { api_key: "[redacted]" },
        changed: ["api_key"],
        organization_id: ACME,
      });

      const event = (key: string) =>
        pool.query<{ id: string }>(
          `select better_supabase.audit_event('invoice.sent', category => 'billing',
             tenant => $1, metadata => '{"invoice": 7}', idempotency_key => $2) as id`,
          [ACME, key],
        );
      const first = (await event(`k_${RUN}`)).rows[0]!.id;
      expect((await event(`k_${RUN}`)).rows[0]!.id).toBe(first);
      const stored = await pool.query(
        `select op, event_type, category, outcome, source, metadata
         from better_supabase.audit_events where id = $1::bigint`,
        [first],
      );
      expect(stored.rows[0]).toEqual({
        op: "event",
        event_type: "invoice.sent",
        category: "billing",
        outcome: "success",
        source: "app",
        metadata: { invoice: 7 },
      });
      await expect(
        pool.query(
          `select better_supabase.audit_event('invoice.sent', restricted => '{"card": "4242"}')`,
        ),
      ).rejects.toMatchObject({ code: "22023" });
      await pool.query(deleteAudit("id = $1::bigint"), [first]);
    } finally {
      await pool.query(`select better_supabase.unaudit('${name}')`);
      await pool.query(`drop table if exists ${name}`);
      await pool.query(deleteAudit("table_name = $1"), [name]);
    }
  });

  it("records actor, labels, request ids and per-column changes", async () => {
    const client = await pool.connect();
    const name = `bs_audit_ctx_${RUN}`;
    const actor = crypto.randomUUID();
    try {
      await client.query("begin");
      await client.query(
        moduleBody("audit", {
          modules: { audit: { options: { restricted: true } } },
        })!,
      );
      await client.query(`
        create table public.${name} (id int primary key, organization_id uuid, title text, secret text);
        create table public.${name}_free (id int primary key, note text);
      `);
      const calls = await client.query<{ call: string }>(
        "select better_supabase.audit_schema_calls('public', 'organization_id', $1) as call",
        [[`${name}_x%`]],
      );
      expect(calls.rows.map((row) => row.call)).toContain(
        `select better_supabase.audit('public.${name}');`,
      );
      expect(calls.rows.map((row) => row.call)).not.toContain(
        `select better_supabase.audit('public.${name}_free');`,
      );
      await client.query(
        `select better_supabase.audit('public.${name}', redact => '{secret}', label_column => 'title')`,
      );
      await client.query(
        `select set_config('request.jwt.claims', $1, true),
                set_config('request.headers', $2, true)`,
        [
          JSON.stringify({
            sub: actor,
            role: "authenticated",
            email: "ada@example.test",
          }),
          JSON.stringify({
            "x-request-id": "req-1",
            "x-correlation-id": "cor-1",
          }),
        ],
      );
      await client.query(
        `insert into public.${name} values (1, '${ACME}', 'Quarterly report', 'k1');
         update public.${name} set title = 'Annual report', secret = 'k2' where id = 1;`,
      );
      const { rows } = await client.query(
        `select e.actor_kind, e.actor_label, e.target_label, e.request_id, e.correlation_id, e.scope,
                e.tenant_label, r.changed_values
         from better_supabase.audit_events e
         join better_supabase.audit_events_restricted r on r.entry_id = e.id
         where e.table_name = $1 order by e.id`,
        [`public.${name}`],
      );
      expect(rows[1]).toMatchObject({
        actor_kind: "user",
        actor_label: "ada@example.test",
        target_label: "Annual report",
        request_id: "req-1",
        correlation_id: "cor-1",
        scope: "tenant",
        changed_values: {
          title: { old: "Quarterly report", new: "Annual report" },
          secret: { old: "[redacted]", new: "[redacted]" },
        },
      });
      expect(rows[0]!.changed_values).toMatchObject({
        title: { old: null, new: "Quarterly report" },
      });
      await client.query("select set_config('request.jwt.claims', $1, true)", [
        JSON.stringify({ role: "service_role" }),
      ]);
      await client.query(
        `select better_supabase.audit_event('report.exported', summary => 'Exported 3 reports',
           target_label => 'Q3', correlation_id => 'job-9')`,
      );
      const event = await client.query(
        `select actor_kind, summary, target_label, correlation_id, scope
         from better_supabase.audit_events where event_type = 'report.exported' order by id desc limit 1`,
      );
      expect(event.rows[0]).toEqual({
        actor_kind: "service",
        summary: "Exported 3 reports",
        target_label: "Q3",
        correlation_id: "job-9",
        scope: "platform",
      });
      await client.query(`drop trigger bs_audit on public.${name}`);
      await client.query(
        `delete from better_supabase.audited_tables where target = 'public.${name}'::regclass`,
      );
      const added = await client.query<{ n: number }>(
        "select better_supabase.audit_schema('public', 'organization_id', $1) as n",
        [["%"]],
      );
      expect(added.rows[0]!.n).toBe(0);
      const some = await client.query<{ n: number }>(
        `select better_supabase.audit_schema('public', 'organization_id', array(
           select c.relname::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'public' and c.relname <> $1
         )) as n`,
        [name],
      );
      expect(some.rows[0]!.n).toBe(1);
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("lists and reveals audit entries through the audit functions", async () => {
    const client = await pool.connect();
    const name = `bs_audit_api_${RUN}`;
    const admin = crypto.randomUUID();
    const outsider = crypto.randomUUID();
    let claims: object = { role: "service_role" };
    const sql: SqlClient = {
      async queryRaw<T>(text: string, params: unknown[] = []) {
        await client.query("savepoint call");
        try {
          await client.query(
            "select set_config('request.jwt.claims', $1, true), set_config('role', $2, true)",
            [
              JSON.stringify(claims),
              "sub" in claims ? "authenticated" : "postgres",
            ],
          );
          const { rows } = await client.query(text, params);
          await client.query("reset role");
          await client.query("release savepoint call");
          // SAFETY: the block names the row shape of its own queries.
          return rows as T[];
        } catch (error) {
          await client.query("rollback to savepoint call");
          throw error;
        }
      },
    };
    try {
      await client.query("begin");
      for (const id of [admin, outsider]) {
        await client.query(
          `insert into auth.users (id, instance_id, aud, role, email)
           values ($1, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', $2)`,
          [id, `${id}@example.test`],
        );
      }
      for (const file of renderModules(["audit", "access"], {
        modules: {
          audit: { options: { restricted: true, readPolicy: true } },
        },
      }))
        if (file.kind === "schema" && file.module === "audit")
          await client.query(file.contents);
      await client.query(`
        create table public.${name} (id int primary key, organization_id uuid, title text);
        select better_supabase.audit('public.${name}', label_column => 'title');
        insert into better_supabase.organizations (id, name, slug) values ('${ACME}', 'Acme', 'acme-${RUN}') on conflict do nothing;
        insert into better_supabase.memberships (organization_id, user_id, role) values ('${ACME}', '${admin}', 'admin');
        insert into public.${name} values (1, '${ACME}', 'Draft');
        update public.${name} set title = 'Final' where id = 1;
      `);
      const transport = sqlTransport(sql);
      type Row = Record<string, unknown> & { id: number };
      const list = async (args: Record<string, unknown>): Promise<Row[]> =>
        // SAFETY: list_audit_events returns a jsonb array of entries.
        ((await transport.call("better_supabase", "list_audit_events", {
          max_items: 50,
          ...args,
        })) ?? []) as Row[];
      const reveal = (entry: number): Promise<unknown> =>
        transport.call("better_supabase", "reveal_audit_entry", {
          entry: String(entry),
        });
      claims = { sub: admin, role: "authenticated" };
      const entries = await list({
        for_tenant: ACME,
        for_target_type: name,
        max_items: 5,
      });
      expect(entries.map((item) => item["eventType"])).toEqual([
        `${name}.updated`,
        `${name}.created`,
      ]);
      expect(entries[0]).toMatchObject({
        targetLabel: "Final",
        scope: "tenant",
      });
      expect(entries[0]).not.toHaveProperty("old");
      const older = await list({
        for_tenant: ACME,
        for_target_type: name,
        before_at: entries[0]!["occurredAt"],
        before_id: entries[0]!.id,
      });
      expect(older.map((item) => item.id)).toEqual([entries[1]!.id]);
      expect(await reveal(entries[0]!.id)).toMatchObject({
        changes: { title: { old: "Draft", new: "Final" } },
      });
      claims = { role: "service_role" };
      const revealed = await list({
        for_event_type: "audit.revealed",
        max_items: 1,
      });
      expect(revealed[0]).toMatchObject({
        actorId: admin,
        record: String(entries[0]!.id),
      });
      claims = { sub: outsider, role: "authenticated" };
      expect(await list({ for_tenant: ACME, for_target_type: name })).toEqual(
        [],
      );
      await expect(reveal(entries[0]!.id)).rejects.toMatchObject({
        hint: "AUDIT_ENTRY_NOT_FOUND",
      });
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("guards, scopes, splits and retains audit entries by option", async () => {
    const name = `public.bs_audit_opt_${RUN}`;
    const other = "00000000-0000-4000-8000-0000000000aa";
    const hook = "public.audit_retention";
    await pool.query(
      moduleBody("audit", {
        modules: {
          audit: {
            options: {
              appendOnly: true,
              readPolicy: true,
              impersonators: "hide",
              restricted: true,
            },
          },
        },
      })!,
    );
    try {
      await pool.query(`
        create table ${name} (id int primary key, organization_id uuid, note text);
        select better_supabase.audit('${name}');
        insert into ${name} values (1, '${ACME}', 'a');
      `);
      const entry = await pool.query<{ id: string; new_record: unknown }>(
        "select id, new_record from better_supabase.audit_events where table_name = $1",
        [name],
      );
      expect(entry.rows[0]!.new_record).toBeNull();
      const details = await pool.query<{ new_record: { note: string } }>(
        "select new_record from better_supabase.audit_events_restricted where entry_id = $1",
        [entry.rows[0]!.id],
      );
      expect(details.rows[0]!.new_record.note).toBe("a");

      await expect(
        pool.query(
          "update better_supabase.audit_events set op = 'x' where table_name = $1",
          [name],
        ),
      ).rejects.toThrow(/append-only/);
      await expect(
        pool.query(
          "delete from better_supabase.audit_events where table_name = $1",
          [name],
        ),
      ).rejects.toThrow(/append-only/);
      const writer = await pool.connect();
      try {
        await writer.query("begin");
        await writer.query(
          "grant delete on better_supabase.audit_events to service_role",
        );
        await writer.query("set local role service_role");
        await writer.query(
          "select set_config('better_supabase.audit_purge', 'on', true)",
        );
        await expect(
          writer.query(
            "delete from better_supabase.audit_events where table_name = $1",
            [name],
          ),
        ).rejects.toThrow(/append-only/);
        await writer.query("rollback");
        await writer.query("begin");
        await expect(
          writer.query("truncate better_supabase.audit_events cascade"),
        ).rejects.toThrow(/append-only/);
      } finally {
        await writer.query("rollback");
        writer.release();
      }

      const privileges = await pool.query<{ column: string; allowed: boolean }>(
        `select c as column, has_column_privilege('authenticated', 'better_supabase.audit_events', c, 'select') as allowed
         from unnest(array['actor_id', 'impersonated_by']) c`,
      );
      expect(privileges.rows).toEqual([
        { column: "actor_id", allowed: true },
        { column: "impersonated_by", allowed: false },
      ]);
      const policy = await pool.query(
        "select 1 from pg_policies where schemaname = 'better_supabase' and tablename = 'audit_events' and policyname = 'bs_audit_read'",
      );
      expect(policy.rowCount).toBe(1);

      await pool.query(
        `insert into better_supabase.audit_events (table_name, op, organization_id, occurred_at)
         values ($1, 'insert', $2, now() - interval '40 days'),
                ($1, 'insert', $3, now() - interval '40 days')`,
        [`${name}_old`, ACME, other],
      );
      await pool.query(`
        create function ${hook}(tenant uuid) returns interval language sql stable as $$
          select case when tenant = '${ACME}' then interval '30 days' end
        $$;
      `);
      const purged = await pool.query<{ n: number }>(
        "select better_supabase.purge_audit_log('10 years') as n",
      );
      expect(purged.rows[0]!.n).toBe(1);
      const left = await pool.query<{ organization_id: string }>(
        "select organization_id from better_supabase.audit_events where table_name = $1",
        [`${name}_old`],
      );
      expect(left.rows).toEqual([{ organization_id: other }]);

      await pool.query(`drop function ${hook}(uuid)`);
      await pool.query(
        `insert into better_supabase.audit_events (table_name, op, occurred_at)
         values ($1, 'insert', now() - interval '40 days')`,
        [`${name}_old`],
      );
      const retained = await purgeAuditLog(postgres.admin, {
        olderThan: "10 years",
        retention: (tenant) => (tenant === ACME ? undefined : 30),
      });
      expect(retained.data).toBe(2);
      const none = await pool.query(
        "select 1 from better_supabase.audit_events where table_name = $1",
        [`${name}_old`],
      );
      expect(none.rowCount).toBe(0);
    } finally {
      await pool.query(`drop function if exists ${hook}(uuid)`);
      await pool.query(`select better_supabase.unaudit('${name}')`);
      await pool.query(`drop table if exists ${name}`);
      await pool.query(SQL_MODULES["audit"]!.sql);
      await pool.query(deleteAudit("table_name like $1"), [`${name}%`]);
      await pool.query(
        "drop policy if exists bs_audit_read on better_supabase.audit_events",
      );
      await pool.query(
        "revoke all on better_supabase.audit_events from authenticated",
      );
    }
  });

  it("pgTAP helpers authenticate as a user under RLS", async () => {
    const client = await pool.connect();
    try {
      await client.query("begin");
      const installed = await client.query<{ pass: string }>(
        SQL_MODULES["pgtap"]!.sql,
      );
      expect(JSON.stringify(installed)).toContain("ok 1");
      const user = await client.query<{ id: string }>(
        `select tests.create_user($1) as id`,
        [`pgtap-${RUN}@example.com`],
      );
      await client.query(`select tests.authenticate_as($1, $2)`, [
        user.rows[0]!.id,
        JSON.stringify({ tenant_id: ACME }),
      ]);
      const visible = await client.query<{ n: number }>(
        `select count(*)::int as n from public.customers where organization_id <> $1`,
        [ACME],
      );
      expect(visible.rows[0]!.n).toBe(0);
      await client.query("select tests.clear_authentication()");
      const rls = await client.query<{ result: string }>(
        `select tests.rls_enabled('public') as result`,
      );
      expect(rls.rows[0]!.result).toMatch(/^not ok/);
      expect(rls.rows[0]!.result).toContain(`bs_block_${RUN}`);
      await client.query(`alter table ${table} enable row level security`);
      const fixed = await client.query<{ result: string }>(
        `select tests.rls_enabled('public') as result`,
      );
      expect(fixed.rows[0]!.result).toMatch(/^ok/);

      await client.query("savepoint as_anon");
      await client.query("select tests.authenticate_as_anon()");
      await expect(
        client.query(`select tests.create_user($1)`, [
          `anon-${RUN}@example.com`,
        ]),
      ).rejects.toMatchObject({ code: "42501" });
      await client.query("rollback to savepoint as_anon");
      await client.query("select tests.authenticate_as($1)", [
        user.rows[0]!.id,
      ]);
      await expect(
        client.query(`select tests.create_user($1)`, [
          `member-${RUN}@example.com`,
        ]),
      ).rejects.toMatchObject({ code: "42501" });
      await client.query("rollback to savepoint as_anon");
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("asUser runs PostgREST and SQL as the same user", async () => {
    const betterSupabase = defineSupabase(schema);
    const alice = await asUser(
      betterSupabase,
      { sub: crypto.randomUUID(), tenant_id: ACME },
      { url, publishableKey, postgres },
    );
    const rest = await alice.db.customers.count().orThrow();
    const sql = await alice.sql!.customers.count().orThrow();
    expect(rest).toBe(sql);
    expect(rest).toBeGreaterThan(0);
    const stranger = await asUser(
      betterSupabase,
      { sub: crypto.randomUUID() },
      { url, publishableKey },
    );
    expect(await stranger.db.customers.count().orThrow()).toBe(0);
  });

  it("read sets run as one GET and one transaction, under RLS", async () => {
    const betterSupabase = defineSupabase(schema);
    const chrome = defineReadSet(
      betterSupabase,
      `block_${RUN}`,
      { params: { organizationId: "uuid", kinds: "public.note_kind[]" } },
      (s, p) => ({
        customers: s.customers.count({
          where: { organizationId: p.organizationId },
        }),
        notes: s.notes.findMany({
          select: ["id", "kind", "customerId"],
          where: {
            organizationId: p.organizationId,
            kind: { in: p.kinds as readonly ("call" | "meeting")[] },
          },
          orderBy: { id: "asc" },
        }),
        organization: s.organizations.findFirst({
          select: ["id", "name"],
          where: { id: p.organizationId },
        }),
        busiest: s.customers.findFirst({
          select: ["id"],
          include: { _count: { notes: true } },
          where: { organizationId: p.organizationId },
          orderBy: { name: "asc" },
        }),
      }),
    );
    const [file] = renderModules(["read-sets"], {
      readSets: [await compileReadSet(chrome)],
    });
    await pool.query(file!.contents);
    await pool.query(`notify pgrst, 'reload schema'`);

    try {
      const alice = await asUser(
        betterSupabase,
        { sub: crypto.randomUUID(), tenant_id: ACME },
        { url, publishableKey, postgres },
      );
      const params = { organizationId: ACME, kinds: ["call", "meeting"] };
      let rest = await alice.db.$many(chrome, params);
      for (let attempt = 0; !rest.ok && attempt < 20; attempt += 1) {
        await new Promise((resolve) => {
          setTimeout(resolve, 250);
        });
        rest = await alice.db.$many(chrome, params);
      }
      expect(rest.error).toBeNull();
      const sql = await alice.sql!.$many(chrome, params).orThrow();
      expect(rest.data).toEqual(sql);

      const separate = {
        customers: await alice.db.customers
          .count({ where: { organizationId: ACME } })
          .orThrow(),
        organization: await alice.db.organizations
          .findFirst({ select: ["id", "name"], where: { id: ACME } })
          .orThrow(),
      };
      await expect(
        alice.db.$run(chrome.specs.organization).orThrow(),
      ).rejects.toThrow(/placeholders/);
      expect(separate).toEqual({
        customers: rest.data!.customers,
        organization: rest.data!.organization,
      });
      expect(rest.data!.customers).toBeGreaterThan(0);
      expect(rest.data!.organization).toMatchObject({ id: ACME });
      expect(rest.data!.busiest?._count.notes).toEqual(expect.any(Number));

      const stranger = await asUser(
        betterSupabase,
        { sub: crypto.randomUUID() },
        { url, publishableKey, postgres },
      );
      const hidden = await stranger.db.$many(chrome, params).orThrow();
      expect(hidden).toEqual({
        customers: 0,
        notes: [],
        organization: null,
        busiest: null,
      });
    } finally {
      await pool.query(`drop function if exists public.rs_block_${RUN}(jsonb)`);
    }
  });

  it("db.$many batches ad-hoc specs in one SQL transaction", async () => {
    const betterSupabase = defineSupabase(schema);
    const alice = await asUser(
      betterSupabase,
      { sub: crypto.randomUUID(), tenant_id: ACME },
      { url, publishableKey, postgres },
    );
    const specs = [
      betterSupabase.spec.customers.count(),
      betterSupabase.spec.notes.findMany({
        select: ["id"],
        orderBy: { id: "asc" },
      }),
    ] as const;
    const rest = await alice.db.$many(specs).orThrow();
    const sql = await alice.sql!.$many(specs).orThrow();
    expect(sql).toEqual(rest);
    expect(rest[0]).toBeGreaterThan(0);
  });

  it("searches the nearest rows the caller can read", async () => {
    const name = `bs_chunks_${RUN}`;
    const mine = crypto.randomUUID();
    const theirs = crypto.randomUUID();
    const column = (db: string, type: string) => ({
      db,
      type,
      nullable: false,
      hasDefault: false,
    });
    const table = (key: string, db: string) => ({
      key,
      name: db,
      schema: "public",
      kind: "table" as const,
      columns: {
        id: column("id", "int4"),
        organizationId: column("org_id", "uuid"),
        content: column("content", "text"),
      },
      primaryKey: ["id"],
      uniqueKeys: {},
      relations: {},
      flags: {},
    });
    const betterSupabase = defineSupabase(
      defineSchema<AnyModels>({
        version: 1,
        casing: "camel",
        tables: {
          chunks: table("chunks", name),
          unsearched: table("unsearched", `bs_unsearched_${RUN}`),
        },
        enums: {},
        functions: {},
      }),
    );
    const rows = [
      ...Array.from(
        { length: 20 },
        (_, i) => `(${i + 1}, '${theirs}', 'x', '[1,${i / 100},0]')`,
      ),
      `(101, '${mine}', 'a', '[0,1,0]')`,
      `(102, '${mine}', 'b', '[0.5,0.5,0]')`,
      `(103, '${mine}', 'c', '[0.9,0.1,0]')`,
    ];
    const [module] = renderModules(["vector-search"], {
      vectorSearch: [{ table: name, column: "embedding", distance: "cosine" }],
    });
    try {
      await pool.query(`
        create extension if not exists vector with schema extensions;
        create table public.${name} (
          id int primary key, org_id uuid not null, content text not null,
          embedding extensions.vector(3)
        );
        insert into public.${name} values ${rows.join(", ")};
        create index on public.${name} using hnsw (embedding extensions.vector_cosine_ops);
        alter table public.${name} enable row level security;
        create policy "own organization" on public.${name} for select to authenticated
          using (org_id = (auth.jwt() ->> 'tenant_id')::uuid);
        grant select on public.${name} to authenticated;
      `);
      await pool.query(module!.contents);
      await pool.query(`notify pgrst, 'reload schema'`);
      const alice = await asUser(
        betterSupabase,
        { sub: crypto.randomUUID(), tenant_id: mine },
        { url, publishableKey, postgres },
      );
      const query = { vector: [1, 0, 0], k: 2, select: ["id", "content"] };
      // The ad-hoc schema is untyped (`AnyModels`), so the args are too.
      const search = (
        db: Pick<typeof alice.db, "$search">,
        table: "chunks" | "unsearched",
        args: object = query,
      ) => db.$search(table, args as never);
      await expect
        .poll(async () => (await search(alice.db, "chunks")).ok, {
          timeout: 10_000,
        })
        .toBe(true);

      const rest = await search(alice.db, "chunks").orThrow();
      expect(rest).toEqual([
        { id: 103, content: "c" },
        { id: 102, content: "b" },
      ]);
      const sql = await search(alice.sql!, "chunks").orThrow();
      expect(sql).toEqual(rest);
      const filtered = await search(alice.db, "chunks", {
        ...query,
        k: 3,
        where: { content: "a" },
      }).orThrow();
      expect(filtered).toEqual([{ id: 101, content: "a" }]);
      for (const db of [alice.db, alice.sql!]) {
        const scored = (await search(db, "chunks", {
          ...query,
          score: true,
        }).orThrow()) as { id: number; $score: number }[];
        expect(scored.map((row) => row.id)).toEqual([103, 102]);
        expect(scored[0]!.$score).toBeGreaterThan(scored[1]!.$score);
      }

      const missing = await search(alice.db, "unsearched");
      expect(missing.ok).toBe(false);
      expect(missing.error?.hint).toContain("vectorSearch");
    } finally {
      await pool.query(`drop table if exists public.${name} cascade`);
      await pool.query(
        `drop function if exists public.search_${name}(extensions.vector, integer);
         drop function if exists public.search_${name}_scores(extensions.vector, integer)`,
      );
    }
  });

  it("fuses full-text and halfvec rankings with prefilters and a boost", async () => {
    const name = `bs_hybrid_${RUN}`;
    const column = (db: string, type: string) => ({
      db,
      type,
      nullable: true,
      hasDefault: false,
    });
    const betterSupabase = defineSupabase(
      defineSchema<AnyModels>({
        version: 1,
        casing: "camel",
        tables: {
          chunks: {
            key: "chunks",
            name,
            schema: "public",
            kind: "table" as const,
            columns: {
              id: column("id", "int4"),
              content: column("content", "text"),
            },
            primaryKey: ["id"],
            uniqueKeys: {},
            relations: {},
            flags: {},
          },
        },
        enums: {},
        functions: {},
      }),
    );
    const [module] = renderModules(["vector-search"], {
      vectorSearch: [
        {
          table: name,
          column: "embedding",
          distance: "cosine",
          type: "halfvec",
          hybrid: { tsvector: "tsv" },
          boost: "t.priority",
          prefilter: ["collection"],
        },
      ],
    });
    try {
      await pool.query(`
        create extension if not exists vector with schema extensions;
        create table public.${name} (
          id int primary key, collection text, content text not null,
          priority double precision not null default 1,
          embedding extensions.halfvec(3),
          tsv tsvector generated always as (to_tsvector('simple', content)) stored
        );
        insert into public.${name} (id, collection, content, priority, embedding) values
          (1, 'a', 'apple pie', 1, '[1,0,0]'),
          (2, 'a', 'banana bread', 1, '[0.9,0.1,0]'),
          (3, 'b', 'apple tart', 1, '[1,0,0]'),
          (4, null, 'apple crumble', 3, '[0,1,0]');
        alter table public.${name} enable row level security;
        create policy "everyone" on public.${name} for select to authenticated using (true);
        grant select on public.${name} to authenticated;
      `);
      await pool.query(module!.contents);
      await pool.query(`notify pgrst, 'reload schema'`);
      const alice = await asUser(
        betterSupabase,
        { sub: crypto.randomUUID() },
        { url, publishableKey, postgres },
      );
      const args = {
        vector: [1, 0, 0],
        k: 3,
        text: "apple",
        filter: { collection: ["a", null] },
        select: ["id"],
      };
      await expect
        .poll(
          async () => (await alice.db.$search("chunks", args as never)).ok,
          { timeout: 10_000 },
        )
        .toBe(true);
      for (const db of [alice.db, alice.sql!]) {
        expect(await db.$search("chunks", args as never).orThrow()).toEqual([
          { id: 4 },
          { id: 1 },
          { id: 2 },
        ]);
        const scored = (await db
          .$search("chunks", { ...args, score: true } as never)
          .orThrow()) as { id: number; $score: number }[];
        expect(scored.map((row) => row.id)).toEqual([4, 1, 2]);
        expect(scored[0]!.$score).toBeGreaterThan(scored[1]!.$score);
      }
    } finally {
      await pool.query(`drop table if exists public.${name} cascade`);
      await pool.query(
        `drop function if exists public.search_${name}(extensions.halfvec, integer, jsonb, text);
         drop function if exists public.search_${name}_scores(extensions.halfvec, integer, jsonb, text)`,
      );
    }
  });

  it("limits route handler keys with hit_rate_limit", async () => {
    const scope = `route-${RUN}`;
    const limit = createRateLimit(postgres.admin);
    try {
      await pool.query(
        "select better_supabase.set_rate_limit($1, 2, interval '1 minute')",
        [scope],
      );
      const hits = [];
      for (let i = 0; i < 3; i += 1)
        hits.push(await limit.check(scope, "token-a").orThrow());
      expect(hits.map((hit) => [hit.allowed, hit.remaining])).toEqual([
        [true, 1],
        [true, 0],
        [false, 0],
      ]);
      expect(hits[2]!.retryAfter).toBeGreaterThan(0);
      expect((await limit.check(scope, "token-b").orThrow()).allowed).toBe(
        true,
      );
      const adhoc = await limit
        .check(`adhoc-${RUN}`, "thread-1", { max: 1, period: "1 hour" })
        .orThrow();
      expect(adhoc.allowed).toBe(true);
      expect(await limit.check(`none-${RUN}`, "k")).toMatchObject({
        ok: false,
        error: { hint: "RATE_LIMIT_UNKNOWN" },
      });
      expect(
        (
          await pool.query<{ allowed: boolean }>(
            "select has_function_privilege('authenticated', 'better_supabase.hit_rate_limit(text, text, integer, interval)', 'execute') as allowed",
          )
        ).rows[0]!.allowed,
      ).toBe(false);
    } finally {
      await pool.query("select better_supabase.set_rate_limit($1, null)", [
        scope,
      ]);
      await pool.query(
        "delete from better_supabase.rate_limits where scope = $1",
        [`adhoc-${RUN}`],
      );
    }
  });

  it("answers writes over the limit with 429 and Retry-After", async () => {
    const probe = `bs_rate_probe_${RUN}`;
    const scope = `/rpc/${probe}`;
    const token = await signLocalJwt({ sub: crypto.randomUUID() });
    const call = (method: "GET" | "POST") =>
      fetch(`${url}/rest/v1/rpc/${probe}`, {
        method,
        headers: {
          apikey: publishableKey,
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        ...(method === "POST" ? { body: "{}" } : {}),
      });
    try {
      await pool.query(`
        create function public.${probe}() returns integer language sql as 'select 1';
        grant execute on function public.${probe}() to authenticated;
        notify pgrst, 'reload schema';
      `);
      await expect
        .poll(async () => (await call("GET")).status, { timeout: 10_000 })
        .toBe(200);
      const { rows } = await pool.query(
        `select setting from pg_db_role_setting s join pg_roles r on r.oid = s.setrole,
           unnest(s.setconfig) setting
         where r.rolname = 'authenticator' and setting like 'pgrst.db_pre_request=%'`,
      );
      expect(rows[0]?.setting).toBe(
        "pgrst.db_pre_request=better_supabase.check_request",
      );
      await pool.query(
        `select better_supabase.set_rate_limit($1, 2, interval '1 minute')`,
        [scope],
      );

      expect((await call("POST")).status).toBe(200);
      expect((await call("POST")).status).toBe(200);
      const limited = await call("POST");
      expect(limited.status).toBe(429);
      const retryAfter = Number(limited.headers.get("retry-after"));
      expect(retryAfter).toBeGreaterThan(0);
      expect(retryAfter).toBeLessThanOrEqual(60);
      const error = mapDbError((await limited.json()) as RawDbError);
      expect(error).toMatchObject({
        kind: "rate_limited",
        status: 429,
        code: "BS429",
        retryAfter,
      });
      expect((await call("GET")).status).toBe(200);

      await pool.query(
        `insert into better_supabase.rate_limits (scope, key, window_start, hits)
         values ($1, 'expired', now() - interval '2 minutes', 1)`,
        [scope],
      );
      await pool.query(`select better_supabase.purge_rate_limits()`);
      const { rows: counters } = await pool.query<{ key: string }>(
        `select key from better_supabase.rate_limits where scope = $1`,
        [scope],
      );
      expect(counters.map((row) => row.key)).not.toContain("expired");
      expect(counters).toHaveLength(1);

      await pool.query(`select better_supabase.set_rate_limit($1, null)`, [
        scope,
      ]);
      expect((await call("POST")).status).toBe(200);
    } finally {
      await pool.query(`select better_supabase.set_rate_limit($1, null)`, [
        scope,
      ]);
      await pool.query(`drop function if exists public.${probe}()`);
    }
  });
});
