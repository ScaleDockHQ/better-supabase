import type { Design, SchemaData, SchemaTable } from "better-supabase/create";

function identifier(table: SchemaTable): string {
  return table.schema === "public"
    ? table.name
    : `${table.schema}_${table.name}`;
}

function mermaidType(type: string): string {
  return (
    type
      .toLowerCase()
      .replaceAll(/[^a-z0-9_]+/gu, "_")
      .replaceAll(/_+$/gu, "") || "unknown"
  );
}

/** The tables as a Mermaid `erDiagram`, foreign keys as one-to-many relations. */
export function toMermaid(data: Pick<SchemaData, "tables">): string {
  const byId = new Map(data.tables.map((table) => [table.id, table]));
  const lines = ["erDiagram"];

  for (const table of data.tables) {
    lines.push(`  ${identifier(table)} {`);

    for (const column of table.columns) {
      const keys = [
        ...(table.primaryKey.includes(column.name) ? ["PK"] : []),
        ...(table.foreignKeys.some((key) => key.columns.includes(column.name))
          ? ["FK"]
          : []),
      ];

      lines.push(
        `    ${mermaidType(column.type)} ${column.name}${keys.length === 0 ? "" : ` ${keys.join(", ")}`}`,
      );
    }

    lines.push("  }");
  }

  for (const table of data.tables) {
    for (const key of table.foreignKeys) {
      const target = byId.get(`${key.target.schema}.${key.target.table}`);

      const to =
        target === undefined
          ? `${key.target.schema}_${key.target.table}`
          : identifier(target);

      lines.push(
        `  ${to} ||--o{ ${identifier(table)} : "${key.columns.join(", ")}"`,
      );
    }
  }

  return `${lines.join("\n")}\n`;
}

function quoted(name: string): string {
  return /^[a-z_][a-z0-9_]*$/u.test(name)
    ? name
    : `"${name.replaceAll('"', '\\"')}"`;
}

/** The tables in DBML, for dbdiagram.io and other DBML tools. */
export function toDbml(data: Pick<SchemaData, "tables">): string {
  const blocks = data.tables.map((table) => {
    const columns = table.columns.map((column) => {
      const settings = [
        ...(table.primaryKey.length === 1 && table.primaryKey[0] === column.name
          ? ["pk"]
          : []),
        ...(column.nullable ? [] : ["not null"]),
        ...(column.unique ? ["unique"] : []),
        ...(column.default === null
          ? []
          : [`default: \`${column.default.replaceAll("`", "'")}\``]),
      ];

      return `  ${quoted(column.name)} ${quoted(column.type)}${settings.length === 0 ? "" : ` [${settings.join(", ")}]`}`;
    });

    const composite =
      table.primaryKey.length > 1
        ? [
            "",
            "  indexes {",
            `    (${table.primaryKey.map(quoted).join(", ")}) [pk]`,
            "  }",
          ]
        : [];

    return [
      `Table ${quoted(table.schema)}.${quoted(table.name)} {`,
      ...columns,
      ...composite,
      "}",
    ].join("\n");
  });

  const refs = data.tables.flatMap((table) =>
    table.foreignKeys.map((key) => {
      const from = `${quoted(table.schema)}.${quoted(table.name)}.(${key.columns.map(quoted).join(", ")})`;

      const toColumns =
        key.target.columns.length === 0 ? ["id"] : key.target.columns;

      const to = `${quoted(key.target.schema)}.${quoted(key.target.table)}.(${toColumns.map(quoted).join(", ")})`;

      return `Ref: ${from} > ${to}`;
    }),
  );

  return `${[...blocks, ...(refs.length === 0 ? [] : [refs.join("\n")])].join("\n\n")}\n`;
}

/** The preset code, the design and the tables as JSON. */
export function toJson(
  code: string,
  design: Design,
  data: Pick<SchemaData, "tables">,
): string {
  return `${JSON.stringify({ preset: code, design, tables: data.tables }, null, 2)}\n`;
}
