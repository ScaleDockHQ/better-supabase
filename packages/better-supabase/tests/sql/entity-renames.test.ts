import { describe, expect, it } from "vitest";

import type { ModuleLayout } from "../../src/sql/module-types.ts";

import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { pluralOf } from "../../src/core/entity-naming.ts";
import { entityRenameChanges, renderModules } from "../../src/sql/index.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";

const BLOCKS = ["tenant", "access", "outbox", "work-items"];

const TASKS: ModuleLayout = {
  modules: {
    "work-items": { entities: { work_item: "task", project: "initiative" } },
  },
};

const body = (module: string, layout: ModuleLayout): string =>
  renderModules(BLOCKS, layout)
    .filter((file) => file.module === module && file.kind === "schema")
    .map((file) => file.contents)
    .join("\n");

describe("blocks.<name>.entities in the SQL", () => {
  it("renames tables, functions, events, permission keys and hooks", () => {
    const sql = body("work-items", TASKS);

    expect(sql).toContain(
      'create table if not exists "better_supabase"."tasks"',
    );
    expect(sql).toContain('"better_supabase"."initiatives"');
    expect(sql).toContain('"better_supabase"."create_task"(');
    expect(sql).toContain("'task.created'");
    expect(sql).toContain("'tasks/'");
    expect(sql).toContain("'taskId'");
    expect(sql).toContain("'tasks.read'");
    expect(sql).toContain('"public"."before_task_create"(');
    expect(sql).toContain(
      "-- @bs-entities work-items work_item=task/tasks project=initiative/initiatives",
    );
  });

  it("writes the default names and no marker without entities", () => {
    const sql = body("work-items", {});

    expect(sql).toContain('"better_supabase"."work_items"');
    expect(sql).toContain("'work_item.created'");
    expect(sql).not.toContain("@bs-entities");
  });

  it("renames the default roles' keys after every block's entities", () => {
    expect(body("access", TASKS)).toContain("'tasks.*'");
    expect(body("access", {})).toContain("'work_items.*'");
  });

  it("keeps the tenant rename out of events, permission keys and hooks", () => {
    const sql = body("work-items", {
      modules: { tenant: { entities: { organization: "workspace" } } },
    });

    expect(sql).toContain("'work_item.created'");
    expect(sql).toContain("'organizationId'");
    expect(sql).toContain("'work_items.read'");
  });

  it("leaves the default nouns only in parameter names, hints and prose", () => {
    const modules = {
      "work-items": {
        entities: {
          work_item: "task",
          project: "initiative",
          iteration: "cycle",
        },
      },
    } as const;

    const names = [...BLOCKS, "pipelines", "rank", "subjects", "notifications"];

    const layout: ModuleLayout = {
      modules,
      subjects: withBlockSubjects({}, names, modules),
    };

    const parameter =
      /\b(?:\w+\.)?(?:work_item|project|iteration)\b(?= uuid|[^_\w'"]|$)/g;

    const left = renderModules(names, layout)
      .flatMap((file) => file.contents.split("\n"))
      .filter((line) => !line.trimStart().startsWith("--"))
      .map((line) =>
        line.replaceAll(/'[^']*\s[^']*'/g, "").replaceAll(parameter, ""),
      )
      .filter((line) =>
        /work_?items?|workItem|projects?(?:_id|Id)|iterations?(?:_id|Id)/.test(
          line,
        ),
      );

    expect(left).toEqual([]);
  });

  const renamable = Object.entries(SQL_MODULES).flatMap(([name, module]) => {
    const entities = Object.entries(module.names?.entities ?? {}).filter(
      ([, entity]) => !entity.global,
    );

    return entities.length === 0 || name === "tenant"
      ? []
      : [[name, entities] as const];
  });

  it.each(renamable)(
    "renames every %s identifier with its entities",
    (name, entities) => {
      const modules = {
        [name]: {
          entities: Object.fromEntries(
            entities.map(([key], index) => [
              key,
              `zq${"abcdefgh".charAt(index)}`,
            ]),
          ),
        },
      };

      const layout: ModuleLayout = {
        modules,
        subjects: withBlockSubjects({}, [name], modules),
      };

      const camel = (value: string): string =>
        value.replaceAll(/_([a-z])/g, (_, letter: string) =>
          letter.toUpperCase(),
        );

      const nouns = entities.map(([, entity]) => ({
        singular: entity.singular,
        plural: entity.plural ?? pluralOf(entity.singular),
      }));

      const parameter = new RegExp(
        String.raw`\b(?:\w+\.)?(?:${nouns.map((noun) => noun.singular).join("|")})\b(?= uuid|[^_\w'"]|$)`,
        "g",
      );

      const leftover = new RegExp(
        String.raw`(?<![a-zA-Z])(?:${nouns
          .flatMap(({ singular, plural }) => [
            String.raw`${plural}(?![a-z])`,
            camel(plural),
            `${singular}_`,
            `${camel(singular)}Id`,
          ])
          .join("|")})`,
      );

      const left = renderModules([name], layout)
        .flatMap((file) => file.contents.split("\n"))
        .filter((line) => !line.trimStart().startsWith("--"))
        .map((line) =>
          line
            .replaceAll(`'${name}'`, "")
            .replaceAll(`'${name}.`, "'")
            .replaceAll(/'[^']*\s[^']*'/g, "")
            .replaceAll(/\bv_\w+/g, "")
            .replaceAll(parameter, ""),
        )
        .filter((line) => leftover.test(line));

      expect(left).toEqual([]);
    },
  );

  it("refuses a rename onto another block's table", () => {
    expect(() =>
      renderModules([...BLOCKS, "deals"], {
        modules: { "work-items": { entities: { work_item: "deal" } } },
      }),
    ).toThrow(
      "blocks.work-items.entities: the work-items block's items table would be named deals, which the deals block already uses",
    );
  });
});

describe("entityRenameChanges", () => {
  const marker = "-- @bs-entities work-items work_item=task/tasks";

  it("reports a module whose entities changed since it was installed", () => {
    expect(entityRenameChanges(["work-items"], "", marker)).toEqual([
      expect.stringContaining(
        "blocks.work-items.entities changed on an installed block (default names to work_item=task/tasks)",
      ),
    ]);
  });

  it("passes unchanged and uninstalled modules", () => {
    expect(entityRenameChanges(["work-items"], marker, marker)).toEqual([]);
    expect(entityRenameChanges([], "", marker)).toEqual([]);
  });
});
