import { describe, expect, it } from "vitest";

import type { BlockSqlFile } from "../../src/sql/module-types.ts";

import { resolveConfig } from "../../src/config/resolve.ts";
import {
  createdNames,
  renameIdentifiers,
} from "../../src/sql/instance-names.ts";
import { moduleLayout } from "../../src/sql/layout.ts";
import { moduleFileVersion } from "../../src/sql/markers.ts";
import { moduleContext } from "../../src/sql/module-context.ts";
import { rolesOf } from "../../src/sql/modules/permissions-model.ts";
import { renderBlocks } from "../../src/sql/render.ts";

const config = resolveConfig(
  {
    blocks: {
      tags: {},
      labels: { block: "tags", entities: { tag: "label" } },
      pipelines: {},
      hiringPipelines: {
        block: "pipelines",
        entities: { pipeline: "hiring_pipeline" },
      },
      tasks: { uses: { pipelines: "pipelines" } },
      tickets: {
        block: "tasks",
        entities: { work_item: "ticket" },
        uses: { pipelines: "hiringPipelines" },
      },
    },
  },
  "/app",
);

const files = renderBlocks(config.blockNames, moduleLayout(config));

const schemaOf = (instance: string): BlockSqlFile => {
  const file = files.find(
    (each) =>
      each.kind === "schema" && (each.instance ?? each.module) === instance,
  );

  if (!file) {
    throw new Error(`No schema file for ${instance}`);
  }

  return file;
};

describe("block instances", () => {
  it("writes each instance its own files, numbered with its block", () => {
    const paths = files.map((file) => file.path);

    expect(new Set(paths).size).toBe(paths.length);
    expect(schemaOf("labels").path).toMatch(/_labels\.sql$/);
    expect(schemaOf("hiringPipelines").path).toMatch(/_hiring_pipelines\.sql$/);
    expect(schemaOf("tickets").path).toMatch(/_tickets\.sql$/);
  });

  it("marks an instance with its block", () => {
    expect(moduleFileVersion(schemaOf("tickets").contents)).toMatchObject({
      module: "tickets",
      block: "tasks",
    });
    expect(moduleFileVersion(schemaOf("tasks").contents)).not.toHaveProperty(
      "block",
    );
  });

  it("gives every instance names its block's other instance doesn't create", () => {
    const shared = new Map<string, number>();

    for (const file of files) {
      if (file.kind === "schema" && file.instance === undefined) {
        for (const name of createdNames(file.contents)) {
          shared.set(name, (shared.get(name) ?? 0) + 1);
        }
      }
    }

    for (const [instance, block] of [
      ["labels", "tags"],
      ["hiringPipelines", "pipelines"],
      ["tickets", "tasks"],
    ] as const) {
      const own = createdNames(schemaOf(block).contents);

      const clashes = [...createdNames(schemaOf(instance).contents)].filter(
        (name) => own.has(name) && (shared.get(name) ?? 0) < 2,
      );

      expect({ instance, clashes }).toStrictEqual({ instance, clashes: [] });
    }
  });

  it("reads the instance its uses names", () => {
    const layout = moduleLayout(config);
    const installed = config.blockNames;

    expect(
      moduleContext("tasks", layout, installed, "tickets")
        .of("pipelines")
        .table("pipelines"),
    ).toBe('"better_supabase"."hiring_pipelines"');
    expect(
      moduleContext("tasks", layout, installed)
        .of("pipelines")
        .table("pipelines"),
    ).toBe('"better_supabase"."pipelines"');
    expect(
      moduleContext("tags", layout, installed, "labels").table("taggings"),
    ).toBe('"better_supabase"."labels_taggings"');
  });

  it("grants the default roles each instance's permission keys", () => {
    const roles = rolesOf(
      moduleContext("permissions", moduleLayout(config), config.blockNames),
    );

    expect(roles["admin"]).toContain("work_items.*");
    expect(roles["admin"]).toContain("tickets.*");
  });

  it("records the instance and its block", () => {
    const data = files.find(
      (file) => file.kind === "data" && file.instance === "tickets",
    );

    expect(data?.contents).toContain("values ('tickets', 'tasks', ");
  });

  it("asks a second instance to rename its record entities", () => {
    expect(() =>
      renderBlocks(
        ["tasks"],
        moduleLayout(
          resolveConfig(
            { blocks: { tasks: {}, tickets: { block: "tasks" } } },
            "/app",
          ),
        ),
      ),
    ).toThrow('this instance renames "work_item"');
  });
});

describe("renameIdentifiers", () => {
  const renames = new Map([["tags_name_idx", "labels_tags_name_idx"]]);

  it("renames identifiers and qualified names in strings, not text", () => {
    expect(
      renameIdentifiers(
        [
          'drop index if exists "tags_name_idx";',
          "create index tags_name_idx on t (name);",
          "raise exception 'tags_name_idx failed';",
          "select 'public.tags_name_idx';",
          "-- tags_name_idx",
        ].join("\n"),
        renames,
      ),
    ).toBe(
      [
        'drop index if exists "labels_tags_name_idx";',
        "create index labels_tags_name_idx on t (name);",
        "raise exception 'tags_name_idx failed';",
        "select 'public.labels_tags_name_idx';",
        "-- tags_name_idx",
      ].join("\n"),
    );
  });
});
