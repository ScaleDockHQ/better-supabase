import { describe, expect, it } from "vitest";

import {
  blockConfigEntries,
  blockConfigPath,
  emitBlockConfig,
} from "../../../src/cli/gen/blocks.ts";
import { resolveConfig } from "../../../src/config/resolve.ts";

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
      options: { requireScan: false },
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
      requireScan: true,
    },
  },`,
    );
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
