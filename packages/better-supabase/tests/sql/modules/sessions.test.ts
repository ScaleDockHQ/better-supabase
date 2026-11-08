import { describe, expect, it } from "vitest";

import type { BlockConfig } from "../../../src/config/blocks.ts";

import { moduleBody } from "../../../src/sql/render.ts";

const sessions = (config: BlockConfig = {}) =>
  moduleBody("sessions", { modules: { sessions: config } })!;

describe("sessions bootstrap wrappers", () => {
  it("renders nothing without the option", () => {
    expect(sessions()).not.toContain("bootstrap_");
  });

  it("renders one wrapper per entry that checks the session first", async () => {
    const sql = sessions({
      options: { bootstrap: { home: "app.home_data", inbox: "app.inbox" } },
    });

    expect(sql).toContain(
      "create or replace function better_supabase.bootstrap_home(args jsonb default '{}'::jsonb)",
    );
    expect(sql).toContain("'data', to_jsonb(app.home_data(args))");
    expect(sql).toContain("'data', to_jsonb(app.inbox(args))");
    expect(sql).toContain(
      "if not (select better_supabase.session_active()) then",
    );
    expect(sql).toContain("security invoker");
    expect(sql).toContain(
      "revoke execute on function better_supabase.bootstrap_home(jsonb) from public, anon;",
    );
    await expect(
      sql.slice(sql.indexOf("-- blocks['sessions'].options.bootstrap")),
    ).toMatchFileSnapshot("../__golden__/sessions-bootstrap.sql");
  });

  it("calls the function a read set installs", () => {
    const sql = sessions({
      options: { bootstrap: { home: { readSet: "home" } } },
    });

    expect(sql).toContain("'data', to_jsonb(public.rs_home(args))");
    expect(() =>
      sessions({ options: { bootstrap: { home: { readSet: "Home;" } } } }),
    ).toThrow(/read set name/);
  });

  it("adds the authorizer subject to the wrapper", () => {
    const sql = sessions({
      options: {
        bootstrap: { home: { readSet: "home", subject: "app.authz_subject" } },
      },
    });

    expect(sql).toContain("'subject', to_jsonb(app.authz_subject())");
    expect(() =>
      sessions({
        options: { bootstrap: { home: { readSet: "home", subject: "drop;" } } },
      }),
    ).toThrow(/subject must name a function/);
  });

  it("takes a read set per call from a fixed list", () => {
    const sql = sessions({
      options: {
        bootstrap: {
          home: { readSets: ["hub", "detail"], shell: "app.home_data" },
        },
      },
    });

    expect(sql).toContain(
      "bootstrap_home(args jsonb default '{}'::jsonb, read_set text default null, read_params jsonb default null)",
    );
    expect(sql).toContain("when 'hub' then to_jsonb(public.rs_hub(");
    expect(sql).toContain("when 'detail' then to_jsonb(public.rs_detail(");
    expect(sql).toContain("read_set not in ('hub', 'detail')");
    expect(sql).toContain("'data', to_jsonb(app.home_data(args))");
    expect(sql).toContain(
      "bootstrap_home(jsonb, text, jsonb) to authenticated",
    );
    expect(() =>
      sessions({ options: { bootstrap: { home: { readSets: ["hub;"] } } } }),
    ).toThrow(/read set names/);
    expect(() =>
      sessions({
        options: {
          bootstrap: { home: { readSets: ["hub"], shell: "home; drop" } },
        },
      }),
    ).toThrow(/shell must name a function/);
  });

  it("takes a function entry with the tables its payload reads", () => {
    const sql = sessions({
      options: {
        bootstrap: {
          home: { function: "app.home_data", tables: ["customers", "notes"] },
        },
      },
    });

    expect(sql).toContain("'data', to_jsonb(app.home_data(args))");
    expect(() =>
      sessions({
        options: {
          bootstrap: { home: { function: "app.home_data", tables: "notes" } },
        },
      }),
    ).toThrow(/tables must list table names/);
    expect(() =>
      sessions({
        options: {
          bootstrap: { home: { readSet: "home", tables: ["a; drop"] } },
        },
      }),
    ).toThrow(/tables must list table names/);
    expect(() =>
      sessions({
        options: { bootstrap: { home: { function: "home; drop" } } },
      }),
    ).toThrow(/function must name a function/);
  });

  it("rejects a name or a function it can't render safely", () => {
    expect(() => sessions({ options: { bootstrap: ["app.home"] } })).toThrow(
      /must map names to functions/,
    );
    expect(() =>
      sessions({ options: { bootstrap: { Home: "app.home_data" } } }),
    ).toThrow(/lowercase name/);
    expect(() =>
      sessions({ options: { bootstrap: { home: "home_data(); drop" } } }),
    ).toThrow(/schema\.function/);
  });
});

describe("sessions authorization versions", () => {
  it("renders nothing without the option", () => {
    expect(sessions()).not.toContain("user_authz_versions");
  });

  it("renders the table, the bump trigger and both broadcasts", async () => {
    const sql = sessions({ options: { authzVersions: true } });

    expect(sql).toContain("create table better_supabase.user_authz_versions (");
    expect(sql).toContain("'better_supabase:authz'");
    expect(sql).toContain("'authz:' || new.user_id::text");
    expect(sql).toContain(
      "(select realtime.topic()) = 'authz:' || (select auth.uid())::text",
    );
    expect(sql).toContain(
      "revoke all on better_supabase.user_authz_versions from public, anon, authenticated;",
    );
    expect(sql).toContain("return better_supabase.authz_version(auth.uid());");
    expect(sql).toContain(
      "grant execute on function better_supabase.caller_authz_version() to authenticated;",
    );
    await expect(
      sql.slice(sql.indexOf("-- blocks['sessions'].options.authzVersions")),
    ).toMatchFileSnapshot("../__golden__/sessions-authz-versions.sql");
  });

  it("returns the live version from the bootstrap wrappers when it keeps one", () => {
    const live = sessions({
      options: { authzVersions: true, bootstrap: { home: "app.home_data" } },
    });

    expect(live).toContain(
      "'authz_version', to_jsonb(better_supabase.caller_authz_version())",
    );
    expect(live).toContain("'token_authz_version', auth.jwt() -> 'authz_ver'");
    expect(
      live.indexOf("function better_supabase.caller_authz_version"),
    ).toBeLessThan(live.indexOf("function better_supabase.bootstrap_home"));

    const token = sessions({
      options: { bootstrap: { home: "app.home_data" } },
    });

    expect(token).not.toContain("caller_authz_version");
    expect(token).toContain("'authz_version', auth.jwt() -> 'authz_ver'");
  });

  it("takes the subject function from the authorization provider unless an entry says otherwise", () => {
    const render = (home: unknown, other: unknown = "app.other") =>
      moduleBody("sessions", {
        modules: { sessions: { options: { bootstrap: { home, other } } } },
        accessProvider: {
          name: "acme-authz",
          scope: "organization",
          idType: "uuid",
          functions: {
            idsWith: "acme.ids({permission})",
            isPlatform: "acme.is({permission})",
            subject: "acme.own_subject",
          },
        },
      })!;

    const sql = render({ readSet: "home" });

    expect(sql).toContain("'subject', to_jsonb(acme.own_subject())");
    expect(render("app.home_data", "app.other")).toContain(
      "'subject', to_jsonb(acme.own_subject())",
    );
    expect(render({ readSet: "home", subject: "app.mine" })).toContain(
      "'subject', to_jsonb(app.mine())",
    );
    expect(
      render(
        { readSet: "home", subject: false },
        { readSet: "x", subject: false },
      ),
    ).not.toContain("'subject'");
  });

  it("reads the provider's function and writes no table when the provider keeps the versions", async () => {
    const sql = moduleBody("sessions", {
      modules: {
        sessions: {
          options: {
            authzVersions: true,
            bootstrap: { home: "app.home_data" },
          },
        },
      },
      authzVersionsProvider: {
        name: "acme-authz",
        function: "acme.authz_version_for",
      },
    })!;

    expect(sql).not.toContain("user_authz_versions");
    expect(sql).not.toContain("bump_authz_version");
    expect(sql).not.toContain("bsb_authz_versions_receive");
    expect(sql).toContain("return acme.authz_version_for(auth.uid());");
    expect(sql).toContain(
      "'authz_version', to_jsonb(better_supabase.caller_authz_version())",
    );
    await expect(
      sql.slice(sql.indexOf("-- The caller's own authorization version")),
    ).toMatchFileSnapshot("../__golden__/sessions-provider-versions.sql");
  });

  it("reads the provider's function without the module option", () => {
    const sql = moduleBody("sessions", {
      modules: { sessions: {} },
      authzVersionsProvider: {
        name: "acme-authz",
        function: "acme.authz_version_for",
      },
    })!;

    expect(sql).toContain("function better_supabase.caller_authz_version()");
    expect(sql).not.toContain("user_authz_versions");
  });
});
