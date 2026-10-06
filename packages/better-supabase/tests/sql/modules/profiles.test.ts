import { describe, expect, it } from "vitest";

import type { ModulesConfig } from "../../../src/config/modules.ts";

import {
  moduleBody,
  renderModules,
  resolveModules,
} from "../../../src/sql/registry.ts";

const CENTRAKIT: ModulesConfig = {
  profiles: {
    mode: "adopt",
    tables: { profiles: "public.profiles" },
    columns: {
      profiles: {
        key: "user_id",
        fullName: null,
        avatar: "avatar_path",
        activeTenant: "active_organization_id",
        onboarding: null,
      },
    },
    hooks: {
      schema: "public",
      functions: { after_profile_sync: "create_contact_profile" },
    },
    options: {
      syncTrigger: false,
      usernameMaxLength: 30,
      metadata: { first_name: "first_name", last_name: "last_name" },
    },
  },
};

const body = (modules: ModulesConfig) => moduleBody("profiles", { modules })!;

describe("profiles module", () => {
  it("owns its table with grants, a guard and the auth triggers", () => {
    const sql = body({});
    expect(sql).toContain(
      'create table if not exists "better_supabase"."profiles" (',
    );
    expect(sql).toContain(
      'grant update ("full_name", "first_name", "last_name", "avatar_url", "username", "onboarding", "updated_at") on "better_supabase"."profiles" to authenticated;',
    );
    expect(sql).toContain("hint = 'PROFILE_COLUMN_READONLY'");
    expect(sql).toContain(
      'new."active_organization_id" is distinct from old."active_organization_id"',
    );
    expect(sql).toContain(
      'create trigger "bs_profile_sync" after insert on auth.users',
    );
    expect(sql).toContain(
      'create trigger "bs_profile_email" after update of email on auth.users',
    );
    expect(sql).toContain("meta ->> 'full_name', meta ->> 'name'");
    expect(sql).toContain('"better_supabase"."allocate_username"(');
    expect(sql).toContain("add constraint profiles_username_check check (");
    expect(sql).toContain("lower(\"username\") <> all (array['admin'");
    expect(sql).toContain("while candidate = any(array['admin'");
    expect(sql).toMatch(
      /if created then\s+if to_regprocedure\('"public"\."after_profile_sync"\(uuid\)'\)/,
    );
    expect(sql).toContain(
      "exception when others then\n    raise warning 'No profile for user %",
    );
    expect(sql).toContain('"id" = (select auth.uid())');
  });

  it("adopts CentraKit's profiles without touching its table or grants", () => {
    const sql = body(CENTRAKIT);
    expect(sql).not.toContain("create table");
    expect(sql).not.toContain("revoke update");
    expect(sql).toContain(
      'insert into "public"."profiles" ("user_id", "first_name", "last_name", "email", "username")',
    );
    expect(sql).toContain(
      `left(regexp_replace(lower(coalesce(base, '')), '[^a-z0-9_]+', '', 'g'), 26)`,
    );
    expect(sql).toContain(
      'drop trigger if exists "bs_profile_sync" on auth.users;',
    );
    expect(sql).toContain(
      `to_regprocedure('"public"."create_contact_profile"(uuid)')`,
    );
    expect(sql).toContain('new."active_organization_id" is distinct from');
    expect(sql).not.toContain("onboarding");
  });

  it("adds extra columns and a members read policy", () => {
    const sql = renderModules(["tenant", "profiles"], {
      modules: {
        profiles: {
          options: {
            extraColumns: { locale: "text not null default 'en'" },
            readPolicy: "members",
          },
        },
      },
    }).findLast((file) => file.kind === "schema")!.contents;
    expect(sql).toContain(
      `alter table "better_supabase"."profiles" add column if not exists "locale" text not null default 'en';`,
    );
    expect(sql).toContain('"locale", "updated_at") on');
    expect(sql).toContain(
      '"id" in (select "better_supabase"."profile_peer_ids"())',
    );
    expect(sql).toContain(
      'revoke select on "better_supabase"."profiles" from authenticated;',
    );
    const grant =
      /grant select \(([^)]*)\) on "better_supabase"\."profiles"/.exec(
        sql,
      )?.[1];
    expect(grant).toContain('"username"');
    expect(grant).toContain('"locale"');
    expect(grant).not.toContain('"email"');
    expect(sql).toContain('"better_supabase"."my_profile"()');
  });

  it("honours updatable, serviceColumns and turning features off", () => {
    const sql = body({
      profiles: {
        columns: { profiles: { email: null } },
        options: {
          updatable: ["full_name"],
          serviceColumns: [],
          username: false,
          splitName: false,
        },
      },
    });
    expect(sql).toContain(
      'grant update ("full_name", "updated_at") on "better_supabase"."profiles" to authenticated;',
    );
    expect(sql).toContain('drop trigger if exists "bs_profile_guard"');
    expect(sql).not.toContain('allocate_username"(coalesce');
    expect(sql).not.toContain("split_part(nullif");
    expect(sql).toContain(
      'drop trigger if exists "bs_profile_email" on auth.users;',
    );
  });

  it("writes nothing in custom mode", () => {
    expect(
      moduleBody("profiles", { modules: { profiles: { mode: "custom" } } }),
    ).toBeUndefined();
  });

  it("rejects bad options", () => {
    expect(() =>
      body({ profiles: { options: { readPolicy: "everyone" } } }),
    ).toThrow(/readPolicy/);
    expect(() =>
      body({ profiles: { options: { readPolicy: "members" } } }),
    ).toThrow(/needs the tenant module/);
    expect(() =>
      body({
        profiles: { options: { extraColumns: { x: "text; drop table y" } } },
      }),
    ).toThrow(/extraColumns.x/);
    expect(() =>
      body({ profiles: { options: { metadata: { name: "Bad Column" } } } }),
    ).toThrow(/not a valid column name/);
    expect(() =>
      body({ profiles: { options: { metadata: { name: 1 } } } }),
    ).toThrow(/must be a column name/);
    expect(() => body({ profiles: { options: { metadata: [] } } })).toThrow(
      /must be an object/,
    );
  });

  it("joins metadata names into a username and adds a platform read policy", () => {
    const sql = renderModules(["profiles"], {
      modules: {
        profiles: {
          options: {
            usernameFrom: [
              { names: ["first_name", "last_name"], separator: "." },
              "user_name",
            ],
            readPolicy: { platform: "platform.user.read" },
          },
        },
      },
    }).find(
      (file) => file.module === "profiles" && file.kind === "schema",
    )!.contents;
    expect(sql).toContain(
      "case when nullif(btrim(coalesce(meta ->> 'first_name')), '') is not null and nullif(btrim(coalesce(meta ->> 'last_name')), '') is not null then concat_ws('.',",
    );
    expect(sql).toContain("better_supabase.is_platform('platform.user.read')");
    expect(sql).toContain("create policy bs_profiles_platform_read");
    expect(
      resolveModules(["profiles"], {
        modules: { profiles: { options: { readPolicy: { platform: "x" } } } },
      }).map((module) => module.name),
    ).toContain("access");
    expect(
      body({
        profiles: {
          options: { usernameFrom: [{ names: ["nick"] }] },
        },
      }),
    ).toContain("concat_ws('_', nullif(btrim(coalesce(meta ->> 'nick')), ''))");
    expect(() =>
      body({ profiles: { options: { readPolicy: { members: "yes" } } } }),
    ).toThrow(/readPolicy must be/);
    expect(() =>
      body({ profiles: { options: { usernameFrom: "user_name" } } }),
    ).toThrow(/must be a list/);
    expect(() =>
      body({ profiles: { options: { usernameFrom: [{ names: [] }] } } }),
    ).toThrow(/entries are metadata keys/);
    expect(() =>
      body({
        profiles: {
          options: { usernameFrom: [{ names: ["a"], separator: "; drop" }] },
        },
      }),
    ).toThrow(/separator/);
  });

  it("needs no other module", () => {
    expect(resolveModules(["profiles"]).map((module) => module.name)).toEqual([
      "profiles",
    ]);
  });
});
