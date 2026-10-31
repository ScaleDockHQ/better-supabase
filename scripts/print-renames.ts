// Prints the rename tables of the 0.46 to 0.47 guide as Markdown, from
// `src/core/renames.ts`: `node scripts/print-renames.ts`. The guide pastes
// these tables, and `scripts/print-renames.test.ts` fails when they differ.
import {
  ENTITY_KEY_RENAMES,
  SUBJECT_TYPE_RENAMES,
  TABLE_RENAMES,
} from "../packages/better-supabase/src/core/renames.ts";

const code = (names: readonly string[]): string =>
  names.map((name) => `\`${name}\``).join(", ");

function table(
  header: readonly string[],
  rows: readonly (readonly string[])[],
): string {
  const width = header.map((cell, index) =>
    Math.max(cell.length, ...rows.map((row) => row[index]?.length ?? 0)),
  );

  const line = (cells: readonly string[]): string =>
    `| ${cells.map((cell, index) => cell.padEnd(width[index] ?? 0)).join(" | ")} |`;

  return [
    line(header),
    `| ${width.map((each) => "-".repeat(each)).join(" | ")} |`,
    ...rows.map(line),
  ].join("\n");
}

/** `blocks.<name>.entities` keys, one row per renamed key. */
export function entityKeyTable(): string {
  return table(
    ["Block", "0.46 key", "0.47 key"],
    Object.entries(ENTITY_KEY_RENAMES).flatMap(([block, keys]) =>
      Object.entries(keys).map(([from, to]) => [
        code([block]),
        code([from]),
        code([to]),
      ]),
    ),
  );
}

/** The subject types the entity renames changed. */
export function subjectTypeTable(): string {
  return table(
    ["0.46 type", "0.47 type"],
    Object.entries(SUBJECT_TYPE_RENAMES).map(([from, to]) => [
      code([from]),
      code([to]),
    ]),
  );
}

/** Module tables, one row per block. */
export function tableRenameTable(): string {
  return table(
    ["Block", "0.46 tables", "0.47 tables"],
    Object.entries(TABLE_RENAMES).map(([block, tables]) => {
      const moves = Object.values(tables);

      return [
        code([block]),
        code(moves.map((move) => move.from)),
        code(moves.map((move) => move.to)),
      ];
    }),
  );
}

export const printRenames = (): string =>
  [
    "## Entity keys",
    entityKeyTable(),
    "## Subject types",
    subjectTypeTable(),
    "## Table names",
    tableRenameTable(),
  ].join("\n\n");

if (import.meta.main) {
  process.stdout.write(`${printRenames()}\n`);
}
