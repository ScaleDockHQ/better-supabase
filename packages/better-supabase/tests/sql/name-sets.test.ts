import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import type { BlockSql } from "../../src/sql/module-types.ts";

import { BLOCK_MANIFESTS } from "../../src/blocks/registry.ts";
import { SQL_MODULES } from "../../src/sql/index.ts";
import { formatNameRegistry, moduleNameSet } from "../../src/sql/name-sets.ts";

const FILE = join(
  import.meta.dirname,
  "../../src/blocks/name-registry.generated.ts",
);

describe("the block names registry", () => {
  it("matches the SQL modules (run `pnpm catalog` when it doesn't)", () => {
    expect(readFileSync(FILE, "utf-8")).toBe(
      formatNameRegistry(Object.values(SQL_MODULES)),
    );
  });

  it("covers every module a block manifest installs", () => {
    const installed = new Set(BLOCK_MANIFESTS.flatMap((block) => block.sql));
    const named = new Set(Object.keys(SQL_MODULES));

    for (const name of installed) {
      expect(named).toContain(name);
    }
  });

  it("reads tables, functions and actions from the module", () => {
    const module = SQL_MODULES["tasks"];

    if (module === undefined) {
      throw new Error("no tasks module");
    }

    const names = moduleNameSet(module);
    expect(Object.keys(names.tables)).toEqual([
      "items",
      "checklist",
      "assignees",
      "projects",
      "iterations",
    ]);
    expect(names.functions).toContain("list_work_items");
    expect(names.actions).toEqual([
      "read",
      "write",
      "manage",
      "create",
      "delete",
    ]);
  });
});

/** What is wrong with `module`'s entities, as messages. */
function entityProblems(module: BlockSql): string[] {
  const names = module.names;
  const actions = moduleNameSet(module).actions;
  const entities = Object.entries(names?.entities ?? {});
  const problems: string[] = [];

  if (entities.filter(([, each]) => each.primary === true).length > 1) {
    problems.push("more than one primary entity");
  }

  for (const [key, entity] of entities) {
    if (!/^[a-z][a-z0-9_]*$/.test(entity.singular)) {
      problems.push(`${key}: singular ${entity.singular}`);
    }

    if (entity.table === undefined) {
      if (entity.global !== true) {
        problems.push(`${key}: no table`);
      }

      continue;
    }

    const table = names?.tables[entity.table];

    if (table === undefined) {
      problems.push(`${key}: no table ${entity.table}`);
      continue;
    }

    const subject = entity.subject;

    if (subject === undefined) {
      continue;
    }

    const used = [
      subject.title,
      subject.deletedAt,
      subject.rank?.column,
      subject.rank?.group,
      subject.search?.title,
      ...(subject.search?.body ?? []),
    ].filter((column) => column !== undefined);

    for (const column of used) {
      if (!Object.hasOwn(table.columns, column)) {
        problems.push(`${key}: no column ${column}`);
      }
    }

    for (const action of [
      subject.permissions.read,
      subject.permissions.write,
    ]) {
      if (!actions.includes(action)) {
        problems.push(`${key}: no action ${action}`);
      }
    }
  }

  return problems;
}

describe("module entities", () => {
  const modules = Object.values(SQL_MODULES).filter(
    (module) => module.names?.entities !== undefined,
  );

  it.each(modules.map((module) => [module.name, module] as const))(
    "%s names real tables, columns and actions",
    (_, module) => {
      expect(entityProblems(module)).toEqual([]);
    },
  );
});
