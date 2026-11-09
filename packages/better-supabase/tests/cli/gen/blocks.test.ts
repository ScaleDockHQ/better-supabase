import { describe, expect, it } from "vitest";

import type { ResolveInput } from "../../../src/config/resolve.ts";
import type { PresetCatalog } from "../../../src/preset/catalog-types.ts";

import {
  blockConfigEntries,
  blockConfigPath,
  emitBlockConfig,
  emitBlockConfigModule,
  emitClientBlocks,
  schemaExtensions,
} from "../../../src/cli/gen/blocks.ts";
import { renderFiles } from "../../../src/cli/gen/render.ts";
import { emitServerBlocks } from "../../../src/cli/gen/server-blocks.ts";
import { resolveConfig as resolveDefault } from "../../../src/config/resolve.ts";
import { zod } from "../../../src/generators/zod.ts";
import { PRESET_CATALOG } from "../../../src/preset/catalog.generated.ts";
import { blockTables } from "../../../src/sql/index.ts";
import { loadFixtureSnapshot } from "../fixtures/render.ts";

/**
 * These tests read the single-module layout; the default layout has its own in
 * render.test.ts.
 */
function resolveConfig(input: ResolveInput, root: string) {
  return resolveDefault(
    {
      ...input,
      gen: { tableModules: false, blockModules: false, ...input.gen },
    },
    root,
  );
}

describe("blocks.generated.ts", () => {
  it("writes each installed block's schema, API schema and shared options", () => {
    const config = resolveConfig(
      {
        database: { sql: { api: "api" } },
        blocks: {
          memberships: {},
          permissions: {},
          attachments: { options: { requireScan: false, bucket: "files" } },
          notifications: { schema: "app_blocks" },
          comments: { api: false },
        },
      },
      "/project",
    );

    const entries = blockConfigEntries(config);
    expect(entries["attachments"]).toEqual({
      schema: "better_supabase",
      api: "api",
      options: { requireScan: false, publicBuckets: [], topic: "attachments" },
    });
    expect(entries["notifications"]).toEqual({
      schema: "app_blocks",
      api: "api",
      options: { topic: "notifications:{userId}" },
    });
    expect(entries["comments"]).toEqual({
      schema: "better_supabase",
      options: {},
    });
    // Blocks with only SQL get an entry too, for `block.using(...)`.
    expect(entries["memberships"]).toEqual({
      schema: "better_supabase",
      api: "api",
      options: {},
    });
  });

  it("writes the app's employee status values for the create input's type", () => {
    const config = resolveConfig(
      {
        blocks: {
          employees: {
            values: {
              employees: {
                status: { active: ["active", "offboarding"], on_leave: "away" },
              },
            },
          },
        },
      },
      "/project",
    );

    expect(blockConfigEntries(config)["employees"]?.options).toMatchObject({
      statuses: ["active", "offboarding", "away"],
    });
  });

  it("writes the function names the tenant name and blocks.<name>.functions give", () => {
    const config = resolveConfig(
      {
        blocks: {
          memberships: { names: { organization: "workspace" } },
          organizations: {},
          tags: { functions: { create_tag: "make_tag" } },
          permissions: {
            model: "custom",
            functions: { can: "public.can({scope}, {id}, {permission})" },
          },
        },
      },
      "/project",
    );

    const entries = blockConfigEntries(config);
    expect(entries["organizations"]?.names).toEqual({ tenant: "workspace" });
    expect(entries["tags"]?.names).toEqual({
      tenant: "workspace",
      functions: { create_tag: "make_tag" },
    });
    expect(entries["permissions"]?.names).toEqual({ tenant: "workspace" });

    const plain = blockConfigEntries(
      resolveConfig({ blocks: ["tags"] }, "/project"),
    );

    expect(plain["tags"]).not.toHaveProperty("names");
  });

  it("writes the tenant columns blocks.<name>.columns renames", () => {
    const config = resolveConfig(
      {
        blocks: {
          memberships: {},
          permissions: {},
          tasks: { columns: { items: { tenant: "org_id" } } },
        },
      },
      "/project",
    );

    expect(blockConfigEntries(config)["tasks"]?.names).toEqual({
      columns: { org_id: "tenant_id" },
    });
  });

  it("leaves out a tenant column renamed to another column's default name", () => {
    const config = resolveConfig(
      {
        blocks: {
          memberships: {},
          permissions: {},
          tasks: { columns: { items: { tenant: "project_id" } } },
        },
      },
      "/project",
    );

    expect(blockConfigEntries(config)["tasks"]?.names).toBeUndefined();
  });

  it("writes the tenant column sql.tenantColumn gives a block's tables", () => {
    const entries = blockConfigEntries(
      resolveConfig(
        {
          blocks: ["quotes"],
          database: { sql: { tenantColumn: "organization_id" } },
        },
        "/project",
      ),
    );

    expect(entries["quotes"]?.names).toEqual({
      tenantColumn: "organization_id",
    });
    expect(entries["memberships"]).not.toHaveProperty("names");
  });

  it("writes the tenant column a block maps on all of its tables", () => {
    const entries = blockConfigEntries(
      resolveConfig(
        {
          blocks: {
            quotes: {
              columns: {
                quotes: { tenant: "org_id" },
                lines: { tenant: "org_id" },
                versions: { tenant: "org_id" },
                versionLines: { tenant: "org_id" },
                taxLines: { tenant: "org_id" },
              },
            },
          },
        },
        "/project",
      ),
    );

    expect(entries["quotes"]?.names).toEqual({ tenantColumn: "org_id" });
  });

  it("writes the entities blocks.<name>.entities renames", () => {
    const config = resolveConfig(
      {
        blocks: {
          memberships: {},
          permissions: {},
          tasks: { names: { task: "ticket", project: "initiative" } },
        },
      },
      "/project",
    );

    expect(blockConfigEntries(config)["tasks"]?.names).toEqual({
      functions: {
        archive_task: "archive_ticket",
        archive_tasks: "archive_tickets",
        clone_task: "clone_ticket",
        create_task: "create_ticket",
        delete_task: "delete_ticket",
        delete_task_checklist_item: "delete_ticket_checklist_item",
        delete_tasks: "delete_tickets",
        get_task: "get_ticket",
        list_task_checklist: "list_ticket_checklist",
        list_task_materials: "list_ticket_materials",
        list_task_specification: "list_ticket_specification",
        list_tasks: "list_tickets",
        save_project: "save_initiative",
        save_task_checklist_item: "save_ticket_checklist_item",
        save_task_material_line: "save_ticket_material_line",
        save_task_specification_line: "save_ticket_specification_line",
        set_task_assignees: "set_ticket_assignees",
        task_tree: "ticket_tree",
        update_tasks: "update_tickets",
      },
      entities: [
        {
          from: { singular: "task", plural: "tasks" },
          to: { singular: "ticket", plural: "tickets" },
        },
        {
          from: { singular: "project", plural: "projects" },
          to: { singular: "initiative", plural: "initiatives" },
        },
      ],
      events: [
        {
          from: { singular: "task", plural: "tasks" },
          to: { singular: "ticket", plural: "tickets" },
          keyed: true,
        },
        {
          from: { singular: "project", plural: "projects" },
          to: { singular: "initiative", plural: "initiatives" },
        },
      ],
    });
  });

  it("writes the renamed block and its renamed types", () => {
    const config = resolveConfig(
      {
        blocks: {
          memberships: {},
          permissions: {},
          tasks: { names: { task: "ticket" } },
        },
      },
      "/project",
    );

    const contents = emitBlockConfig(config)?.contents ?? "";

    expect(contents).toContain(
      `import {
  type EventRenamesOf,
  type Events,
  renameBlock,
  type RenamedEvents,
  type RenamedType,
} from "better-supabase/blocks";`,
    );
    expect(contents).toContain(
      '  tasksBlock,\n} from "better-supabase/blocks/tasks";',
    );
    expect(contents).toContain(
      'export const ticketsBlock = renameBlock(tasksBlock, blockConfig["tasks"].names);',
    );
    expect(contents).toContain(
      "export type Ticket<F extends object = Record<never, never>> = RenamedType<Task<F>, TasksRenames>;",
    );
    expect(contents).toContain(
      "export type TicketsEvents = RenamedEvents<TasksEvents, TasksRenamesEvents>;",
    );
    expect(contents).toContain("  type Project as DefaultProject,");
    expect(contents).toContain(
      "export type Project = RenamedType<DefaultProject, TasksRenames>;",
    );
    expect(contents).not.toContain("TasksOptions");
  });

  it("marks the instances PowerSync doesn't sync as needing the network", () => {
    const blocks = {
      memberships: {},
      permissions: {},
      notifications: {},
      tags: {},
    };

    const synced = emitBlockConfig(
      resolveConfig(
        { blocks, gen: { powersync: { instances: ["notifications"] } } },
        "/project",
      ),
    )?.contents;

    const online = emitBlockConfig(
      resolveConfig({ blocks }, "/project"),
    )?.contents;

    expect(synced).toContain(
      "  /** Needs the network on native. */\n  tags: tagsBlockInstance,",
    );
    expect(synced).toContain("\n  notifications: notificationsBlockInstance,");
    expect(synced).not.toContain(
      "  /** Needs the network on native. */\n  notifications:",
    );
    expect(online).not.toContain("Needs the network on native.");
  });

  it("writes an entry and a renamed block for each instance of a block", () => {
    const config = resolveConfig(
      {
        blocks: {
          pipelines: {},
          tasks: { names: { task: "todo" } },
          tickets: {
            block: "tasks",
            entities: { task: "ticket" },
            uses: { pipelines: "pipelines" },
          },
        },
      },
      "/project",
    );

    const entries = blockConfigEntries(config);
    expect(entries["tickets"]).toMatchObject({
      block: "tasks",
      names: {
        functions: {
          create_task: "create_ticket",
          save_project: "tickets_save_project",
        },
      },
    });
    expect(entries["tickets"]?.uses).toBeUndefined();

    const contents = emitBlockConfig(config)?.contents ?? "";
    expect(contents).toContain(
      'export const todosBlock = renameBlock(defaultTasksBlock, blockConfig["tasks"].names);',
    );
    expect(contents).toContain(
      'export const ticketsBlock = renameBlock(defaultTasksBlock, blockConfig["tickets"].names);',
    );
    expect(contents).toContain(
      "export type Ticket<F extends object = Record<never, never>> = RenamedType<DefaultTask<F>, TicketsRenames>;",
    );
    expect(contents).toContain(
      "export type TicketsEvents = RenamedEvents<DefaultTasksEvents, TicketsRenamesEvents>;",
    );
    expect(contents).toMatch(/BlockEvents = .*TodosEvents & TicketsEvents/);
  });

  it("leaves out the block's own entry when only another name installs it", () => {
    const entries = blockConfigEntries(
      resolveConfig(
        { blocks: { labels: { block: "tags", entities: { tag: "label" } } } },
        "/project",
      ),
    );

    expect(entries["tags"]).toBeUndefined();
    expect(entries["labels"]?.block).toBe("tags");
  });

  it("writes typed name constants for permissions, roles, events and keys", () => {
    const config = resolveConfig(
      {
        blocks: {
          memberships: {},
          permissions: { roles: { owner: ["*"], editor: ["tasks.write"] } },
          notifications: {},
          tasks: {},
          settings: {
            options: { schemas: { user: { theme: { type: "string" } } } },
          },
          usage: { options: { meters: { seats: { aggregate: "count" } } } },
        },
        database: { buckets: { avatars: { path: "{userId}/{name}" } } },
      },
      "/project",
    );

    const contents = emitBlockConfig(config)?.contents ?? "";
    const data = emitBlockConfigModule(config)?.contents ?? "";

    expect(data).toContain("export const permissions = {");
    expect(data).toContain('    write: "tasks.write",');
    expect(data).toMatch(/export type PermissionKey = [^;]*"tasks\.write"/u);
    expect(contents).toContain(
      'export { permissions, type PermissionKey } from "./blocks.config.ts";',
    );
    expect(contents).toContain('export type RoleName = "editor" | "owner";');
    expect(contents).toContain(
      "export const blockEvents: Events<BlockEvents> = {",
    );
    expect(contents).toContain('    "task.created",');
    expect(contents).not.toContain('"ticket.created"');
    expect(contents).toMatch(/export type BlockEvents = [^;]*TasksEvents/u);
    expect(contents).toContain("export const topics = {");
    expect(contents).toMatch(/notifications:\$\{String\(v\.userId\)\}/u);
    expect(contents).toContain("export const paths = {");
    expect(contents).toContain('export type SettingKey = "theme";');
    expect(contents).toContain('export type MeterName = "seats";');
  });

  it("writes the keys of record actions, skipping actions granted only per row", () => {
    const config = resolveConfig(
      {
        recordTypes: {
          file: {
            table: "public.files",
            permissions: {
              read: "file.read",
              share: { key: "file.share", rows: "file" },
              write: { owner: "owner_id" },
            },
          },
        },
        blocks: { memberships: {}, permissions: {}, subjects: {} },
      },
      "/project",
    );

    const contents = emitBlockConfigModule(config)?.contents ?? "";

    expect(contents).toContain('    share: "file.share",');
    expect(contents).toContain('    read: "file.read",');
    expect(contents).not.toMatch(/ {4}write: /u);
  });

  it("writes a url for every subject type with a template", () => {
    const config = resolveConfig(
      {
        gen: { casing: "camel" },
        recordTypes: {
          customer: {
            table: "public.customers",
            tenant: "organization_id",
            url: "/customers/{id}",
          },
          note: { table: "public.notes", tenant: false },
        },
        appTables: {
          projects: {
            columns: { name: { type: "text" } },
            subject: {
              type: "project",
              url: "/projects/{id}/{organization_id}",
            },
          },
        },
        blocks: { memberships: {}, permissions: {}, subjects: {} },
      },
      "/project",
    );

    const contents = emitBlockConfig(config)?.contents ?? "";

    expect(contents).toContain("export const urls = {");
    expect(contents).toMatch(/ {2}customer: .*\/customers\//u);
    expect(contents).toMatch(/ {2}project: .*organizationId/u);
    expect(contents).not.toMatch(/ {2}note: /u);
  });

  it("writes a block entity's url, and a constant path without arguments", () => {
    const config = resolveConfig(
      {
        blocks: {
          memberships: {},
          subjects: {},
          tasks: { names: { task: { name: "task", url: "/tasks/{id}" } } },
          deals: { names: { deal: { url: "/crm/deals" } } },
        },
      },
      "/project",
    );

    const contents = emitBlockConfig(config)?.contents ?? "";

    expect(contents).toMatch(/ {2}task: \(v: \{ readonly id: /u);
    expect(contents).toContain('  deal: () => "/crm/deals",');
  });

  it("leaves out tenant and access in user scope", () => {
    const entries = blockConfigEntries(
      resolveConfig(
        { database: { sql: { owner: "user" } }, blocks: ["tags"] },
        "/project",
      ),
    );

    expect(Object.keys(entries)).toContain("tags");
    expect(Object.keys(entries)).not.toContain("memberships");
  });

  it("emits a typed module next to the main generated module", () => {
    const config = resolveConfig(
      {
        gen: { file: "app/lib/db/generated.ts" },
        blocks: ["memberships", "attachments"],
      },
      "/project",
    );

    const file = emitBlockConfig(config, { runtimeImport: "better-supabase" });
    expect(file?.path).toBe("app/lib/db/blocks.generated.ts");
    expect(blockConfigPath(config)).toBe("app/lib/db/blocks.generated.ts");
    expect(file?.contents).toContain(
      'import {\n  blockRead,\n  type Events,\n} from "better-supabase/blocks";',
    );
    expect(
      emitBlockConfigModule(config, { runtimeImport: "better-supabase" })
        ?.contents,
    ).toContain(
      `  attachments: {
    schema: "better_supabase",
    options: {
      publicBuckets: [],
      topic: "attachments",
    },
  },`,
    );
  });

  it("passes offline, and leaves requireScan to the client's default", () => {
    const config = resolveConfig(
      {
        blocks: {
          memberships: {},
          attachments: { options: { offline: true } },
        },
      },
      "/project",
    );

    const file = emitBlockConfig(config, { runtimeImport: "better-supabase" });
    const module = emitBlockConfigModule(config)?.contents;
    expect(module).toContain("offline: true");
    expect(module).not.toContain("requireScan");
    expect(file?.contents).toContain('from "./blocks.config.ts"');
  });

  it("declares the events app tables emit", () => {
    const config = resolveConfig(
      {
        blocks: { memberships: {}, outbox: {} },
        appTables: {
          tasks: { subject: { type: "task" }, events: true },
          notes: { events: { on: ["deleted"] } },
          files: {},
        },
      },
      "/project",
    );

    const contents =
      emitBlockConfig(config, { runtimeImport: "better-supabase" })?.contents ??
      "";

    expect(contents).toContain(
      'import {\n  type AppTableEventData,\n  defineEvents,\n  event,\n} from "better-supabase/blocks";',
    );
    expect(contents).toContain(
      'export const appTableEvents = defineEvents({\n  "task.created": event<AppTableEventData>(),\n  "task.updated": event<AppTableEventData>(),\n  "task.deleted": event<AppTableEventData>(),\n  "notes.deleted": event<AppTableEventData>(),\n});',
    );
    expect(contents).toContain('  "notes.deleted": true,\n} as const;');
  });

  it("lists an event two blocks emit once", () => {
    const contents =
      emitBlockConfig(
        resolveConfig(
          { blocks: { memberships: {}, organizations: {}, waitlist: {} } },
          "/project",
        ),
      )?.contents ?? "";

    expect(contents.match(/"organization\.member_added": true/g)).toHaveLength(
      1,
    );
  });

  it("writes nothing when the config installs no blocks", () => {
    expect(emitBlockConfig(resolveConfig({}, "/project"))).toBeUndefined();
  });
});

describe("block reads in blocks.generated.ts", () => {
  it("writes a typed read and its result type for each block that ships one", () => {
    const config = resolveConfig(
      {
        blocks: {
          memberships: {},
          permissions: {},
          subjects: {},
          pipelines: {},
          deals: {},
        },
      },
      "/project",
    );

    const file = emitBlockConfig(config);

    expect(file?.contents).toContain("export const reads = {");
    expect(file?.contents).toContain(
      'board: blockRead<DealsBoardArgs, DealsBoardResult>("deal_board", { pipelineId: "pipeline" }, ["pipeline_stages", "deals"], "better_supabase")',
    );
    expect(file?.contents).toContain("export type DealsBoardResult = {");
    expect(file?.contents).toContain("readonly weighted: readonly {");
  });
});

describe("block reads served from the app's views", () => {
  const config = resolveConfig(
    { blocks: { organizations: {}, memberships: {}, attachments: {} } },
    "/project",
  );

  const tables = blockTables(config).byBlock;

  it("lists the views over a table a read lists", () => {
    const file = emitBlockConfig(config, {
      viewFanOut: {
        views: new Map([
          ["better_supabase.attachments", ["jobAttachments"]],
          ["better_supabase.memberships", ["memberships"]],
        ]),
        tables,
      },
    });

    expect(file?.contents).toContain(
      '["attachments", "jobAttachments"], "better_supabase")',
    );

    // organization_overview reads tables of the memberships instance.
    expect(file?.contents).toMatch(
      /\["organizations", "memberships", "invitations"\], "better_supabase"/,
    );
  });

  it("writes the plain lists without views", () => {
    expect(emitBlockConfig(config)?.contents).toContain(
      '["attachments"], "better_supabase")',
    );
  });
});

describe("schemaExtensions", () => {
  it("lists the repository extension of each installed block", () => {
    expect(
      schemaExtensions(
        resolveConfig(
          {
            blocks: {
              "updated-at": {},
              trash: { options: { deletedAt: "archived_at" } },
              comments: {},
            },
          },
          "/project",
        ),
      ),
    ).toEqual([
      { export: "updatedAtExtension", subpath: "blocks/updated-at", args: "" },
      { export: "trashExtension", subpath: "blocks/trash", args: "" },
    ]);
  });

  it("passes stamp trigger to the updated-at and created-by extensions", async () => {
    const config = resolveConfig(
      {
        blocks: {
          "created-by": { options: { stamp: "trigger" } },
          "updated-at": { options: { stamp: "trigger" } },
          trash: {},
        },
        gen: { file: "src/db/generated.ts" },
      },
      "/project",
    );

    expect(schemaExtensions(config)).toEqual([
      {
        export: "createdByExtension",
        subpath: "blocks/created-by",
        args: '{ stamp: "trigger" }',
      },
      {
        export: "updatedAtExtension",
        subpath: "blocks/updated-at",
        args: '{ stamp: "trigger" }',
      },
      { export: "trashExtension", subpath: "blocks/trash", args: "" },
    ]);

    const main = (
      await renderFiles(config, await loadFixtureSnapshot(), {})
    ).find((file) => file.path === "src/db/generated.ts")?.contents;

    expect(main).toContain(
      'const extensions: Extensions = [createdByExtension({ stamp: "trigger" }), updatedAtExtension({ stamp: "trigger" }), trashExtension()];',
    );
    expect(() =>
      schemaExtensions(
        resolveConfig(
          // @ts-expect-error -- stamp takes "client" or "trigger"
          { blocks: { "updated-at": { options: { stamp: "db" } } } },
          "/project",
        ),
      ),
    ).toThrow('blocks.updated-at.options.stamp must be "client" or "trigger"');
  });

  it("scopes by the organization column without the memberships block", () => {
    expect(
      schemaExtensions(
        resolveConfig(
          { auth: { tenant: { column: "org_id", onMissing: "error" } } },
          "/project",
        ),
      ),
    ).toEqual([
      {
        export: "membershipsExtension",
        subpath: "blocks/memberships",
        args: expect.stringContaining('onMissing: "error"'),
      },
    ]);
    expect(schemaExtensions(resolveConfig({}, "/project"))).toEqual([]);
  });

  it("puts the extensions and validation on the generated schema", async () => {
    const config = resolveConfig(
      {
        blocks: { trash: { options: { deletedAt: "archived_at" } } },
        gen: { file: "src/db/generated.ts", generators: [zod()] },
      },
      "/project",
    );

    const snapshot = await loadFixtureSnapshot();

    const main = (await renderFiles(config, snapshot, {})).find(
      (file) => file.path === "src/db/generated.ts",
    )?.contents;

    expect(main).toContain(
      'import { trashExtension } from "better-supabase/blocks/trash";',
    );
    expect(main).toContain('import { validators } from "./generated.zod.ts";');
    expect(main).toContain(
      "type Extensions = readonly [ReturnType<typeof trashExtension>, ReturnType<typeof validation>];",
    );
    expect(main).toContain(
      "ExtensionsOf<Extensions>> = defineSchema(meta, extensions);",
    );

    const bare = (
      await renderFiles(config, snapshot, { extensions: false })
    ).find((file) => file.path === "src/db/generated.ts")?.contents;

    expect(bare).toContain(
      "export const schema: Schema<Models, Database, Functions, SubjectType> = defineSchema(meta);",
    );
    expect(bare).not.toContain("trashExtension");
  });

  describe("composite blocks", () => {
    const catalog: PresetCatalog = {
      ...PRESET_CATALOG,
      manifests: [
        ...PRESET_CATALOG.manifests,
        {
          name: "talk",
          sql: [],
          category: "collaboration",
          client: null,
          consumes: {},
          provides: [],
          composes: ["comments", "tags"],
        },
      ],
    };

    const withParts = resolveConfig(
      { blocks: { memberships: {}, permissions: {}, comments: {}, tags: {} } },
      "/project",
    );

    it("writes an entry for a composite without glue SQL once its parts are installed", () => {
      expect(blockConfigEntries(withParts, catalog)["talk"]).toEqual({
        schema: "better_supabase",
        options: {},
      });
    });

    it("leaves the composite out while a part is missing", () => {
      const missing = resolveConfig(
        { blocks: { memberships: {}, permissions: {}, comments: {} } },
        "/project",
      );

      expect(blockConfigEntries(missing, catalog)["talk"]).toBeUndefined();
    });
  });
});

describe("blocks.client.ts", () => {
  const install = { memberships: {}, attachments: {}, tags: {} };

  it("wires only the listed instances, each from its own subpath", () => {
    const config = resolveConfig(
      { blocks: install, gen: { clientBlocks: ["tags"] } },
      "/project",
    );

    const file = emitClientBlocks(config);

    expect(file?.path).toBe("src/lib/supabase/blocks.client.ts");
    expect(file?.contents).toContain('from "better-supabase/blocks/tags"');
    expect(file?.contents).not.toContain("blocks/attachments");
    expect(file?.contents).not.toContain("blocks.generated");
    expect(file?.contents).toContain(
      "export const clientBlocks = defineBlocks(blockConfig, instances);",
    );
  });

  it("writes nothing without a list, and rejects an unknown instance", () => {
    expect(
      emitClientBlocks(resolveConfig({ blocks: install }, "/project")),
    ).toBeUndefined();

    expect(() =>
      emitClientBlocks(
        resolveConfig(
          { blocks: install, gen: { clientBlocks: ["nope"] } },
          "/project",
        ),
      ),
    ).toThrow(/doesn't install/);
  });

  it("rejects a listed block without a client", () => {
    expect(() =>
      emitClientBlocks(
        resolveConfig(
          {
            blocks: { ...install, "updated-at": {} },
            gen: { clientBlocks: ["updated-at"] },
          },
          "/project",
        ),
      ),
    ).toThrow(/no client/);
  });

  it("writes nothing when no block is installed", () => {
    const config = resolveConfig(
      { gen: { clientBlocks: ["tags"] } },
      "/project",
    );

    expect(emitClientBlocks(config)).toBeUndefined();
    expect(emitBlockConfigModule(config)).toBeUndefined();
  });
});

describe("blocks.<name>.ts", () => {
  const install = { memberships: {}, attachments: {}, tags: {} };

  const configOf = (serverBlocks: Record<string, readonly string[]>) =>
    resolveConfig({ blocks: install, gen: { serverBlocks } }, "/project");

  it("writes one set per name over only the listed instances", () => {
    const [file, ...rest] = emitServerBlocks(configOf({ shell: ["tags"] }));

    expect(rest).toEqual([]);
    expect(file?.path).toBe("src/lib/supabase/blocks.shell.ts");
    expect(file?.contents).toContain('from "better-supabase/blocks/tags"');
    expect(file?.contents).not.toContain("blocks/attachments");
    expect(file?.contents).not.toContain('from "./blocks.generated');
    expect(file?.contents).toContain("export const shellInstances = {");

    expect(file?.contents).toContain(
      "export const shellBlocks = defineBlocks(blockConfig, shellInstances);",
    );
  });

  it("writes nothing without sets", () => {
    expect(
      emitServerBlocks(resolveConfig({ blocks: install }, "/project")),
    ).toEqual([]);
  });

  it("rejects an unknown instance and a block without a client", () => {
    expect(() => emitServerBlocks(configOf({ shell: ["nope"] }))).toThrow(
      /gen\.serverBlocks\.shell lists "nope", which `blocks` doesn't install/,
    );

    expect(() =>
      emitServerBlocks(
        resolveConfig(
          {
            blocks: { ...install, "updated-at": {} },
            gen: { serverBlocks: { shell: ["updated-at"] } },
          },
          "/project",
        ),
      ),
    ).toThrow(/no client/);
  });

  it("fails when a listed block needs a port no listed block provides", () => {
    const needy: PresetCatalog = {
      ...PRESET_CATALOG,
      manifests: PRESET_CATALOG.manifests.map((manifest) =>
        manifest.name === "tags"
          ? { ...manifest, consumes: { notifier: "required" } }
          : manifest,
      ),
    };

    const config = configOf({
      shell: ["tags"],
      both: ["tags", "notifications"],
    });

    expect(() => emitServerBlocks(config, { catalog: needy })).toThrow(
      /gen\.serverBlocks\.shell lists "tags", which needs a block that provides the notifier port/,
    );
  });
});

describe("columns from the app's schema files", () => {
  it("types a block's fields with the columns app files add to its table", () => {
    const config = resolveConfig({ blocks: ["memberships", "tags"] }, "/p");

    expect(
      blockConfigEntries(config, undefined, {
        "better_supabase.tags": [{ name: "region", type: "text not null" }],
      })["tags"]?.columns,
    ).toEqual({ region: "text not null" });
    expect(blockConfigEntries(config)["tags"]?.columns).toBeUndefined();
  });
});
