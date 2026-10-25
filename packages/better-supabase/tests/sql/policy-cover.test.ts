import { describe, expect, it } from "vitest";

import type { CatalogPolicy } from "../../src/config/snapshot.ts";

import {
  appTablePolicyNotes,
  canonicalCondition,
  declaredPolicies,
  parsePolicy,
  widenedCommands,
  withoutAppTablePolicies,
  withoutCoveredPolicies,
} from "../../src/sql/policy-cover.ts";
import { renderBlocks } from "../../src/sql/render.ts";
import { ownTablesOf } from "../fixtures/own-tables.ts";

const policy = (
  name: string,
  using: string,
  extra: Partial<CatalogPolicy> = {},
): CatalogPolicy => ({
  name,
  command: "select",
  roles: ["authenticated"],
  permissive: true,
  using,
  check: null,
  ...extra,
});

const MEMBERS = "id in (select better_supabase.member_organization_ids())";

const BLOCK = `drop policy if exists bsb_organizations_select on "public"."organizations";
create policy bsb_organizations_select on "public"."organizations" for select to authenticated
  using ("id" in (select better_supabase.member_organization_ids()));
comment on policy bsb_organizations_select on "public"."organizations" is 'members';
`;

describe("canonicalCondition", () => {
  it("spells a schema file's condition and Postgres's print of it the same", () => {
    expect(
      canonicalCondition(
        "(id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids))",
      ),
    ).toBe(
      canonicalCondition(
        `"id" in (select better_supabase.member_organization_ids())`,
      ),
    );
  });

  it("keeps string literals, quoted names that need quotes and casts", () => {
    expect(
      canonicalCondition(`"Kind" = 'Open  Case' AND cast(x as text) = 'a'`),
    ).toBe(`"Kind" = 'Open  Case' and cast(x as text) = 'a'`);
    expect(canonicalCondition("")).toBe("");
  });
});

describe("parsePolicy", () => {
  it("reads the name, table, command, roles, mode and both expressions", () => {
    expect(
      parsePolicy(`create policy "Notes write" on notes as restrictive for update to authenticated, anon
  using (owner = (select auth.uid())) with check (owner = (select auth.uid()));`),
    ).toStrictEqual({
      table: "public.notes",
      policy: {
        name: "Notes write",
        command: "update",
        roles: ["authenticated", "anon"],
        permissive: false,
        using: "owner = (select auth.uid())",
        check: "owner = (select auth.uid())",
      },
    });
  });

  it("defaults to every command and public, and skips other statements", () => {
    expect(
      parsePolicy("create policy p on app.t with check (true);")?.policy,
    ).toMatchObject({
      command: "all",
      roles: ["public"],
      using: null,
      check: "true",
    });
    expect(parsePolicy("create table t (id int);")).toBeUndefined();
    expect(parsePolicy("create policy p on t using (a = (b);")).toBeUndefined();
  });
});

describe("declaredPolicies", () => {
  it("keeps what the files leave, in order, for the listed schemas", () => {
    expect(
      declaredPolicies(
        [
          {
            text: `-- create policy hidden on public.t using (false);
create policy a on public.t for select using (true);
create policy b on public.t for select using (false);
create policy c on private.t using (true);`,
          },
          {
            text: "drop policy if exists b on public.t; drop policy x on public.u;",
          },
        ],
        ["public"],
      ),
    ).toStrictEqual({
      "public.t": [policy("a", "true", { roles: ["public"] })],
    });
  });
});

describe("widenedCommands", () => {
  it("reports a command the block's condition opens wider than the app's", () => {
    expect(
      widenedCommands(policy("bsb_t_select", MEMBERS), [
        policy("own", "id = (select better_supabase.current_tenant_id())"),
      ]),
    ).toStrictEqual(["select"]);
  });

  it("leaves a command the app has no policy for, or one it allows with true", () => {
    expect(
      widenedCommands(policy("bsb_t_all", MEMBERS, { command: "all" }), [
        policy("own", "true", { roles: ["public"] }),
      ]),
    ).toStrictEqual([]);
  });

  it("counts an app condition with the block's as one of its or operands", () => {
    const tenant = "id = (select better_supabase.current_tenant_id())";

    expect(
      widenedCommands(policy("bsb_t_select", MEMBERS), [
        policy(
          "own",
          "((id = ( SELECT better_supabase.current_tenant_id() AS current_tenant_id)) OR (id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))",
        ),
      ]),
    ).toStrictEqual([]);
    expect(
      widenedCommands(policy("bsb_t_select", `${MEMBERS} or ${tenant}`), [
        policy("own", tenant),
      ]),
    ).toStrictEqual(["select"]);
  });
});

describe("withoutCoveredPolicies", () => {
  it("leaves out the block's policy when the app's has the same condition", () => {
    const out = withoutCoveredPolicies(BLOCK, {
      "public.organizations": [
        policy(
          "organizations_member_select",
          "(id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids))",
        ),
      ],
    });

    expect(out)
      .toBe(`drop policy if exists bsb_organizations_select on "public"."organizations";
-- public.organizations: the app's policy organizations_member_select already allows what bsb_organizations_select would, so the block adds none.
`);
  });

  it("leaves out a block condition the app's narrows with more and operands", () => {
    const sql = `create policy bsb_t_select on public.t for select to authenticated using (a = 1 and b = 2);`;

    expect(
      withoutCoveredPolicies(sql, { "public.t": [policy("own", "(b = 2)")] }),
    ).toContain("the app's policy own already allows");
  });

  it("keeps a wider block condition, so BS347 reports it", () => {
    expect(
      withoutCoveredPolicies(BLOCK, {
        "public.organizations": [
          policy(
            "organizations_member_select",
            "id = (select better_supabase.current_tenant_id())",
          ),
        ],
      }),
    ).toBe(BLOCK);
  });

  it("keeps the block's policy for a command or role the app's doesn't cover", () => {
    const all = `create policy bsb_t_all on public.t for all to authenticated using (true) with check (true);`;
    const anon = `create policy bsb_t_select on public.t for select to anon using (true);`;
    const own = { "public.t": [policy("own", "true")] };

    expect(withoutCoveredPolicies(all, own)).toBe(all);
    expect(withoutCoveredPolicies(anon, own)).toBe(anon);
  });

  it("keeps restrictive policies, the app's own names and tables without policies", () => {
    const sql = `create policy bsb_tenant_scope on public.t as restrictive for all to authenticated using (true);
create policy own on public.t for select using (true);
create policy bsb_u_select on public.u for select to authenticated using (true);`;

    const own = {
      "public.t": [
        policy("own", "true", { command: "all", roles: ["public"] }),
      ],
    };

    expect(withoutCoveredPolicies(sql, own)).toBe(sql);
    expect(withoutCoveredPolicies(sql)).toBe(sql);
  });

  it("drops the organizations block's policy over an app table whose own policy repeats it", () => {
    const modules = { organizations: {} };

    const layout = {
      modules,
      ownTables: ownTablesOf(modules, ["organizations"]),
    };

    const contents = (ownPolicies?: Record<string, CatalogPolicy[]>) =>
      renderBlocks(["organizations"], {
        ...layout,
        ...(ownPolicies ? { ownPolicies } : {}),
      })
        .filter((file) => file.kind === "schema")
        .map((file) => file.contents)
        .join("\n");

    expect(contents()).toContain("create policy bsb_organizations_select");

    const table = Object.keys(layout.ownTables).find((name) =>
      name.endsWith(".organizations"),
    )!;

    const covered = contents({
      [table]: [policy("organizations_member_select", MEMBERS)],
    });

    expect(covered).not.toContain("create policy bsb_organizations_select");
    expect(covered).toContain(
      "drop policy if exists bsb_organizations_select on",
    );
  });
});

describe("withoutAppTablePolicies", () => {
  it("leaves out the block's permissive and restrictive policies on the app's tables", () => {
    const sql = `${BLOCK}create policy bsb_tenant_scope on public.organizations as restrictive for all to authenticated using (true);
create policy bsb_teams_all on public.teams for all to authenticated using (true) with check (true);
`;

    expect(withoutAppTablePolicies(sql, new Set(["public.organizations"])))
      .toBe(`drop policy if exists bsb_organizations_select on "public"."organizations";
-- public.organizations: the app's policies govern this table (ownTablePolicies "app"), so the block adds no bsb_organizations_select for select.
-- public.organizations: the app's policies govern this table (ownTablePolicies "app"), so the block adds no restrictive bsb_tenant_scope.
create policy bsb_teams_all on public.teams for all to authenticated using (true) with check (true);
`);
  });

  it("names every command a for all policy would have granted", () => {
    expect(
      withoutAppTablePolicies(
        "create policy bsb_t_all on public.t for all to authenticated using (true);",
        new Set(["public.t"]),
      ),
    ).toContain("adds no bsb_t_all for select, insert, update, delete.");
  });

  it("reads back the policies it left out, but not the restrictive ones", () => {
    const sql = withoutAppTablePolicies(
      `create policy bsb_t_all on public.t for all to authenticated using (true);
create policy bsb_t_select on public.t for select to authenticated using (true);
create policy bsb_tenant_scope on public.t as restrictive for all to authenticated using (true);`,
      new Set(["public.t"]),
    );

    expect(appTablePolicyNotes(sql)).toEqual([
      {
        table: "public.t",
        policy: "bsb_t_all",
        commands: ["select", "insert", "update", "delete"],
      },
      { table: "public.t", policy: "bsb_t_select", commands: ["select"] },
    ]);
  });

  it("keeps everything without app tables", () => {
    expect(withoutAppTablePolicies(BLOCK, new Set())).toBe(BLOCK);
  });

  it("renders a block with ownTablePolicies app without its policies on the app's table", () => {
    const contents = (ownTablePolicies?: "app" | "block") => {
      const modules = {
        organizations:
          ownTablePolicies === undefined ? {} : { ownTablePolicies },
      };

      return renderBlocks(["organizations"], {
        modules,
        ownTables: ownTablesOf(modules, ["organizations"]),
      })
        .filter((file) => file.kind === "schema")
        .map((file) => file.contents)
        .join("\n");
    };

    expect(contents()).toContain("create policy bsb_organizations_select");
    expect(contents("block")).toBe(contents());

    const app = contents("app");

    expect(app).not.toContain("create policy bsb_organizations_select");
    expect(app).toContain("drop policy if exists bsb_organizations_select on");
    expect(app).toMatch(
      /-- \S+\.organizations: the app's policies govern this table \(ownTablePolicies "app"\), so the block adds no bsb_organizations_select for select\./,
    );
    expect(app).toContain("create or replace function");
  });

  it("leaves the tenant scope off the app's memberships table, and drops an earlier copy", () => {
    const modules = { memberships: { ownTablePolicies: "app" as const } };
    const ownTables = ownTablesOf(modules, ["memberships"]);

    const table = Object.keys(ownTables).find((name) =>
      name.endsWith(".memberships"),
    )!;

    const [schema, name] = table.split(".");
    const quoted = `"${schema}"."${name}"`;

    const contents = (layout: Parameters<typeof renderBlocks>[1]) =>
      renderBlocks(["memberships"], layout)
        .filter((file) => file.kind === "schema")
        .map((file) => file.contents)
        .join("\n");

    const app = contents({ modules, ownTables });

    expect(contents({ modules: {}, ownTables })).toContain(
      `create policy bsb_tenant_scope on ${quoted}`,
    );
    expect(app).not.toContain(`create policy bsb_tenant_scope on ${quoted}`);
    expect(app).not.toMatch(
      new RegExp(`create policy bsb_\\w+ on ${quoted.replaceAll(".", "\\.")}`),
    );
    expect(app).toContain(
      `drop policy if exists bsb_tenant_scope on ${quoted}`,
    );
    expect(app).toContain(
      `-- ${table}: the app's policies govern this table (ownTablePolicies "app"), so the block adds no restrictive bsb_tenant_scope.`,
    );
  });

  it("keeps the policies on the block's own tables with ownTablePolicies app", () => {
    const modules = { organizations: { ownTablePolicies: "app" as const } };

    const contents = renderBlocks(["organizations"], { modules })
      .filter((file) => file.kind === "schema")
      .map((file) => file.contents)
      .join("\n");

    expect(contents).toContain("create policy bsb_organizations_read");
    expect(contents).not.toContain("the app's policies govern");
  });
});
