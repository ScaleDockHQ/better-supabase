import { describe, expect, it } from "vitest";

import type { OrganizationsEvents } from "../../src/blocks/organizations/events.ts";
import type { BlockSqlEvents } from "../../src/sql/context.ts";

import {
  contractSignature,
  createModuleContext,
  NOTHING,
} from "../../src/sql/context.ts";
import { isModuleDataFile, moduleFileVersion } from "../../src/sql/markers.ts";
import { moduleContext } from "../../src/sql/module-context.ts";
import {
  checkMigrationOptions,
  checkModules,
  resolveBlocks,
  SQL_MODULES,
} from "../../src/sql/registry.ts";
import {
  customContracts,
  moduleBody,
  renderBlocks,
} from "../../src/sql/render.ts";
import { ownTablesOf } from "../fixtures/own-tables.ts";

const names = {
  tables: {
    items: {
      name: "items",
      app: {},
      columns: { tenant: "org_id", label: "label" },
      optional: ["label"],
      typed: ["label"],
    },
    extras: { name: "extras", columns: { id: "id" }, optionalTable: true },
  },
  options: ["flavour", "size", "on", "list", "missing"],
};

describe("createModuleContext", () => {
  it("casts a typed column to the type of the app's table, and leaves the block's own one as it is", () => {
    expect(
      createModuleContext("demo", () => names).cast(
        "items",
        "label",
        "p_label",
      ),
    ).toBe("p_label");

    const overApp = createModuleContext("demo", () => names, {
      modules: { demo: { tables: { items: "public.things" } } },
      ownTables: { "public.things": "app.sql" },
    });

    expect(overApp.cast("items", "label", "p_label")).toBe(
      'better_supabase.as_column_type(p_label, (null::"public"."things")."label")',
    );
    expect(() => overApp.cast("items", "tenant", "p_tenant")).toThrow(
      /doesn't list/,
    );
  });

  it("resolves default names in the module schema", () => {
    const ctx = createModuleContext("demo", () => names);
    expect(ctx.mode).toBe("managed");
    expect(ctx.manages).toBe(true);
    expect(ctx.table("items")).toBe('"better_supabase"."items"');
    expect(ctx.col("items", "tenant")).toBe('"org_id"');
    expect(ctx.fn("can")).toBe('"better_supabase"."can"');
    expect(ctx.trigger("audit")).toBe('"bsb_audit"');
    expect(ctx.idType).toBe("uuid");
    expect(ctx.hasTable("extras")).toBe(true);
  });

  it("maps tables, columns, schema, id type and permissions from modules", () => {
    const ctx = createModuleContext("demo", () => names, {
      modules: {
        demo: {
          schema: "app",
          tables: { items: "public.things", extras: null },
          columns: { items: { tenant: "organization_id", label: null } },
          idType: "int8",
          permissions: { invite: "organization.members.invite" },
          options: { flavour: "map", size: 3, on: true, list: ["a"] },
        },
      },
      ownTables: { "public.things": "app.sql" },
    });

    expect(ctx.owns("items")).toBe(false);
    expect(ctx.appOwned).toEqual(["items"]);
    expect(ctx.table("items")).toBe('"public"."things"');
    expect(ctx.col("items", "tenant")).toBe('"organization_id"');
    expect(ctx.has("items", "label")).toBe(false);
    expect(ctx.has("items", "tenant")).toBe(true);
    expect(ctx.hasTable("extras")).toBe(false);
    expect(ctx.table("extras")).toBe('"app"."bsb_unmapped_table:extras"');
    expect(ctx.col("items", "label")).toBe('"bsb_unmapped:items.label"');
    expect(() => ctx.colName("items", "label")).toThrow(/maps to null/);
    expect(ctx.schema).toBe('"app"');
    expect(ctx.idType).toBe("bigint");
    expect(ctx.trigger("audit")).toBe('"bsb_audit"');
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
      'blocks.demo.options: unknown option "flavor". Options: flavour, size, on, list, missing',
    );
    expect(() =>
      createModuleContext("bare", () => undefined, {
        modules: { bare: { options: { size: 1 } } },
      }),
    ).toThrow('blocks.bare.options: unknown option "size". Options: none');
    const ctx = createModuleContext("demo", () => names);
    expect(() => ctx.table("nope")).toThrow(/no table/);
    expect(() => ctx.col("items", "nope")).toThrow(/no column/);
    expect(() => ctx.hasTable("nope")).toThrow(/no table/);
    expect(() => ctx.text("undeclared", "")).toThrow(
      'Module "demo" reads option "undeclared", which its names.options doesn\'t declare',
    );
    expect(ctx.option("size")).toBeUndefined();
  });

  it("takes the id type from blocks.permissions, then the provider", () => {
    expect(
      createModuleContext("demo", () => names, {
        modules: { permissions: { idType: "text" } },
      }).idType,
    ).toBe("text");
    expect(
      createModuleContext("demo", () => names, { providerIdType: "integer" })
        .idType,
    ).toBe("integer");
  });

  it("knows the modules installed with it and reaches other modules", () => {
    const ctx = moduleContext("permissions", {}, [
      "memberships",
      "permissions",
    ]);

    expect(ctx.installed("memberships")).toBe(true);
    expect(ctx.installed("organizations")).toBe(false);
    expect(() => ctx.installed("outbox")).toThrow(
      'Module "permissions" reads module "outbox", which it neither requires nor lists in integrates',
    );
    expect(ctx.of("memberships").table("memberships")).toBe(
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
    ).toBe(`declare
    v_hook regprocedure := to_regprocedure('"public"."after_item_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using new_id, auth.uid();
    end if;
  end;`);
    expect(
      createModuleContext("demo", () => ({
        ...names,
        hooks: ["on_tick"],
      })).hook("on_tick", []),
    ).toContain(
      `v_hook regprocedure := to_regprocedure('"public"."on_tick"()');`,
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
      `v_hook regprocedure := to_regprocedure('"private"."seed_item"(uuid)');`,
    );
    expect(() =>
      createModuleContext("demo", () => hooked, {
        modules: { demo: { hooks: { functions: { nope: "x" } } } },
      }),
    ).toThrow(
      'blocks.demo.hooks.functions: unknown hook "nope". Hooks: after_item_create',
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
    ).toThrow("blocks.demo.hooks.schema");
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
      checkModules({ mfa: { mode: "custom" } });
    }).toThrow(/supports managed, not custom/);
    expect(() =>
      renderBlocks(["mfa"], { modules: { mfa: { mode: "custom" } } }),
    ).toThrow(/supports managed/);
  });

  it("accepts migration-only options only over the app's tables", () => {
    expect(() => {
      checkMigrationOptions({
        invitations: { options: { tokenStorage: "plain" } },
      });
    }).toThrow(
      'blocks.invitations.options.tokenStorage is "plain". It stores invitation tokens in plain text instead of their SHA-256 hash. It fits only a block over a table your schema already has: remove the option, or keep it while you migrate that table.',
    );
    expect(() => {
      checkMigrationOptions({ outbox: { options: { blockSource: "domain" } } });
    }).toThrow(/outbox\.options\.blockSource/);
    expect(() => {
      checkMigrationOptions({
        "webhooks-out": { options: { eventIdType: "bigint" } },
      });
    }).toThrow(/eventIdType/);
    const invitations = { invitations: { options: { tokenStorage: "plain" } } };
    checkMigrationOptions(invitations, ownTablesOf(invitations));
    checkMigrationOptions({
      outbox: {
        options: {
          settle: "2 seconds",
          blockSource: "better-supabase/{module}",
          defaultSource: "",
        },
      },
    });
    checkMigrationOptions({
      "webhooks-out": {
        options: { secretStorage: "vault", eventIdType: "text" },
      },
    });
    checkMigrationOptions({
      "webhooks-out": { options: { eventIdType: "uuid", runIdType: "uuid" } },
    });
  });

  it("stamps the module version and mode, and records the module", () => {
    const tenant = renderBlocks(["memberships"]).filter(
      (module) => module.module === "memberships",
    );

    const file = tenant.find((module) => module.kind === "schema");
    expect(file!.contents).toContain("-- @bsb-block memberships@3 managed\n");
    expect(moduleFileVersion(file!.contents)).toEqual({
      module: "memberships",
      version: 3,
    });
    expect(moduleFileVersion("-- no marker")).toBeUndefined();
    expect(file!.contents).not.toContain("insert into");
    expect(file!.contents).toContain(
      "create table if not exists better_supabase.blocks",
    );
    const data = tenant.find((module) => module.kind === "data");
    expect(data).toMatchObject({
      kind: "data",
      path: "supabase/better-supabase-data/900_better_supabase_004_memberships.sql",
    });
    expect(data!.contents).toContain("-- @bsb-block-data memberships\n");
    expect(data!.contents).toContain("values ('memberships', 3, 'managed')");
    expect(isModuleDataFile(data!.contents)).toBe(true);
    expect(isModuleDataFile(file!.contents)).toBe(false);

    const dataPath = (layout: Parameters<typeof renderBlocks>[1]) =>
      renderBlocks(["memberships"], layout).find(
        (module) => module.kind === "data" && module.module === "memberships",
      )!.path;

    expect(dataPath({ dir: "supabase/schemas/_custom/better_supabase" })).toBe(
      "supabase/better-supabase-data/900_better_supabase_004_memberships.sql",
    );
    expect(dataPath({ dir: "./supabase/schemas/module/" })).toBe(
      "./supabase/better-supabase-data/900_better_supabase_004_memberships.sql",
    );
    expect(
      dataPath({
        dir: "supabase/declarative/module",
        schemasDir: "supabase/declarative",
      }),
    ).toBe(
      "supabase/better-supabase-data/900_better_supabase_004_memberships.sql",
    );
    expect(dataPath({ dir: "db/module" })).toBe(
      "db/better-supabase-data/900_better_supabase_004_memberships.sql",
    );
    const pgtap = renderBlocks(["pgtap"]);
    expect(pgtap.map((entry) => entry.kind)).toEqual(["test"]);
    expect(pgtap[0]!.contents).not.toContain("better_supabase.blocks");
  });

  it("writes no file in custom mode and lists the contract instead", () => {
    const layout = { modules: { memberships: { mode: "custom" as const } } };
    const files = renderBlocks(["invitations"], layout);
    expect(
      files.filter((file) => file.kind === "schema").map((file) => file.module),
    ).toEqual(["updated-at", "invitations", "permissions"]);
    expect(moduleBody("memberships", layout)).toBeUndefined();
    const [contract] = customContracts(["invitations"], layout);
    expect(contract).toMatchObject({
      module: "memberships",
      schema: "better_supabase",
    });
    expect(contract!.functions.map((fn) => fn.name)).toContain(
      "has_organization_role",
    );
    expect(customContracts(["mfa"])).toEqual([]);
  });

  it("lays functions over the app's memberships table without creating it", () => {
    const sql = renderBlocks(["memberships"], {
      modules: {
        memberships: {
          tables: { memberships: "public.organization_users" },
          columns: {
            memberships: { tenant: "organization_id", lastUsedAt: null },
          },
        },
      },
      ownTables: { "public.organization_users": "app.sql" },
    }).find(
      (file) => file.module === "memberships" && file.kind === "schema",
    )!.contents;

    expect(sql).not.toContain('create table if not exists "public"');
    expect(sql).toContain(
      'alter table "public"."organization_users" add column if not exists "role" text',
    );
    expect(sql).not.toContain('"last_used_at"');
    expect(sql).toContain('from "public"."organization_users" m');
    expect(sql).toContain(
      'm."organization_id" = has_organization_role.organization',
    );
  });

  it("keeps the managed tenant module's names and takes roles from blocks.permissions", () => {
    const sql = SQL_MODULES["memberships"]!.sql;
    expect(sql).toContain(
      'create table if not exists "better_supabase"."memberships"',
    );
    expect(sql).toContain(
      `check ("role" in ('owner', 'admin', 'member', 'viewer'))`,
    );

    const custom = moduleBody("memberships", {
      modules: { permissions: { roles: { lead: ["*"], guest: [] } } },
    })!;

    expect(custom).toContain(`check ("role" in ('lead', 'guest'))`);
  });

  it("renders the membership claim as a map on request", () => {
    const sql = moduleBody("memberships", {
      modules: { memberships: { options: { claimFormat: "map" } } },
    })!;

    expect(sql).toContain('jsonb_object_agg(m."organization_id"::text');
  });

  it("reads the active tenant from the configured source, members only", () => {
    const claim = moduleBody("memberships", {
      modules: { permissions: { activeTenant: "claim" } },
    })!;

    expect(claim).toContain("auth.jwt() ->> 'tenant_id'");
    expect(claim).not.toContain("x-bsb-tenant");
    expect(claim).toContain('and m."user_id" = auth.uid() limit 1');
    expect(claim).toContain("raw_app_meta_data - 'tenant_id'");
    const resolver = moduleBody("memberships", {})!;
    expect(resolver).not.toContain("clear_tenant_claim");
    expect(resolver).toContain(
      "current_setting('better_supabase.tenant', true)",
    );
    expect(resolver).toContain("->> 'x-bsb-tenant'");

    const profile = moduleBody("memberships", {
      modules: {
        permissions: {
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
      moduleBody("memberships", {
        modules: {
          permissions: { activeTenant: { profileColumn: "profiles.x" } },
        },
      }),
    ).toThrow(/schema.table.column/);
  });

  it("defines the disabled helpers in one module file", () => {
    const disabled = { tenant: "public.organizations.disabled_at" } as const;

    const files = renderBlocks(["permissions"], {
      modules: { permissions: { disabled } },
    }).filter((file) => file.kind === "schema");

    expect(files.map((file) => file.module)).toEqual([
      "updated-at",
      "memberships",
      "permissions",
    ]);

    const defining = files.filter((file) =>
      file.contents.includes(
        "create or replace function better_supabase.tenant_disabled(",
      ),
    );

    expect(defining.map((file) => file.module)).toEqual(["permissions"]);

    const tenant = files.find(
      (file) => file.module === "memberships",
    )!.contents;

    expect(tenant).toContain("set check_function_bodies = off;");
    expect(tenant).toContain("not better_supabase.tenant_disabled(");
    expect(moduleBody("memberships")).toContain(
      "create or replace function better_supabase.tenant_disabled(",
    );
    expect(
      moduleBody("memberships", {
        modules: { permissions: { mode: "custom" } },
      }),
    ).toContain("create or replace function better_supabase.tenant_disabled(");
  });

  it("honours disabled tenants and users", () => {
    const sql = moduleBody("permissions", {
      modules: {
        permissions: {
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
    const names = (model: "roles" | "catalog" | "provider" | "custom") =>
      resolveBlocks(["permissions"], {
        modules: { permissions: { model } },
      }).map((module) => module.name);

    expect(names("roles")).toEqual([
      "updated-at",
      "memberships",
      "permissions",
    ]);
    expect(names("catalog")).toEqual([
      "updated-at",
      "memberships",
      "permissions",
    ]);
    expect(names("provider")).toEqual(["permissions"]);
    expect(names("custom")).toEqual(["permissions"]);
  });
});

describe("statement helpers", () => {
  const event = {
    type: "item.created",
    payload: "jsonb_build_object('id', new_id)",
    subject: "'items/' || new_id",
    tenant: "organization",
    key: "'item.created:' || new_id",
  };

  const all = (...installed: string[]) =>
    createModuleContext("demo", () => names, {
      installed: ["demo", ...installed],
    });

  it("returns a statement whatever is installed", () => {
    const bare = all();
    expect(bare.record({ ...event, audit: false })).toBe(NOTHING);
    expect(bare.record({ ...event, audit: { category: "data" } })).toBe(
      NOTHING,
    );
    expect(bare.notify("'{}'::jsonb")).toBe(NOTHING);
    expect(bare.enqueue("q", "'{}'::jsonb", "'k'")).toBe(NOTHING);
  });

  it("records to the outbox and the audit log", () => {
    expect(all("outbox").record({ ...event, audit: false })).toBe(
      all("outbox").emit(event),
    );

    const audited = all("audit").record({
      ...event,
      audit: { category: "data", targetType: "item", recordId: "new_id::text" },
    });

    expect(audited).toBe(`perform better_supabase.audit_event(
    event_type => 'item.created',
    category => 'data',
    target_type => 'item',
    record_id => new_id::text,
    tenant => (organization)::uuid,
    metadata => jsonb_build_object('id', new_id),
    idempotency_key => 'item.created:' || new_id
  );`);

    const both = all("outbox", "audit").record({
      ...event,
      audit: { category: "data" },
    });

    expect(both.startsWith(all("outbox").emit(event))).toBe(true);
    expect(both).toContain("better_supabase.audit_event(");
  });

  it("skips the audit entry for audit: false, per action or per module", () => {
    expect(all("audit").record({ ...event, audit: false })).toBe(NOTHING);

    const optedOut = createModuleContext("demo", () => names, {
      installed: ["demo", "audit", "outbox"],
      modules: { demo: { audit: false } },
    });

    const statement = optedOut.record({
      ...event,
      audit: { category: "data" },
    });

    expect(statement).toBe(optedOut.emit(event));
    expect(statement).not.toContain("audit_event");
  });

  it("casts the tenant to the audit id type and honours auditCategory", () => {
    const legacy = createModuleContext(
      "demo",
      () => ({ ...names, options: [...names.options, "auditCategory"] }),
      {
        installed: ["demo", "audit"],
        modules: {
          audit: { idType: "text" },
          demo: { options: { auditCategory: "org" } },
        },
      },
    );

    const statement = legacy.record({ ...event, audit: { category: "data" } });
    expect(statement).toContain("category => 'org'");
    expect(statement).toContain("tenant => (organization)::text");

    const invalid = createModuleContext(
      "demo",
      () => ({ ...names, options: [...names.options, "auditCategory"] }),
      {
        installed: ["demo", "audit"],
        modules: { demo: { options: { auditCategory: 1 } } },
      },
    );

    expect(() =>
      invalid.record({ ...event, audit: { category: "data" } }),
    ).toThrow("blocks.demo.options.auditCategory must be a string");
  });

  it("checks each recorded event against the module's catalog", () => {
    const catalog = (events: BlockSqlEvents<OrganizationsEvents>) =>
      createModuleContext("demo", () => ({ ...names, events }), {
        installed: ["demo", "outbox"],
      });

    const member = {
      type: "organization.member_added",
      payload:
        "jsonb_build_object('organizationId', t::text, 'userId', u, 'role', r)",
      subject: "'organizations/' || t::text",
      tenant: "t",
      audit: false,
    } as const;

    const spec = {
      subject: "organizations",
      payload: ["organizationId", "userId", "role"],
    } as const;

    expect(
      catalog({ "organization.member_added": spec }).record(member),
    ).toContain("emit_event('organization.member_added'");
    expect(() => catalog({}).record(member)).toThrow(
      'Module "demo" records "organization.member_added", which its names.events doesn\'t declare',
    );
    expect(() =>
      catalog({
        "organization.member_added": {
          ...spec,
          subject: "organization_members",
        },
      }).record(member),
    ).toThrow("not a kebab-case plural");
    expect(() =>
      catalog({
        "organization.member_added": { ...spec, subject: "members" },
      }).record(member),
    ).toThrow("needs a subject that starts with 'members/'");
    expect(() =>
      catalog({
        "organization.member_added": {
          ...spec,
          payload: [...spec.payload, "previousRole"],
        },
      }).record(member),
    ).toThrow("payload lacks previousRole");
    expect(() =>
      catalog({
        "organization.member_added": { ...spec, payload: ["userId", "role"] },
      }).record(member),
    ).toThrow("has a tenant, so its payload needs organizationId");
    expect(() =>
      catalog({
        "organization.member_added": { ...spec, retries: true },
      }).record(member),
    ).toThrow("needs a key");
    expect(
      catalog({
        "organization.member_added": { ...spec, payload: ["userId", "role"] },
      }).record({ ...member, tenant: "null" }),
    ).toContain("emit_event(");
  });

  it("notifies as the service role and restores the claims", () => {
    expect(all("notifications").notify("v_fields", { indent: "    " })).toBe(
      `if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(v_fields);
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;`,
    );
  });

  it("names the import mode condition", () => {
    expect(all().importing()).toBe("better_supabase.import_run() is not null");
  });

  it("enqueues a deduplicated job", () => {
    expect(all("queue").enqueue("emails", "'{}'::jsonb", "'k'")).toBe(
      `perform "better_supabase"."enqueue_job"(queue => 'emails', payload => '{}'::jsonb, dedupe_key => 'k', dedupe_running => false);`,
    );
  });

  it("reads entitlements, permissions and staff checks", () => {
    expect(all().entitlements("t")).toBeUndefined();
    expect(all().entitlements("t", "'{}'::text[]")).toBe("'{}'::text[]");
    expect(all("entitlements").entitlements("t", "'{}'")).toBe(
      "better_supabase.tenant_entitlements(t)",
    );
    expect(all().can("tenant", "t", "'item.read'")).toBe(
      "coalesce(better_supabase.can('tenant', t, 'item.read'), false)",
    );
    expect(all().staff("'item.manage'")).not.toContain("is_platform");
    expect(all("permissions").staff("'item.manage'")).toContain(
      "coalesce(better_supabase.is_platform('item.manage'), false)",
    );
  });

  it("broadcasts only when Realtime exists", () => {
    expect(all().broadcast("'t'", "'e'", "'{}'::jsonb")).toBe(
      `if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send('{}'::jsonb, 'e', 't', true);
  end if;`,
    );
  });
});

describe("integrates", () => {
  it("lets a module read only what it requires or integrates", () => {
    const ctx = moduleContext("inbox", {}, ["inbox", "queue", "outbox"]);
    expect(ctx.installed("queue")).toBe(true);
    expect(() => ctx.installed("billing")).toThrow(
      'Module "inbox" reads module "billing", which it neither requires nor lists in integrates',
    );
  });

  it("rejects a jobs schema and keeps access functions in better_supabase", () => {
    expect(() => {
      checkModules({ queue: { schema: "app" } });
    }).toThrow("blocks.queue.schema");
    expect(() => {
      checkModules({ queue: { schema: "better_supabase" } });
    }).not.toThrow();
    const layout = { modules: { permissions: { schema: "app" } } };

    const support = moduleContext("impersonation", layout, [
      "memberships",
      "permissions",
      "audit",
      "impersonation",
    ]);

    expect(support.of("permissions").fn("is_platform")).toBe(
      '"better_supabase"."is_platform"',
    );
    expect(support.of("permissions").table("roles")).toContain('"app".');
  });
});

describe("fixed functions", () => {
  it("names the tenant role helpers in better_supabase whatever the tenant schema", () => {
    const flags = moduleContext(
      "flags",
      { modules: { memberships: { schema: "app" }, flags: { schema: "app" } } },
      ["memberships", "flags"],
    );

    const tenant = flags.of("memberships");
    expect(tenant.fn("member_organization_ids")).toBe(
      "better_supabase.member_organization_ids",
    );
    expect(tenant.fn("has_organization_role")).toBe(
      "better_supabase.has_organization_role",
    );
    expect(tenant.fn("membership_role_scope")).toBe(
      '"app"."membership_role_scope"',
    );
  });

  it("reads an unquoted column name, and refuses one mapped to null", () => {
    const organizations = moduleContext("organizations", {
      modules: {
        organizations: {
          columns: { organizations: { id: "team_id", slug: null } },
        },
      },
      ownTables: { "better_supabase.organizations": "app.sql" },
    });

    expect(organizations.colName("organizations", "id")).toBe("team_id");
    expect(() => organizations.colName("organizations", "slug")).toThrow(
      "needs organizations.slug",
    );
  });
});
