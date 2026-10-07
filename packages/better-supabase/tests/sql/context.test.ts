import { describe, expect, it } from "vitest";

import {
  contractSignature,
  createModuleContext,
} from "../../src/sql/context.ts";
import {
  checkModules,
  customContracts,
  isModuleDataFile,
  moduleContext,
  moduleFileVersion,
  moduleBody,
  renderModules,
  resolveModules,
  SQL_MODULES,
} from "../../src/sql/registry.ts";

const names = {
  tables: {
    items: {
      name: "items",
      columns: { tenant: "org_id", label: "label" },
      optional: ["label"],
    },
    extras: { name: "extras", columns: { id: "id" }, optionalTable: true },
  },
  options: ["flavour", "size", "on", "list", "missing"],
};

describe("createModuleContext", () => {
  it("resolves default names in the module schema", () => {
    const ctx = createModuleContext("demo", () => names);
    expect(ctx.mode).toBe("managed");
    expect(ctx.manages).toBe(true);
    expect(ctx.table("items")).toBe('"better_supabase"."items"');
    expect(ctx.col("items", "tenant")).toBe('"org_id"');
    expect(ctx.fn("can")).toBe('"better_supabase"."can"');
    expect(ctx.trigger("audit")).toBe('"bs_audit"');
    expect(ctx.idType).toBe("uuid");
    expect(ctx.hasTable("extras")).toBe(true);
  });

  it("maps tables, columns, schema, id type and permissions from modules", () => {
    const ctx = createModuleContext("demo", () => names, {
      modules: {
        demo: {
          mode: "adopt",
          schema: "app",
          tables: { items: "public.things", extras: null },
          columns: { items: { tenant: "organization_id", label: null } },
          idType: "int8",
          permissions: { invite: "organization.members.invite" },
          options: { flavour: "map", size: 3, on: true, list: ["a"] },
        },
      },
    });
    expect(ctx.manages).toBe(false);
    expect(ctx.table("items")).toBe('"public"."things"');
    expect(ctx.col("items", "tenant")).toBe('"organization_id"');
    expect(ctx.has("items", "label")).toBe(false);
    expect(ctx.has("items", "tenant")).toBe(true);
    expect(ctx.hasTable("extras")).toBe(false);
    expect(() => ctx.table("extras")).toThrow(/maps to null/);
    expect(() => ctx.col("items", "label")).toThrow(/maps to null/);
    expect(ctx.schema).toBe('"app"');
    expect(ctx.idType).toBe("bigint");
    expect(ctx.trigger("audit")).toBe('"bs_audit"');
    expect(ctx.permission("invite", "members.invite")).toBe(
      "'organization.members.invite'",
    );
    expect(ctx.permissionKey("remove", "members.remove")).toBe(
      "members.remove",
    );
    expect(ctx.text("flavour", "array")).toBe("map");
    expect(ctx.number("size", 1)).toBe(3);
    expect(ctx.flag("on", false)).toBe(true);
    expect(ctx.list("list", [])).toEqual(["a"]);
    expect(ctx.list("missing", ["x"])).toEqual(["x"]);
    expect(() => ctx.number("flavour", 1)).toThrow(/must be a number/);
    expect(() => ctx.list("flavour", [])).toThrow(/string array/);
  });

  it("rejects unknown tables and columns, required nulls and bad names", () => {
    const build = (demo: object) => () =>
      createModuleContext("demo", () => names, { modules: { demo } });
    expect(build({ tables: { nope: "x" } })).toThrow(/unknown table "nope"/);
    expect(build({ columns: { nope: {} } })).toThrow(/unknown table "nope"/);
    expect(build({ columns: { items: { nope: "x" } } })).toThrow(
      /unknown column "nope"/,
    );
    expect(build({ columns: { items: { tenant: null } } })).toThrow(/required/);
    expect(build({ tables: { items: null } })).toThrow(/required/);
    expect(build({ columns: { items: { tenant: "bad name" } } })).toThrow(
      /not a valid identifier/,
    );
    expect(build({ schema: "1x" })).toThrow(/not a valid identifier/);
    expect(build({ idType: "jsonb" })).toThrow(/idType/);
    expect(build({ options: { flavor: "map" } })).toThrow(
      'sql.modules.demo.options: unknown option "flavor". Options: flavour, size, on, list, missing',
    );
    expect(() =>
      createModuleContext("bare", () => undefined, {
        modules: { bare: { options: { size: 1 } } },
      }),
    ).toThrow('sql.modules.bare.options: unknown option "size". Options: none');
    const ctx = createModuleContext("demo", () => names);
    expect(() => ctx.table("nope")).toThrow(/no table/);
    expect(() => ctx.col("items", "nope")).toThrow(/no column/);
    expect(() => ctx.hasTable("nope")).toThrow(/no table/);
    expect(() => ctx.text("undeclared", "")).toThrow(
      'Module "demo" reads option "undeclared", which its names.options doesn\'t declare',
    );
    expect(ctx.option("size")).toBeUndefined();
  });

  it("takes the id type from sql.modules.access, then PermDock", () => {
    expect(
      createModuleContext("demo", () => names, {
        modules: { access: { idType: "text" } },
      }).idType,
    ).toBe("text");
    expect(
      createModuleContext("demo", () => names, { permdockIdType: "integer" })
        .idType,
    ).toBe("integer");
  });

  it("knows the modules installed with it and reaches other modules", () => {
    const ctx = moduleContext("access", {}, ["tenant", "access"]);
    expect(ctx.installed("tenant")).toBe(true);
    expect(ctx.installed("outbox")).toBe(false);
    expect(ctx.of("tenant").table("memberships")).toBe(
      '"better_supabase"."memberships"',
    );
  });

  it("prints contract signatures with the id type", () => {
    expect(
      contractSignature(
        { name: "can", args: ["text", "{id}", "text"], returns: "boolean" },
        "bigint",
      ),
    ).toBe("text, bigint, text");
  });
});

describe("hooks and events", () => {
  const hooked = { ...names, hooks: ["after_item_create"] };

  it("calls the app's hook function when it exists", () => {
    const ctx = createModuleContext("demo", () => hooked);
    expect(
      ctx.hook("after_item_create", [
        ["uuid", "new_id"],
        ["uuid", "auth.uid()"],
      ]),
    )
      .toBe(`if to_regprocedure('"public"."after_item_create"(uuid, uuid)') is not null then
    execute format('select %s($1::uuid, $2::uuid)', to_regprocedure('"public"."after_item_create"(uuid, uuid)')::oid::regproc)
      using new_id, auth.uid();
  end if;`);
    expect(
      createModuleContext("demo", () => ({
        ...names,
        hooks: ["on_tick"],
      })).hook("on_tick", []),
    ).toContain(
      `execute format('select %s()', to_regprocedure('"public"."on_tick"()')::oid::regproc);`,
    );
    expect(() => ctx.hook("before_item_create", [])).toThrow(
      'Module "demo" declares no hook "before_item_create"',
    );
  });

  it("looks hooks up in the configured schema and functions", () => {
    const ctx = createModuleContext("demo", () => hooked, {
      modules: {
        demo: {
          hooks: {
            schema: "app",
            functions: { after_item_create: "private.seed_item" },
          },
        },
      },
    });
    expect(ctx.hook("after_item_create", [["uuid", "id"]])).toContain(
      `execute format('select %s($1::uuid)', to_regprocedure('"private"."seed_item"(uuid)')::oid::regproc)`,
    );
    expect(() =>
      createModuleContext("demo", () => hooked, {
        modules: { demo: { hooks: { functions: { nope: "x" } } } },
      }),
    ).toThrow(
      'sql.modules.demo.hooks.functions: unknown hook "nope". Hooks: after_item_create',
    );
    expect(() =>
      createModuleContext("demo", () => names, {
        modules: { demo: { hooks: { functions: { nope: "x" } } } },
      }),
    ).toThrow("Hooks: none");
    expect(() =>
      createModuleContext("demo", () => hooked, {
        modules: {
          demo: { hooks: { functions: { after_item_create: "bad name" } } },
        },
      }),
    ).toThrow("is not a valid identifier");
    expect(() =>
      createModuleContext("demo", () => hooked, {
        modules: { demo: { hooks: { schema: "1x" } } },
      }),
    ).toThrow("sql.modules.demo.hooks.schema");
  });

  it("writes outbox events only with the outbox installed", () => {
    const event = {
      type: "item.created",
      payload: "jsonb_build_object('id', new_id)",
      subject: "'items/' || new_id",
      tenant: "organization",
    };
    expect(createModuleContext("demo", () => names).emit(event)).toBe("");
    const ctx = createModuleContext("demo", () => names, {
      installed: ["demo", "outbox"],
      modules: { outbox: { schema: "events" } },
    });
    expect(ctx.emit(event)).toBe(
      `perform "events".emit_event('item.created', jsonb_build_object('id', new_id), 'items/' || new_id, (organization)::text, null, 'better-supabase/demo');`,
    );
    expect(ctx.emit({ type: "x", payload: "'{}'", key: "k" })).toBe(
      `perform "events".emit_event('x', '{}', null, null, k, 'better-supabase/demo');`,
    );
    expect(
      createModuleContext("demo", () => names, {
        installed: ["demo", "outbox"],
        modules: { demo: { events: false } },
      }).emit(event),
    ).toBe("");
    const sourced = createModuleContext("demo", () => names, {
      installed: ["demo", "outbox"],
      modules: { outbox: { options: { blockSource: "app/{module}" } } },
    });
    expect(sourced.emit({ type: "x", payload: "'{}'" })).toContain(
      "'app/demo');",
    );
    expect(() =>
      createModuleContext("demo", () => names, {
        installed: ["demo", "outbox"],
        modules: { outbox: { options: { blockSource: 1 } } },
      }).emit(event),
    ).toThrow("blockSource must be a string");
  });
});

describe("module modes", () => {
  it("rejects modules for unknown modules and unsupported modes", () => {
    expect(() => {
      checkModules({ nope: {} });
    }).toThrow(/no SQL module "nope"/);
    expect(() => {
      checkModules({ mfa: { mode: "adopt" } });
    }).toThrow(/supports managed, not adopt/);
    expect(() =>
      renderModules(["mfa"], { modules: { mfa: { mode: "custom" } } }),
    ).toThrow(/supports managed/);
  });

  it("accepts migration-only options in adopt mode only", () => {
    expect(() => {
      checkModules({ invitations: { options: { tokenStorage: "plain" } } });
    }).toThrow(
      'sql.modules.invitations.options.tokenStorage is "plain". It stores invitation tokens in plain text instead of their SHA-256 hash. Only adopt mode accepts it: set sql.modules.invitations.mode to "adopt" while you migrate an existing schema, or remove the option.',
    );
    expect(() => {
      checkModules({ outbox: { options: { blockSource: "domain" } } });
    }).toThrow(/outbox\.options\.blockSource/);
    expect(() => {
      checkModules({ "webhooks-out": { options: { eventIdType: "bigint" } } });
    }).toThrow(/eventIdType/);
    checkModules({
      invitations: { mode: "adopt", options: { tokenStorage: "plain" } },
    });
    checkModules({
      outbox: {
        options: {
          settle: "2 seconds",
          blockSource: "better-supabase/{module}",
          defaultSource: "",
        },
      },
    });
    checkModules({
      "webhooks-out": {
        options: { secretStorage: "vault", eventIdType: "text" },
      },
    });
    checkModules({
      "webhooks-out": { options: { eventIdType: "uuid", runIdType: "uuid" } },
    });
  });

  it("stamps the module version and mode, and records the module", () => {
    const tenant = renderModules(["tenant"]).filter(
      (module) => module.module === "tenant",
    );
    const file = tenant.find((module) => module.kind === "schema");
    expect(file!.contents).toContain("-- @bs-module tenant@2 managed\n");
    expect(moduleFileVersion(file!.contents)).toEqual({
      module: "tenant",
      version: 2,
    });
    expect(moduleFileVersion("-- no marker")).toBeUndefined();
    expect(file!.contents).not.toContain("insert into");
    expect(file!.contents).toContain(
      "create table if not exists better_supabase.modules",
    );
    const data = tenant.find((module) => module.kind === "data");
    expect(data).toMatchObject({
      kind: "data",
      path: "supabase/better-supabase-data/900_better_supabase_04_tenant.sql",
    });
    expect(data!.contents).toContain("-- @bs-module-data tenant\n");
    expect(data!.contents).toContain("values ('tenant', 2, 'managed')");
    expect(isModuleDataFile(data!.contents)).toBe(true);
    expect(isModuleDataFile(file!.contents)).toBe(false);
    const dataPath = (layout: Parameters<typeof renderModules>[1]) =>
      renderModules(["tenant"], layout).find(
        (module) => module.kind === "data" && module.module === "tenant",
      )!.path;
    expect(dataPath({ dir: "supabase/schemas/_custom/better_supabase" })).toBe(
      "supabase/better-supabase-data/900_better_supabase_04_tenant.sql",
    );
    expect(dataPath({ dir: "./supabase/schemas/module/" })).toBe(
      "./supabase/better-supabase-data/900_better_supabase_04_tenant.sql",
    );
    expect(
      dataPath({
        dir: "supabase/declarative/module",
        schemasDir: "supabase/declarative",
      }),
    ).toBe("supabase/better-supabase-data/900_better_supabase_04_tenant.sql");
    expect(dataPath({ dir: "db/module" })).toBe(
      "db/better-supabase-data/900_better_supabase_04_tenant.sql",
    );
    const pgtap = renderModules(["pgtap"]);
    expect(pgtap.map((entry) => entry.kind)).toEqual(["test"]);
    expect(pgtap[0]!.contents).not.toContain("better_supabase.modules");
  });

  it("writes no file in custom mode and lists the contract instead", () => {
    const layout = { modules: { tenant: { mode: "custom" as const } } };
    const files = renderModules(["invitations"], layout);
    expect(
      files.filter((file) => file.kind === "schema").map((file) => file.module),
    ).toEqual(["updated-at", "invitations", "access"]);
    expect(moduleBody("tenant", layout)).toBeUndefined();
    const [contract] = customContracts(["invitations"], layout);
    expect(contract).toMatchObject({
      module: "tenant",
      schema: "better_supabase",
    });
    expect(contract!.functions.map((fn) => fn.name)).toContain(
      "has_organization_role",
    );
    expect(customContracts(["mfa"])).toEqual([]);
  });

  it("adopts an existing memberships table without creating it", () => {
    const sql = moduleBody("tenant", {
      modules: {
        tenant: {
          mode: "adopt",
          tables: { memberships: "public.organization_users" },
          columns: {
            memberships: { tenant: "organization_id", lastUsedAt: null },
          },
        },
      },
    })!;
    expect(sql).not.toMatch(/create table/);
    expect(sql).not.toContain("bs_memberships_read");
    expect(sql).toContain('from "public"."organization_users" m');
    expect(sql).toContain(
      'm."organization_id" = has_organization_role.organization',
    );
    expect(sql).toContain("Adopted:");
  });

  it("keeps the managed tenant module's names and takes roles from sql.modules.access", () => {
    const sql = SQL_MODULES["tenant"]!.sql;
    expect(sql).toContain(
      'create table if not exists "better_supabase"."memberships"',
    );
    expect(sql).toContain(
      `check ("role" in ('owner', 'admin', 'member', 'viewer'))`,
    );
    const custom = moduleBody("tenant", {
      modules: { access: { roles: { lead: ["*"], guest: [] } } },
    })!;
    expect(custom).toContain(`check ("role" in ('lead', 'guest'))`);
  });

  it("renders the membership claim as a map on request", () => {
    const sql = moduleBody("tenant", {
      modules: { tenant: { options: { claimFormat: "map" } } },
    })!;
    expect(sql).toContain('jsonb_object_agg(m."organization_id"::text');
  });

  it("reads the active tenant from the configured source, members only", () => {
    const claim = moduleBody("tenant", {
      modules: { access: { activeTenant: "claim" } },
    })!;
    expect(claim).toContain("auth.jwt() ->> 'tenant_id'");
    expect(claim).not.toContain("x-bs-tenant");
    expect(claim).toContain('and m."user_id" = auth.uid() limit 1');
    expect(claim).toContain("raw_app_meta_data - 'tenant_id'");
    const resolver = moduleBody("tenant", {})!;
    expect(resolver).not.toContain("clear_tenant_claim");
    expect(resolver).toContain(
      "current_setting('better_supabase.tenant', true)",
    );
    expect(resolver).toContain("->> 'x-bs-tenant'");
    const profile = moduleBody("tenant", {
      modules: {
        access: {
          activeTenant: {
            profileColumn: "public.profiles.active_organization_id",
            key: "user_id",
          },
        },
      },
    })!;
    expect(profile).toContain(
      'select p."active_organization_id"::text from "public"."profiles" p where p."user_id" = auth.uid()',
    );
    expect(() =>
      moduleBody("tenant", {
        modules: { access: { activeTenant: { profileColumn: "profiles.x" } } },
      }),
    ).toThrow(/schema.table.column/);
  });

  it("defines the disabled helpers in one module file", () => {
    const disabled = {
      tenant: "public.organizations.disabled_at",
    } as const;
    const files = renderModules(["access"], {
      modules: { access: { disabled } },
    }).filter((file) => file.kind === "schema");
    expect(files.map((file) => file.module)).toEqual([
      "updated-at",
      "tenant",
      "access",
    ]);
    const defining = files.filter((file) =>
      file.contents.includes(
        "create or replace function better_supabase.tenant_disabled(",
      ),
    );
    expect(defining.map((file) => file.module)).toEqual(["access"]);
    const tenant = files.find((file) => file.module === "tenant")!.contents;
    expect(tenant).toContain("set check_function_bodies = off;");
    expect(tenant).toContain("not better_supabase.tenant_disabled(");
    expect(moduleBody("tenant")).toContain(
      "create or replace function better_supabase.tenant_disabled(",
    );
    expect(
      moduleBody("tenant", { modules: { access: { mode: "custom" } } }),
    ).toContain("create or replace function better_supabase.tenant_disabled(");
  });

  it("honours disabled tenants and users", () => {
    const sql = moduleBody("access", {
      modules: {
        access: {
          disabled: {
            tenant: "public.organizations.disabled_at",
            user: "public.profiles.disabled_at",
            userKey: "user_id",
          },
        },
      },
    })!;
    expect(sql).toContain(
      'exists (select 1 from "public"."organizations" t where t."id" = tenant_disabled.tenant and t."disabled_at" is not null)',
    );
    expect(sql).toContain(
      'exists (select 1 from "public"."profiles" u where u."user_id" = user_disabled.user_id and u."disabled_at" is not null)',
    );
  });

  it("pulls in tenant for the roles and catalog models only", () => {
    const names = (model: "roles" | "catalog" | "permdock" | "custom") =>
      resolveModules(["access"], { modules: { access: { model } } }).map(
        (module) => module.name,
      );
    expect(names("roles")).toEqual(["updated-at", "tenant", "access"]);
    expect(names("catalog")).toEqual(["updated-at", "tenant", "access"]);
    expect(names("permdock")).toEqual(["access"]);
    expect(names("custom")).toEqual(["access"]);
  });
});
