import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../src/config/blocks.ts";
import type { BlockSqlContext } from "../../src/sql/context.ts";
import type { DeclaredForeignKey } from "../../src/sql/foreign-keys.ts";

import {
  inferredColumn,
  inferredLink,
} from "../../src/sql/inferred-bindings.ts";
import { ownTablesOf } from "../fixtures/own-tables.ts";
import { renderBlocks } from "./app-columns.ts";

const key = (
  table: string,
  column: string,
  references: string,
): DeclaredForeignKey => ({
  table,
  columns: [column],
  references,
  referencedColumns: ["id"],
});

const withKeys = (
  foreignKeys: readonly DeclaredForeignKey[],
): BlockSqlContext =>
  // SAFETY: the inference reads only `foreignKeys`.
  ({ foreignKeys }) as unknown as BlockSqlContext;

const tasks = { table: "public.tasks", extra: {} };

const tagsSql = (foreignKeys: readonly DeclaredForeignKey[]): string => {
  const modules: AnyBlocksConfig = {
    tags: {
      tables: { tags: "public.labels", taggings: null },
      columns: { tags: { rank: null } },
      on: { task: { table: "public.tasks" } },
    },
  };

  return renderBlocks(["tags"], {
    modules,
    ownTables: ownTablesOf(modules),
    declaredColumns: {},
    foreignKeys,
  })
    .map((file) => file.contents)
    .join("\n");
};

describe("column inferred from a foreign key", () => {
  it("finds the one key into the record type's table", () => {
    const ctx = withKeys([key("public.entries", "task_id", "public.tasks")]);

    expect(inferredColumn(ctx, '"public"."entries"', tasks, "w")).toBe(
      "task_id",
    );
  });

  it("finds nothing without a key", () => {
    expect(
      inferredColumn(withKeys([]), "public.entries", tasks, "w"),
    ).toBeUndefined();
  });

  it("lists the candidates when there are several", () => {
    const ctx = withKeys([
      key("public.entries", "task_id", "public.tasks"),
      key("public.entries", "parent_id", "public.tasks"),
    ]);

    expect(() => inferredColumn(ctx, "public.entries", tasks, "w")).toThrow(
      /task_id, parent_id/,
    );
  });
});

describe("tags link inferred from foreign keys", () => {
  const links = [
    key("public.task_labels", "task_id", "public.tasks"),
    key("public.task_labels", "label_id", "public.labels"),
  ];

  it("finds the table with a key into each side", () => {
    expect(
      inferredLink(withKeys(links), tasks, '"public"."labels"', "w"),
    ).toEqual({
      table: "public.task_labels",
      subject: "task_id",
      tag: "label_id",
    });
  });

  it("renders the link table without a links entry", () => {
    const sql = tagsSql(links);

    expect(sql).toContain('"public"."task_labels"');
    expect(sql).toContain('"task_id"');
  });

  it("keeps the polymorphic table when no table links the two", () => {
    expect(tagsSql([])).not.toContain("task_labels");
  });

  it("lists the tables when two link the same pair", () => {
    expect(() =>
      inferredLink(
        withKeys([
          ...links,
          key("public.task_topics", "task_id", "public.tasks"),
          key("public.task_topics", "label_id", "public.labels"),
        ]),
        tasks,
        "public.labels",
        "w",
      ),
    ).toThrow(/task_labels.*task_topics|task_topics.*task_labels/);
  });
});

describe("id type inferred from the schema files", () => {
  it("casts a stored text id to the declared type, only for an id with its shape", () => {
    const modules: AnyBlocksConfig = {
      tags: {
        tables: { tags: "public.labels", taggings: null },
        columns: { tags: { rank: null } },
        on: { task: { table: "public.tasks" } },
      },
    };

    const sql = renderBlocks(["tags"], {
      modules,
      ownTables: ownTablesOf(modules),
      idTypes: { "public.tasks": { id: "bigint" } },
    })
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain("^-?[0-9]{1,18}$");
  });
});
