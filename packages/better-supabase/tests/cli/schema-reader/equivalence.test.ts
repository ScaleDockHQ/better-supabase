import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { describe, expect, it } from "vitest";

import type { FileFacts } from "../../../src/cli/schema-reader/index.ts";

import { readFileFacts } from "../../../src/cli/schema-reader/index.ts";
import {
  addedColumnTypes,
  declaredColumnTypes,
  declaredEnums,
  declaredNotNullColumns,
  declaredTableColumns,
  declaredTables,
  rlsTables,
} from "../../../src/sql/schema-scan.ts";

const REPO = join(import.meta.dirname, "../../../../..");

/** Generated modules, the repo's own schema and a validation project. */
const CORPUS = [
  "packages/better-supabase/tests/sql/__golden__",
  "supabase/schemas",
  "tests/validation-centrakit/supabase/schemas",
];

const SCHEMAS = [
  "public",
  "better_supabase",
  "auth",
  "storage",
  "api",
  "_better_supabase",
  "rbac",
  "extensions",
  "workflow",
];

function walk(directory: string, found: string[] = []): string[] {
  for (const entry of readdirSync(directory)) {
    const path = join(directory, entry);

    if (statSync(path).isDirectory()) {
      walk(path, found);
    } else if (path.endsWith(".sql")) {
      found.push(path);
    }
  }

  return found;
}

const files = CORPUS.flatMap((directory) => walk(join(REPO, directory))).map(
  (path) => ({
    path,
    name: relative(REPO, path),
    text: readFileSync(path, "utf-8"),
  }),
);

const inSchemas = (name: string): boolean =>
  SCHEMAS.includes(name.slice(0, name.indexOf(".")));

function created(facts: FileFacts): string[] {
  const events = [
    ...facts.tables.map((each) => ({
      at: each.index,
      create: true,
      name: each.name,
    })),
    ...facts.drops
      .filter((each) => each.kind === "table")
      .map((each) => ({ at: each.index, create: false, name: each.name })),
  ].toSorted((a, b) => a.at - b.at);

  const found = new Set<string>();

  for (const event of events) {
    if (!event.create) {
      found.delete(event.name);
    } else if (inSchemas(event.name)) {
      found.add(event.name);
    }
  }

  return [...found];
}

const byName = (a: string, b: string): number => a.localeCompare(b);

const nested = (
  map: ReadonlyMap<string, ReadonlyMap<string, string> | ReadonlySet<string>>,
): string =>
  JSON.stringify(
    [...map]
      .map(
        ([key, value]) =>
          [
            key,
            [...value].map((item) => JSON.stringify(item)).toSorted(byName),
          ] as const,
      )
      .toSorted(([a], [b]) => a.localeCompare(b)),
  );

describe("the schema reader matches the text scanners", () => {
  it("has a corpus", () => {
    expect(files.length).toBeGreaterThan(300);
  });

  it.each(files)("$name", async (file) => {
    const facts = await readFileFacts(file.text, { path: file.name });
    const one = [{ text: file.text }];

    expect(created(facts).toSorted(byName)).toEqual(
      declaredTables(one, SCHEMAS).toSorted(byName),
    );

    const types = new Map<string, Map<string, string>>();
    const columns = new Map<string, Set<string>>();

    for (const table of facts.tables.filter((each) => inSchemas(each.name))) {
      const known = types.get(table.name) ?? new Map<string, string>();

      for (const column of table.columns) {
        known.set(column.name, column.type);
      }

      types.set(table.name, known);
      columns.set(table.name, new Set(known.keys()));
    }

    expect(nested(types)).toBe(nested(declaredColumnTypes(one, SCHEMAS)));
    expect(nested(columns)).toBe(nested(declaredTableColumns(one, SCHEMAS)));

    const added = new Map<string, Map<string, string>>();

    for (const alter of facts.alters.filter((each) => inSchemas(each.table))) {
      if (alter.addedColumns.length > 0) {
        const known = added.get(alter.table) ?? new Map<string, string>();

        for (const column of alter.addedColumns) {
          known.set(column.name, column.type);
        }

        added.set(alter.table, known);
      }
    }

    expect(nested(added)).toBe(nested(addedColumnTypes(one, SCHEMAS)));

    const notNull = new Map<string, Set<string>>();

    const mark = (table: string, column: string): void => {
      if (inSchemas(table)) {
        notNull.set(table, (notNull.get(table) ?? new Set()).add(column));
      }
    };

    for (const table of facts.tables) {
      for (const column of table.columns.filter((each) => each.notNull)) {
        mark(table.name, column.name);
      }
    }

    for (const alter of facts.alters) {
      for (const column of alter.setNotNull) {
        mark(alter.table, column);
      }
    }

    const scanned = new Map(
      [...declaredNotNullColumns(one, SCHEMAS)].map(
        ([table, names]) => [table, new Set(names)] as const,
      ),
    );

    // The scanner reads `not null` inside `check (role is null or ...)` as a
    // constraint of `role`; the reader reads the constraint list.
    const overread =
      scanned.get("better_supabase.invite_codes")?.has("role") === true;

    scanned.get("better_supabase.invite_codes")?.delete("role");
    expect(
      overread &&
        notNull.get("better_supabase.invite_codes")?.has("role") === true,
    ).toBe(false);

    expect(nested(notNull)).toBe(nested(scanned));
    expect(
      [...new Set(facts.enums.map((each) => each.name))].toSorted(byName),
    ).toEqual([...declaredEnums(one)].toSorted(byName));

    const rls = new Set<string>();

    for (const alter of facts.alters.filter((each) => each.enablesRls)) {
      if (inSchemas(alter.table)) {
        rls.add(alter.table);
      }
    }

    // The scanner also drops a table on `disable` or `drop`; this corpus has neither.
    expect([...rls].toSorted(byName)).toEqual(
      rlsTables(one, SCHEMAS).toSorted(byName),
    );
  });
});
