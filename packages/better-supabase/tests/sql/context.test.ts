import { describe, expect, it } from "vitest";

import {
  checkBlocks,
  customContracts,
  isBlockDataFile,
  blockContext,
  blockFileVersion,
  moduleBody,
  renderBlocks,
  resolveModules,
  SQL_MODULES,
} from "../../src/sql/blocks.ts";
import {
  contractSignature,
  createBlockContext,
} from "../../src/sql/context.ts";

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

describe("createBlockContext", () => {
  it("resolves default names in the module schema", () => {
    const ctx = createBlockContext("demo", () => names);
    expect(ctx.mode).toBe("managed");
    expect(ctx.manages).toBe(true);
    expect(ctx.table("items")).toBe('"better_supabase"."items"');
    expect(ctx.col("items", "tenant")).toBe('"org_id"');
    expect(ctx.fn("can")).toBe('"better_supabase"."can"');
    expect(ctx.trigger("audit")).toBe('"bs_audit"');
    expect(ctx.idType).toBe("uuid");
    expect(ctx.hasTable("extras")).toBe(true);
  });

  it("maps tables, columns, schema, id type and permissions from blocks", () => {
    const ctx = createBlockContext("demo", () => names, {
      blocks: {
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
      createBlockContext("demo", () => names, { blocks: { demo } });
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
      'blocks.demo.options: unknown option "flavor". Options: flavour, size, on, list, missing',
    );
    expect(() =>
      createBlockContext("bare", () => undefined, {
        blocks: { bare: { options: { size: 1 } } },
      }),
    ).toThrow('blocks.bare.options: unknown option "size". Options: none');
    const ctx = createBlockContext("demo", () => names);
    expect(() => ctx.table("nope")).toThrow(/no table/);
    expect(() => ctx.col("items", "nope")).toThrow(/no column/);
    expect(() => ctx.hasTable("nope")).toThrow(/no table/);
    expect(() => ctx.text("undeclared", "")).toThrow(
      'Module "demo" reads option "undeclared", which its names.options doesn\'t declare',
    );
    expect(ctx.option("size")).toBeUndefined();
  });

  it("takes the id type from blocks.access, then PermDock", () => {
    expect(
      createBlockContext("demo", () => names, {
        blocks: { access: { idType: "text" } },
      }).idType,
    ).toBe("text");
    expect(
      createBlockContext("demo", () => names, { permdockIdType: "integer" })
        .idType,
    ).toBe("integer");
  });

  it("knows the modules installed with it and reaches other modules", () => {
    const ctx = blockContext("access", {}, ["tenant", "access"]);
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
    const ctx = createBlockContext("demo", () => hooked);
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
      createBlockContext("demo", () => ({
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
    const ctx = createBlockContext("demo", () => hooked, {
      blocks: {
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
      createBlockContext("demo", () => hooked, {
        blocks: { demo: { hooks: { functions: { nope: "x" } } } },
      }),
    ).toThrow(
      'blocks.demo.hooks.functions: unknown hook "nope". Hooks: after_item_create',
    );
    expect(() =>
      createBlockContext("demo", () => names, {
        blocks: { demo: { hooks: { functions: { nope: "x" } } } },
      }),
    ).toThrow("Hooks: none");
    expect(() =>
      createBlockContext("demo", () => hooked, {
        blocks: {
          demo: { hooks: { functions: { after_item_create: "bad name" } } },
        },
      }),
    ).toThrow("is not a valid identifier");
    expect(() =>
      createBlockContext("demo", () => hooked, {
        blocks: { demo: { hooks: { schema: "1x" } } },
      }),
    ).toThrow("blocks.demo.hooks.schema");
  });

  it("writes outbox events only with the outbox installed", () => {
    const event = {
      type: "item.created",
      payload: "jsonb_build_object('id', new_id)",
      subject: "'items/' || new_id",
      tenant: "organization",
    };
    expect(createBlockContext("demo", () => names).emit(event)).toBe("");
    const ctx = createBlockContext("demo", () => names, {
      installed: ["demo", "outbox"],
      blocks: { outbox: { schema: "events" } },
    });
    expect(ctx.emit(event)).toBe(
      `perform "events".emit_event('item.created', jsonb_build_object('id', new_id), 'items/' || new_id, (organization)::text, null, 'better-supabase/demo');`,
    );
    expect(ctx.emit({ type: "x", payload: "'{}'", key: "k" })).toBe(
      `perform "events".emit_event('x', '{}', null, null, k, 'better-supabase/demo');`,
    );
    expect(
      createBlockContext("demo", () => names, {
        installed: ["demo", "outbox"],
        blocks: { demo: { events: false } },
      }).emit(event),
    ).toBe("");
    const sourced = createBlockContext("demo", () => names, {
      installed: ["demo", "outbox"],
      blocks: { outbox: { options: { blockSource: "app/{module}" } } },
    });
    expect(sourced.emit({ type: "x", payload: "'{}'" })).toContain(
      "'app/demo');",
    );
    expect(() =>
      createBlockContext("demo", () => names, {
        installed: ["demo", "outbox"],
        blocks: { outbox: { options: { blockSource: 1 } } },
      }).emit(event),
    ).toThrow("blockSource must be a string");
  });
});

describe("block modes", () => {
  it("rejects blocks for unknown modules and unsupported modes", () => {
    expect(() => {
      checkBlocks({ nope: {} });
    }).toThrow(/no SQL module "nope"/);
    expect(() => {
      checkBlocks({ mfa: { mode: "adopt" } });
    }).toThrow(/supports managed, not adopt/);
    expect(() =>
      renderBlocks(["mfa"], { blocks: { mfa: { mode: "custom" } } }),
    ).toThrow(/supports managed/);
  });

  it("accepts migration-only options in adopt mode only", () => {
    expect(() => {
      checkBlocks({ invitations: { options: { tokenStorage: "plain" } } });
    }).toThrow(
      'blocks.invitations.options.tokenStorage is "plain". It stores invitation tokens in plain text instead of their SHA-256 hash. Only adopt mode accepts it: set blocks.invitations.mode to "adopt" while you migrate an existing schema, or remove the option.',
    );
    expect(() => {
      checkBlocks({ outbox: { options: { blockSource: "domain" } } });
    }).toThrow(/outbox\.options\.blockSource/);
    expect(() => {
      checkBlocks({ "webhooks-out": { options: { eventIdType: "uuid" } } });
    }).toThrow(/eventIdType/);
    checkBlocks({
      invitations: { mode: "adopt", options: { tokenStorage: "plain" } },
    });
    checkBlocks({
      outbox: {
        options: {
          settle: "2 seconds",
          blockSource: "better-supabase/{module}",
          defaultSource: "",
        },
      },
    });
    checkBlocks({
      "webhooks-out": {
        options: { secretStorage: "vault", eventIdType: "text" },
      },
    });
  });

  it("stamps the module version and mode, and records the module", () => {
    const tenant = renderBlocks(["tenant"]).filter(
      (block) => block.module === "tenant",
    );
    const file = tenant.find((block) => block.kind === "schema");
    expect(file!.contents).toContain("-- @bs-block tenant@2 managed\n");
    expect(blockFileVersion(file!.contents)).toEqual({
      module: "tenant",
      version: 2,
    });
    expect(blockFileVersion("-- no marker")).toBeUndefined();
    expect(file!.contents).not.toContain("insert into");
    expect(file!.contents).toContain(
      "create table if not exists better_supabase.block_modules",
    );
    const data = tenant.find((block) => block.kind === "data");
    expect(data).toMatchObject({
      kind: "data",
      path: "supabase/better-supabase-data/900_better_supabase_04_tenant.sql",
    });
    expect(data!.contents).toContain("-- @bs-block-data tenant\n");
    expect(data!.contents).toContain("values ('tenant', 2, 'managed')");
    expect(isBlockDataFile(data!.contents)).toBe(true);
    expect(isBlockDataFile(file!.contents)).toBe(false);
    const dataPath = (layout: Parameters<typeof renderBlocks>[1]) =>
      renderBlocks(["tenant"], layout).find(
        (block) => block.kind === "data" && block.module === "tenant",
      )!.path;
    expect(dataPath({ dir: "supabase/schemas/_custom/better_supabase" })).toBe(
      "supabase/better-supabase-data/900_better_supabase_04_tenant.sql",
    );
    expect(dataPath({ dir: "./supabase/schemas/block/" })).toBe(
      "./supabase/better-supabase-data/900_better_supabase_04_tenant.sql",
    );
    expect(
      dataPath({
        dir: "supabase/declarative/block",
        schemasDir: "supabase/declarative",
      }),
    ).toBe("supabase/better-supabase-data/900_better_supabase_04_tenant.sql");
    expect(dataPath({ dir: "db/block" })).toBe(
      "db/better-supabase-data/900_better_supabase_04_tenant.sql",
    );
    const pgtap = renderBlocks(["pgtap"]);
    expect(pgtap.map((entry) => entry.kind)).toEqual(["test"]);
    expect(pgtap[0]!.contents).not.toContain("block_modules");
  });

  it("writes no file in custom mode and lists the contract instead", () => {
    const layout = { blocks: { tenant: { mode: "custom" as const } } };
    const files = renderBlocks(["invitations"], layout);
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
      blocks: {
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

  it("keeps the managed tenant module's names and takes roles from blocks.access", () => {
    const sql = SQL_MODULES["tenant"]!.sql;
    expect(sql).toContain(
      'create table if not exists "better_supabase"."memberships"',
    );
    expect(sql).toContain(
      `check ("role" in ('owner', 'admin', 'member', 'viewer'))`,
    );
    const custom = moduleBody("tenant", {
      blocks: { access: { roles: { lead: ["*"], guest: [] } } },
    })!;
    expect(custom).toContain(`check ("role" in ('lead', 'guest'))`);
  });

  it("renders the membership claim as a map on request", () => {
    const sql = moduleBody("tenant", {
      blocks: { tenant: { options: { claimFormat: "map" } } },
    })!;
    expect(sql).toContain('jsonb_object_agg(m."organization_id"::text');
  });

  it("reads the active tenant from the configured source, members only", () => {
    const claim = moduleBody("tenant", {
      blocks: { access: { activeTenant: "claim" } },
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
      blocks: {
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
        blocks: { access: { activeTenant: { profileColumn: "profiles.x" } } },
      }),
    ).toThrow(/schema.table.column/);
  });

  it("honours disabled tenants and users", () => {
    const sql = moduleBody("tenant", {
      blocks: {
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
      resolveModules(["access"], { blocks: { access: { model } } }).map(
        (module) => module.name,
      );
    expect(names("roles")).toEqual(["updated-at", "tenant", "access"]);
    expect(names("catalog")).toEqual(["updated-at", "tenant", "access"]);
    expect(names("permdock")).toEqual(["access"]);
    expect(names("custom")).toEqual(["access"]);
  });
});
