import type { Preset } from "../preset/index.ts";
import type { Design } from "./design.ts";
import type { Issue } from "./issue.ts";
import type { SchemaData } from "./schema.ts";

import { jsonPointer } from "../preset/design.ts";
import { appNameLengthError } from "../preset/index.ts";
import { lockedWithoutDefault } from "./column-keys.ts";
import { AUTH_USERS, scopeColumnOf } from "./design-scope.ts";
import { subjectColumns } from "./design-subject.ts";
import { defaultError, identifierError, isAppTable } from "./design.ts";

/**
 * What would stop `upgrade` from writing the design: a table name a block
 * already uses, a reference to a table the preset no longer installs, a
 * set-null delete on a required column, a composite key on a column the table
 * doesn't have, and extra columns for a block that is gone or no longer takes
 * them.
 */
export function designIssues(
  design: Design,
  data: SchemaData,
  preset: Pick<Preset, "scope" | "tenantName" | "idType">,
): readonly Issue[] {
  const issues: Issue[] = [];

  const names = new Set(
    data.tables
      .filter((table) => !isAppTable(table))
      .map((table) => table.name),
  );

  const logical = new Set(
    Object.values(data.blockTables).map(
      (each) => `${each.block}.${each.table}`,
    ),
  );

  const modules = new Set(
    data.tables
      .filter((table) => data.extraColumns.includes(table.id))
      .map((table) => table.module),
  );

  const subjectTypes = new Map<string, string>();

  for (const [name, table] of Object.entries(design.appTables ?? {})) {
    const type = table.subject?.type;

    if (type !== undefined && !subjectTypes.has(type)) {
      subjectTypes.set(type, name);
    }
  }

  for (const [name, table] of Object.entries(design.appTables ?? {})) {
    const invalid = identifierError(name);

    if (invalid !== undefined) {
      issues.push({
        severity: "error",
        source: "rules",
        code: "invalid_name",
        path: jsonPointer("appTables", name),
        table: name,
        message: `The name ${name} is invalid. ${invalid}`,
      });
    }

    if (names.has(name)) {
      issues.push({
        severity: "error",
        source: "rules",
        code: "table_name_taken",
        path: jsonPointer("appTables", name),
        table: name,
        message: `A block already creates a ${name} table. Rename this one.`,
      });
    }

    const long = appNameLengthError(name, table);

    if (long !== undefined) {
      issues.push({
        severity: "error",
        source: "rules",
        code: "name_too_long",
        path: jsonPointer("appTables", name),
        table: name,
        message: `${long}.`,
      });
    }

    const type = table.subject?.type;

    if (type !== undefined && subjectTypes.get(type) !== name) {
      issues.push({
        severity: "error",
        source: "rules",
        code: "subject_type_taken",
        path: jsonPointer("appTables", name, "subject", "type"),
        table: name,
        message: `${subjectTypes.get(type)} already has the subject type ${type}. Choose another.`,
      });
    }

    for (const [column, config] of Object.entries(table.columns ?? {})) {
      const fallback =
        config.default === undefined
          ? undefined
          : defaultError(config, config.default);

      if (fallback !== undefined) {
        issues.push({
          severity: "error",
          source: "rules",
          code: "invalid_default",
          path: jsonPointer("appTables", name, "columns", column, "default"),
          table: name,
          message: `${name}.${column}: ${fallback}`,
        });
      }

      if (lockedWithoutDefault(config)) {
        issues.push({
          severity: "error",
          source: "rules",
          code: "default_required",
          path: jsonPointer("appTables", name, "columns", column),
          table: name,
          message: `${name}.${column} is required, and signed-in users can't write it, so give it a default.`,
        });
      }
    }

    for (const column of subjectColumns(table.subject)) {
      if (Object.hasOwn(table.columns ?? {}, column.name)) {
        issues.push({
          severity: "error",
          source: "rules",
          code: "column_clash",
          path: jsonPointer("appTables", name, "columns", column.name),
          table: name,
          message: `${name}.${column.name} clashes with the column its record features add. Rename it.`,
        });
      }
    }

    const known = new Set([
      "id",
      ...Object.keys(table.columns ?? {}),
      ...(table.timestamps === false ? [] : ["created_at", "updated_at"]),
    ]);

    const scope = scopeColumnOf(table, preset);

    if (scope !== null) {
      known.add(scope.name);
    }

    for (const [key, field, sets] of [
      ["unique key", "unique", table.unique],
      ["index", "indexes", table.indexes],
    ] as const) {
      for (const [index, columns] of (sets ?? []).entries()) {
        const gone = columns.filter((column) => !known.has(column));

        if (gone.length > 0) {
          issues.push({
            severity: "error",
            source: "rules",
            code: "unknown_column",
            path: jsonPointer("appTables", name, field, index),
            table: name,
            message: `The ${key} on ${columns.join(", ")} names ${gone.join(", ")}, which ${name} doesn't have.`,
          });
        }
      }
    }

    for (const [column, config] of Object.entries(table.columns ?? {})) {
      const reference = config.references;

      if (reference === undefined) {
        continue;
      }

      const missing =
        reference.block === undefined
          ? reference.table !== AUTH_USERS &&
            design.appTables?.[reference.table] === undefined
          : !logical.has(`${reference.block}.${reference.table}`);

      if (missing) {
        issues.push({
          severity: "error",
          source: "rules",
          code: "missing_reference",
          path: jsonPointer("appTables", name, "columns", column, "references"),
          table: name,
          message: `${name}.${column} references ${reference.block === undefined ? reference.table : `${reference.block}.${reference.table}`}, which the preset does not install.`,
        });
      }

      if (reference.onDelete === "set null" && config.nullable === false) {
        issues.push({
          severity: "error",
          source: "rules",
          code: "set_null_required",
          path: jsonPointer(
            "appTables",
            name,
            "columns",
            column,
            "references",
            "onDelete",
          ),
          table: name,
          message: `${name}.${column} is required, so deleting the row it references can't set it to null.`,
        });
      }
    }
  }

  for (const block of Object.keys(design.extraColumns ?? {})) {
    if (!modules.has(block)) {
      issues.push({
        severity: "error",
        source: "rules",
        code: "block_not_installed",
        path: jsonPointer("extraColumns", block),
        table: block,
        message: `The extra columns for ${block} have no table: the block is not installed or takes no extra columns.`,
      });
    }
  }

  return issues;
}
