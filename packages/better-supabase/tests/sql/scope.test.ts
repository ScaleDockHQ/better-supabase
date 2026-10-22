import { readdir, readFile } from "node:fs/promises";
import { describe, expect, it } from "vitest";

import { moduleContext } from "../../src/sql/module-context.ts";
import {
  blockScope,
  resolveBlocks,
  SQL_MODULES,
} from "../../src/sql/registry.ts";
import { moduleBody, renderBlocks } from "../../src/sql/render.ts";
import { moduleScope } from "../../src/sql/scope.ts";

const MODULES_DIR = new URL("../../src/sql/modules/", import.meta.url);

const scope = (kind: "tenant" | "user" | "none") =>
  moduleScope({
    kind,
    idType: "uuid",
    access: false,
    members: () => "better_supabase.member_organization_ids",
  });

describe("moduleScope", () => {
  it("renders the access contract per tenant", () => {
    const tenant = scope("tenant");
    expect(tenant.can("t.org", "'tags.manage'")).toBe(
      "coalesce(better_supabase.can('tenant', t.org, 'tags.manage'), false)",
    );
    expect(tenant.ids("'tags.read'")).toBe(
      "better_supabase.tenant_ids_with('tags.read')",
    );
    expect(tenant.check("org", "'tags.read'")).toBe(
      "org in (select better_supabase.tenant_ids_with('tags.read'))",
    );
    expect(tenant.canUser("u", "t.org", "'x'")).toBe(
      "coalesce(better_supabase.can_user(u, 'tenant', t.org, 'x'), false)",
    );
    expect(tenant.platform("'p'")).toBe(
      "(select coalesce(better_supabase.is_platform('p'), false))",
    );
    expect(tenant.members()).toBe("better_supabase.member_organization_ids()");
    expect(tenant.column()).toBe("uuid not null");
    expect(tenant.bind("f.tenant")).toBe("");
    expect(tenant.value("f.tenant")).toBe("f.tenant");
    expect(tenant.eq("a", "b")).toBe("a = b");
  });

  it("checks the caller's own id per user", () => {
    const user = scope("user");
    expect(user.can("t.owner", "'tags.manage'")).toBe(
      "coalesce(t.owner = (select auth.uid()), false)",
    );
    expect(user.check("owner", "'tags.read'")).toBe(
      "owner = (select auth.uid())",
    );
    expect(user.canUser("u", "t.owner", "'x'")).toBe(
      "coalesce(t.owner = u, false)",
    );
    expect(user.column()).toBe("uuid default auth.uid()");
    expect(user.value("f.tenant")).toBe(
      "coalesce(f.tenant, (select auth.uid()))",
    );
    expect(user.bind("f.tenant")).toContain("f.tenant := (select auth.uid());");
    expect(user.platform("'p'")).toBe("false");
  });

  it("lets every signed-in user in the shared space", () => {
    const none = scope("none");
    expect(none.can("t.org", "'tags.manage'")).toBe(
      "((select auth.uid()) is not null)",
    );
    expect(none.check("org", "'tags.read'")).toBe(
      "((select auth.uid()) is not null)",
    );
    expect(none.column()).toBe("uuid");
    expect(none.value("f.tenant")).toBe("null::uuid");
    expect(none.eq("a", "b")).toBe("a is not distinct from b");
  });
});

describe("block scope", () => {
  it("defaults to sql.scope, then tenant, and keeps tenant and access in tenant", () => {
    expect(blockScope("tags", {})).toBe("tenant");
    expect(blockScope("tags", { scope: "user" })).toBe("user");
    expect(
      blockScope("tags", {
        scope: "user",
        modules: { tags: { scope: "none" } },
      }),
    ).toBe("none");
    expect(blockScope("tenant", { scope: "user" })).toBe("tenant");
  });

  it("drops tenant and access from what a user-scoped block needs", () => {
    const names = (scope?: "user") =>
      resolveBlocks(["tags"], scope ? { scope } : {}).map((m) => m.name);

    expect(names()).toEqual(expect.arrayContaining(["tenant", "access"]));
    expect(names("user")).toEqual(["tags"]);
  });

  it("refuses a block that needs tenants outside tenant scope", () => {
    expect(() => resolveBlocks(["organizations"], { scope: "user" })).toThrow(
      'blocks.organizations: the organizations module runs in tenant scope, not user (from database.sql.owner). Set blocks.organizations.owner to "tenant" or remove the block.',
    );
    expect(() =>
      resolveBlocks(["organizations"], {
        scope: "user",
        modules: { organizations: { scope: "tenant" } },
      }),
    ).not.toThrow();
    expect(() =>
      resolveBlocks(["drive-files"], {
        scope: "none",
        modules: { "drive-files": { scope: "tenant" } },
      }),
    ).toThrow(
      /not none \(from database.sql.owner\)\..* It is required by drive-files\./,
    );
  });

  it("has every module that needs tenants declare its scopes", () => {
    const undeclared = Object.values(SQL_MODULES)
      .filter((module) => module.name !== "tenant" && module.name !== "access")
      .filter((module) =>
        module.requires.some((name) => name === "tenant" || name === "access"),
      )
      .filter((module) => module.scopes === undefined)
      .map((module) => module.name);

    expect(undeclared).toEqual([]);
  });

  it("renders user ids as the scope id type", () => {
    expect(moduleContext("tags", { scope: "user" }).idType).toBe("uuid");
    expect(() =>
      moduleContext("tags", {
        scope: "user",
        modules: { tags: { idType: "bigint" } },
      }),
    ).toThrow(/in user scope the scope id is a user id, so it is uuid/);
  });
});

describe("module sources", () => {
  it("name the access contract only through ctx.scope", async () => {
    const literal =
      /better_supabase\.can\(|tenant_ids_with\(|is_platform\(|member_organization_ids\(\)/;

    const files = (await readdir(MODULES_DIR)).filter(
      (file) =>
        file.endsWith(".ts") &&
        file !== "access.ts" &&
        file !== "access-permissions.ts",
    );

    const sites: string[] = [];

    for (const file of files) {
      const lines = (await readFile(new URL(file, MODULES_DIR), "utf-8")).split(
        "\n",
      );

      for (const [index, line] of lines.entries()) {
        const code = line.trim();

        if (
          /^(\*|\/\/|\/\*|--)/.test(code) ||
          code.startsWith('"') ||
          code.includes("-- ")
        ) {
          continue;
        }

        if (literal.test(line)) {
          sites.push(`${file}:${String(index + 1)}`);
        }
      }
    }

    expect(sites).toEqual([]);
  });
});

// Outside string literals and comments: the identifiers the SQL uses.
function code(sql: string): string {
  return sql.replaceAll(/--[^\n]*/g, "").replaceAll(/'(?:[^']|'')*'/g, "''");
}

describe("blocks.tenant.names.organization", () => {
  const layout = {
    modules: { tenant: { entities: { organization: "workspace" } } },
  } as const;

  it("leaves no organization identifier but parameter names", () => {
    const names = Object.keys(SQL_MODULES).filter((name) => name !== "pgtap");

    const found = new Set(
      renderBlocks(names, layout).flatMap((file) =>
        [...code(file.contents).matchAll(/\w*organization\w*/g)].map(
          (match) => match[0],
        ),
      ),
    );

    // Function parameters keep their names, so the TypeScript clients pass
    // the same arguments under any tenant name.
    expect([...found].toSorted()).toEqual([
      "except_organization",
      "organization",
    ]);
  });

  it("renames tables, columns, functions and their parameter qualifiers", () => {
    const sql = moduleBody("organizations", layout) ?? "";
    expect(sql).toContain(
      'create table if not exists "better_supabase"."workspaces"',
    );
    expect(sql).toContain('"better_supabase"."create_workspace"(');
    expect(sql).not.toMatch(/\bcreate_organization\./);
    const tenant = moduleBody("tenant", layout) ?? "";
    expect(tenant).toContain("better_supabase.member_workspace_ids(");
    expect(tenant).toContain('"workspace_id"');
  });
});

describe("tenant name clashes", () => {
  it("refuses a tenant name that renames onto a name a module already uses", () => {
    expect(() =>
      renderBlocks(["teams"], {
        modules: { tenant: { entities: { organization: "team" } } },
      }),
    ).toThrow(
      'blocks.tenant.names.organization: "team" renames the tenant tables and columns to names the teams module already uses (teams, team_id). Choose another name.',
    );
    expect(() =>
      renderBlocks(["teams"], {
        modules: { tenant: { entities: { organization: "workspace" } } },
      }),
    ).not.toThrow();
  });
});

describe("blocks.<name>.functions", () => {
  it("renames a function and its parameter qualifiers", () => {
    const sql =
      moduleBody("tags", {
        modules: { tags: { functions: { create_tag: "make_tag" } } },
      }) ?? "";

    expect(sql).toContain('"better_supabase"."make_tag"(');
    expect(sql).toContain("make_tag.tenant");
    expect(sql).not.toMatch(/\bcreate_tag\b/);
  });

  it("takes the renamed name as a key under a renamed tenant", () => {
    const sql =
      moduleBody("organizations", {
        modules: {
          tenant: { entities: { organization: "workspace" } },
          organizations: { functions: { create_workspace: "open_workspace" } },
        },
      }) ?? "";

    expect(sql).toContain('"better_supabase"."open_workspace"(');
  });

  it("rejects a function the module doesn't write", () => {
    expect(() =>
      renderBlocks(["tags"], {
        modules: { tags: { functions: { make_coffee: "brew" } } },
      }),
    ).toThrow(
      'blocks.tags.functions: the tags module writes no function "make_coffee"',
    );
  });

  it("checks the names are identifiers", () => {
    expect(() =>
      moduleContext("tags", {
        modules: { tags: { functions: { create_tag: "make tag" } } },
      }),
    ).toThrow(
      /blocks.tags.functions.create_tag: "make tag" is not a valid identifier/,
    );
  });
});
