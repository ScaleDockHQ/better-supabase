import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { LiveDatabase } from "../../../src/cli/doctor/live.ts";
import type { IntrospectionSource } from "../../../src/cli/introspect/source.ts";
import type { Snapshot } from "../../../src/cli/introspect/types.ts";
import type { AuthorizationProvider } from "../../../src/config/index.ts";

import {
  type DoctorContext,
  RULES,
  runRules,
} from "../../../src/cli/doctor/rules.ts";
import { introspect } from "../../../src/cli/introspect/index.ts";
import { pgSource } from "../../../src/cli/introspect/source.ts";
import { parseToml } from "../../../src/cli/supabase-toml.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import {
  stubProvider,
  withProvider,
} from "../../fixtures/authorization-provider.ts";

const dbUrl =
  process.env["SUPABASE_DB_URL"] ??
  "postgresql://postgres:postgres@127.0.0.1:55422/postgres";
const SCHEMA = `bs_doctor_${Date.now()}`;
const ORG = "00000000-0000-4000-8000-000000000001";

async function open(): Promise<IntrospectionSource | undefined> {
  try {
    const source = await pgSource(dbUrl);
    await source.queryable.query("select 1");
    return source;
  } catch {
    return undefined;
  }
}

const source = await open();

describe.skipIf(!source)("doctor against the local stack", () => {
  const db = source!;
  let snapshot: Snapshot;
  const database: LiveDatabase = {
    describe: "local stack",
    session: true,
    async query<R>(sql: string) {
      return (await db.queryable.query(sql)).rows as R[];
    },
  };
  const context = (extra: Partial<DoctorContext> = {}): DoctorContext => ({
    config: resolveConfig({ schemas: [SCHEMA] }, "/project"),
    snapshot,
    configToml: undefined,
    envFiles: [],
    gitignore: "",
    sources: [],
    database,
    ...extra,
  });
  const only = (...codes: string[]) =>
    RULES.filter((rule) => codes.includes(rule.code));

  beforeAll(async () => {
    await db.queryable.query(`
      create schema ${SCHEMA};
      create table ${SCHEMA}.projects (
        id uuid primary key default gen_random_uuid(),
        org_id uuid not null
      );
      alter table ${SCHEMA}.projects enable row level security;
      create function ${SCHEMA}.is_member(organization uuid) returns boolean
        language plpgsql stable set search_path = ''
        as $$ begin return organization = ((current_setting('request.jwt.claims', true))::jsonb->>'org_id')::uuid; end $$;
      create policy projects_member on ${SCHEMA}.projects for select to authenticated
        using (${SCHEMA}.is_member(org_id));
      create policy projects_open on ${SCHEMA}.projects for select to public
        using (false);
      grant usage on schema ${SCHEMA} to anon, authenticated;
      grant select on ${SCHEMA}.projects to authenticated;
      grant execute on function ${SCHEMA}.is_member(uuid) to authenticated;
      insert into ${SCHEMA}.projects (org_id)
        select '${ORG}'::uuid from generate_series(1, 20);
      create table ${SCHEMA}.members (
        org_id uuid not null,
        user_id uuid not null,
        role text not null,
        note text,
        primary key (org_id, user_id)
      );
      alter table ${SCHEMA}.members enable row level security;
      create function ${SCHEMA}.is_admin(organization uuid) returns boolean
        language sql stable security definer set search_path = ''
        as $$ select exists (
          select 1 from ${SCHEMA}.members m
          where m.org_id = organization and m.user_id = auth.uid() and m.role = 'admin'
        ) $$;
      create policy members_read on ${SCHEMA}.members for select to authenticated
        using ((select ${SCHEMA}.is_admin(org_id)));
      create policy members_own on ${SCHEMA}.members for update to authenticated
        using (user_id = (select auth.uid()));
      grant select on ${SCHEMA}.members to authenticated;
      grant update (role, note) on ${SCHEMA}.members to authenticated;
      create table ${SCHEMA}.audit_events (
        id bigint generated always as identity primary key,
        payload jsonb not null
      );
      alter table ${SCHEMA}.audit_events enable row level security;
      revoke all on ${SCHEMA}.audit_events from public, anon, authenticated;
      grant select, insert on ${SCHEMA}.audit_events to service_role;
    `);
    snapshot = await introspect(db.queryable, [SCHEMA]);
  });

  afterAll(async () => {
    await db.queryable.query(`drop schema if exists ${SCHEMA} cascade`);
    await db.close();
  });

  it("reads the functions a policy calls from pg_depend", () => {
    const table = snapshot.extras.tables.find(
      (entry) => entry.name === "projects",
    )!;
    expect(
      table.policies.map((policy) => [policy.name, policy.functions]),
    ).toEqual([
      ["projects_member", [`${SCHEMA}.is_member`]],
      ["projects_open", []],
    ]);
    expect(snapshot.extras.functions).toContainEqual({
      schema: SCHEMA,
      name: "is_member",
      signature: "organization uuid",
      language: "plpgsql",
      volatility: "stable",
      securityDefiner: false,
      settings: { search_path: '""' },
      execute: ["anon", "authenticated"],
    });
  });

  it("flags the per-row helper and the overlapping policies", async () => {
    const findings = await runRules(context(), only("BS205", "BS207"));
    expect(findings).toMatchObject([
      // Postgres never inlines a security definer function.
      {
        code: "BS205",
        message: expect.stringContaining(
          `${SCHEMA}.is_admin(org_id), a security definer function`,
        ),
      },
      {
        code: "BS205",
        message: expect.stringContaining(`${SCHEMA}.is_member(org_id)`),
      },
      {
        code: "BS207",
        message: expect.stringContaining(
          "select for authenticated: projects_member, projects_open",
        ),
      },
    ]);
  });

  it("reads column grants and flags a role column members may update (BS213)", async () => {
    const members = snapshot.extras.tables.find(
      (entry) => entry.name === "members",
    )!;
    expect(members.columnGrants).toEqual([
      { column: "note", role: "authenticated", privileges: ["UPDATE"] },
      { column: "role", role: "authenticated", privileges: ["UPDATE"] },
    ]);
    const findings = await runRules(context(), only("BS213"));
    expect(findings).toMatchObject([
      {
        code: "BS213",
        target: `${SCHEMA}.members`,
        message: expect.stringContaining(
          `authenticated may update role. ${SCHEMA}.is_admin reads them`,
        ),
      },
    ]);
    expect(findings[0]!.message).toContain(
      `revoke update (role) on ${SCHEMA}.members from authenticated;`,
    );
  });

  it("accepts a service-role table and flags one the Data API reaches (BS106)", async () => {
    const config = (serviceRole: readonly string[]) =>
      resolveConfig(
        {
          schemas: [SCHEMA],
          tables: Object.fromEntries(
            serviceRole.map((name) => [name, { serviceRole: true }]),
          ),
        },
        "/project",
      );
    const targets = async (serviceRole: readonly string[]) =>
      (
        await runRules(context({ config: config(serviceRole) }), only("BS106"))
      ).map((finding) => finding.target);

    expect(await targets([])).toEqual([`${SCHEMA}.audit_events:authenticated`]);
    expect(await targets(["audit_events"])).toEqual([]);
    expect(await targets(["audit_events", "projects"])).toEqual([
      `${SCHEMA}.projects:authenticated`,
    ]);
  });

  it("reads statistics without failing", async () => {
    const findings = await runRules(
      context({ stats: true }),
      only("BS208", "BS209"),
    );
    for (const finding of findings)
      expect(finding.message).not.toMatch(/^Could not read/);
  });

  it("plans a table under RLS as the given claims and rolls back", async () => {
    const [finding] = await runRules(
      context({
        explain: {
          tables: ["projects"],
          claims: { role: "authenticated", org_id: ORG },
        },
      }),
      only("BS212"),
    );
    expect(finding).toMatchObject({
      code: "BS212",
      target: `${SCHEMA}.projects:explain`,
      message: expect.stringMatching(
        new RegExp(
          `^${SCHEMA}\\.projects as authenticated: .* ms, .*Seq Scan on projects.*${SCHEMA}\\.is_member .* over 20 calls`,
        ),
      ),
    });
    // The role and claims were local to the rolled-back transaction.
    const [who] = (
      await db.queryable.query(
        `select current_user as role, current_setting('request.jwt.claims', true) as claims`,
      )
    ).rows as { role: string; claims: string | null }[];
    expect(who).toEqual({
      role: "postgres",
      claims: expect.toBeOneOf(["", null]),
    });
  });
});

const hookSource = await open();

describe.skipIf(!hookSource)(
  "doctor Auth hooks against the local stack",
  () => {
    const db = hookSource!;
    const HOOKS = `bs_doctor_hooks_${Date.now()}`;
    const USER = crypto.randomUUID();
    const database: LiveDatabase = {
      describe: "local stack",
      session: true,
      async query<R>(sql: string) {
        return (await db.queryable.query(sql)).rows as R[];
      },
    };
    const toml = (fn: string) => {
      const text = `[auth.hook.custom_access_token]
enabled = true
uri = "pg-functions://postgres/${HOOKS}/${fn}"
`;
      return {
        path: "supabase/config.toml",
        dir: "supabase",
        text,
        document: parseToml(text),
        parser: "smol-toml" as const,
      };
    };
    const run = async (
      fn: string,
      codes: string[],
      hookUser?: string,
      authorization?: AuthorizationProvider,
    ) => {
      const snapshot = await introspect(db.queryable, ["public"], {
        hooks: [{ hook: "custom_access_token", schema: HOOKS, name: fn }],
      });
      return runRules(
        {
          config: resolveConfig(
            {
              schemas: ["public"],
              ...(authorization ? { authorization } : {}),
            },
            "/project",
          ),
          snapshot,
          configToml: toml(fn),
          envFiles: [],
          gitignore: "",
          sources: [],
          database,
          ...(hookUser ? { hookUser } : {}),
        },
        RULES.filter((rule) => codes.includes(rule.code)),
      );
    };

    beforeAll(async () => {
      await db.queryable.query(`
      create schema ${HOOKS};
      create function ${HOOKS}.good(event jsonb) returns jsonb
        language plpgsql stable set search_path = ''
        as $$ begin
          return jsonb_set(event, '{claims,profile}', to_jsonb(repeat('x', 3000)));
        end $$;
      grant usage on schema ${HOOKS} to supabase_auth_admin;
      grant execute on function ${HOOKS}.good(jsonb) to supabase_auth_admin;
      revoke execute on function ${HOOKS}.good(jsonb) from authenticated, anon, public;
      create function ${HOOKS}.bad(event jsonb) returns jsonb
        language plpgsql
        as $$ begin return event; end $$;
      -- A provider-shaped token: about 1.5 KB of token, memberships and attrs within 1024.
      create function ${HOOKS}.provider_fits(event jsonb) returns jsonb
        language plpgsql stable set search_path = ''
        as $$ begin
          event := jsonb_set(event, '{claims,memberships}', jsonb_build_array(
            jsonb_build_object('scope', 'organization', 'id', repeat('a', 300), 'roles', jsonb_build_array('admin'))));
          event := jsonb_set(event, '{claims,attrs}', jsonb_build_object('plan', repeat('p', 200)));
          return jsonb_set(event, '{claims,profile}', to_jsonb(repeat('x', 500)));
        end $$;
      -- Memberships and attrs over 1024, the whole token under 2048.
      create function ${HOOKS}.provider_over(event jsonb) returns jsonb
        language plpgsql stable set search_path = ''
        as $$ begin
          event := jsonb_set(event, '{claims,memberships}', jsonb_build_array(
            jsonb_build_object('scope', 'organization', 'id', repeat('a', 800), 'roles', jsonb_build_array('admin'))));
          return jsonb_set(event, '{claims,attrs}', jsonb_build_object('plan', repeat('p', 300)));
        end $$;
      grant usage on schema ${HOOKS} to supabase_auth_admin;
      grant execute on function ${HOOKS}.provider_fits(jsonb), ${HOOKS}.provider_over(jsonb) to supabase_auth_admin;
      revoke execute on function ${HOOKS}.provider_fits(jsonb), ${HOOKS}.provider_over(jsonb) from authenticated, anon, public;
      insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data)
        values ('${USER}', 'authenticated', 'authenticated', 'hook-${USER}@example.com', '{}', '{}');
    `);
    });

    afterAll(async () => {
      await db.queryable.query(`
      delete from auth.users where id = '${USER}';
      drop schema if exists ${HOOKS} cascade;
    `);
      await db.close();
    });

    it("introspects hook functions outside the configured schemas", async () => {
      const snapshot = await introspect(db.queryable, ["public"], {
        hooks: [{ hook: "custom_access_token", schema: HOOKS, name: "good" }],
      });
      expect(snapshot.extras.hooks).toEqual([
        {
          hook: "custom_access_token",
          schema: HOOKS,
          name: "good",
          functions: [
            expect.objectContaining({
              signature: "event jsonb",
              volatility: "stable",
              settings: { search_path: '""' },
              execute: ["supabase_auth_admin"],
              publicExecute: false,
              schemaUsage: ["supabase_auth_admin"],
            }),
          ],
        },
      ]);
    });

    it("flags default grants and a volatile hook without search_path", async () => {
      const findings = await run("bad", ["BS404", "BS405"]);
      expect(findings.map((finding) => finding.code)).toEqual([
        "BS404",
        "BS405",
      ]);
      // `public` may execute a new function, so Auth can call it, and so can everyone else.
      expect(findings[0]!.message).toContain(
        "authenticated, anon, public may execute it",
      );
      expect(findings[0]!.message).toContain(
        `revoke execute on function ${HOOKS}.bad(event jsonb) from authenticated, anon, public;`,
      );
      expect(await run("good", ["BS404", "BS405"])).toEqual([]);
    });

    it("calls the hook as supabase_auth_admin for --as and measures the claims", async () => {
      const findings = await run("good", ["BS405"], USER);
      expect(findings).toMatchObject([
        {
          code: "BS405",
          severity: "warning",
          message: expect.stringMatching(/returns \d{4} bytes of claims/),
        },
      ]);
      const [who] = (await db.queryable.query("select current_user as role"))
        .rows as { role: string }[];
      expect(who?.role).toBe("postgres");
    });

    it("measures the provider's hook budget apart from the whole token", async () => {
      const provider = withProvider({
        tokenHook: {
          ...stubProvider.tokenHook,
          budget: { claims: ["memberships", "attrs"], bytes: 1024 },
        },
      });
      expect(await run("provider_fits", ["BS405"], USER, provider)).toEqual([]);
      const findings = await run("provider_over", ["BS405"], USER, provider);
      expect(findings).toMatchObject([
        {
          code: "BS405",
          message: expect.stringMatching(
            /returns \d{4} bytes of memberships and attrs .*over the hook's budget of 1024/,
          ),
        },
      ]);
      expect(await run("provider_over", ["BS405"], USER)).toEqual([]);
    });
  },
);
