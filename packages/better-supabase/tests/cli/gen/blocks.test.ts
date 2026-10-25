import { describe, expect, it } from "vitest";

import {
  blockConfigEntries,
  blockConfigPath,
  emitBlockConfig,
  schemaExtensions,
} from "../../../src/cli/gen/blocks.ts";
import { renderFiles } from "../../../src/cli/gen/render.ts";
import { resolveConfig } from "../../../src/config/resolve.ts";
import { zod } from "../../../src/generators/zod.ts";
import { loadFixtureSnapshot } from "../fixtures/render.ts";

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
      options: { requireScan: false, publicBuckets: [] },
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
          tasks: { names: { work_item: "task", project: "initiative" } },
        },
      },
      "/project",
    );

    expect(blockConfigEntries(config)["tasks"]?.names).toEqual({
      entities: [
        {
          from: { singular: "work_item", plural: "work_items" },
          to: { singular: "task", plural: "tasks" },
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
          tasks: { names: { work_item: "task" } },
        },
      },
      "/project",
    );

    const contents = emitBlockConfig(config)?.contents ?? "";

    expect(contents).toContain(
      `import {
  type Events,
  type GeneratedBlocks,
  renameBlock,
  type RenamedEvents,
  type RenamedType,
} from "better-supabase/blocks";`,
    );
    expect(contents).toContain(
      '  tasksBlock as defaultTasksBlock,\n} from "better-supabase/blocks/tasks";',
    );
    expect(contents).toContain(
      'export const tasksBlock = renameBlock(defaultTasksBlock, blockConfig["tasks"].names);',
    );
    expect(contents).toContain(
      "export type Task<F extends object = Record<never, never>> = RenamedType<WorkItem<F>, TasksRenames>;",
    );
    expect(contents).toContain(
      "export type TasksEvents = RenamedEvents<DefaultTasksEvents, TasksRenames>;",
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
          tasks: { names: { work_item: "task" } },
          tickets: {
            block: "tasks",
            entities: { work_item: "ticket" },
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
          create_work_item: "create_ticket",
          save_project: "tickets_save_project",
        },
      },
    });
    expect(entries["tickets"]?.uses).toBeUndefined();

    const contents = emitBlockConfig(config)?.contents ?? "";
    expect(contents).toContain(
      'export const tasksBlock = renameBlock(defaultTasksBlock, blockConfig["tasks"].names);',
    );
    expect(contents).toContain(
      'export const ticketsBlock = renameBlock(defaultTasksBlock, blockConfig["tickets"].names);',
    );
    expect(contents).toContain(
      "export type Ticket<F extends object = Record<never, never>> = RenamedType<DefaultWorkItem<F>, TicketsRenames>;",
    );
    expect(contents).toContain(
      "export type TicketsEvents = RenamedEvents<DefaultTasksEvents, TicketsRenames>;",
    );
    expect(contents).toMatch(/BlockEvents = .*TasksEvents & TicketsEvents/);
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
          tasks: { names: { work_item: "task" } },
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

    expect(contents).toContain("export const permissions = {");
    expect(contents).toContain('    write: "tasks.write",');
    expect(contents).toMatch(
      /export type PermissionKey = [^;]*"tasks\.write"/u,
    );
    expect(contents).toContain('export type RoleName = "editor" | "owner";');
    expect(contents).toContain(
      "export const blockEvents: Events<BlockEvents> = {",
    );
    expect(contents).toContain('    "task.created",');
    expect(contents).not.toContain('"work_item.created"');
    expect(contents).toMatch(/export type BlockEvents = [^;]*TasksEvents/u);
    expect(contents).toContain("export const topics = {");
    expect(contents).toMatch(/notifications:\$\{String\(v\.userId\)\}/u);
    expect(contents).toContain("export const paths = {");
    expect(contents).toContain('export type SettingKey = "theme";');
    expect(contents).toContain('export type MeterName = "seats";');
  });

  it("writes a url for every subject type with a template", () => {
    const config = resolveConfig(
      {
        gen: { casing: "camel" },
        records: {
          customer: {
            table: "public.customers",
            tenant: "organization_id",
            url: "/customers/{id}",
          },
          note: { table: "public.notes", tenant: false },
        },
        tables: {
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
          tasks: { names: { work_item: { name: "task", url: "/tasks/{id}" } } },
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
        gen: { output: "app/lib/db/generated.ts" },
        blocks: ["memberships", "attachments"],
      },
      "/project",
    );

    const file = emitBlockConfig(config, { runtimeImport: "better-supabase" });
    expect(file?.path).toBe("app/lib/db/blocks.generated.ts");
    expect(blockConfigPath(config)).toBe("app/lib/db/blocks.generated.ts");
    expect(file?.contents).toContain(
      'import {\n  type Events,\n  type GeneratedBlocks,\n} from "better-supabase/blocks";',
    );
    expect(file?.contents).toContain(
      `  attachments: {
    schema: "better_supabase",
    options: {
      publicBuckets: [],
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
    expect(file?.contents).toContain("offline: true");
    expect(file?.contents).not.toContain("requireScan");
  });

  it("declares the events app tables emit", () => {
    const config = resolveConfig(
      {
        blocks: { memberships: {}, outbox: {} },
        tables: {
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
      'import {\n  type AppTableEventData,\n  defineEvents,\n  event,\n  type GeneratedBlocks,\n} from "better-supabase/blocks";',
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
        gen: { output: "src/db/generated.ts" },
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
          { auth: { organization: { column: "org_id", onMissing: "error" } } },
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
        gen: { output: "src/db/generated.ts", generators: [zod()] },
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
      "export const schema: Schema<Models, Database, Functions> = defineSchema(meta);",
    );
    expect(bare).not.toContain("trashExtension");
  });
});
