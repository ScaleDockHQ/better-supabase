import {
  lineOf,
  type Location,
  type SqlObject,
  type TextFile,
} from "../doctor/rules.ts";

const escape = (name: string): string =>
  name.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&");

/** Where a table, function or policy is declared: declarative schemas first, then the newest migration. */
export function locate(
  files: readonly TextFile[],
  object: SqlObject,
): Location | undefined {
  const name = `"?${escape(object.name)}"?`;
  const qualifiedName = `(?:"?${escape(object.schema)}"?\\.)?${name}`;
  if (object.kind === "policy" && object.table !== undefined) {
    // `create policy <name>` and `on <table>` are often on separate lines.
    const onTable = new RegExp(
      `create\\s+policy\\s+${name}\\s+on\\s+(?:only\\s+)?(?:"?${escape(object.schema)}"?\\.)?"?${escape(object.table)}"?(?:\\s|;|$)`,
      "i",
    );
    for (const file of files) {
      const match = onTable.exec(file.text);
      if (match) {
        return {
          file: file.path,
          line: file.text.slice(0, match.index).split("\n").length,
        };
      }
    }
    return undefined;
  }
  const pattern =
    object.kind === "table"
      ? new RegExp(
          `create\\s+(?:unlogged\\s+)?table\\s+(?:if\\s+not\\s+exists\\s+)?${qualifiedName}(?:\\s|\\(|$)`,
          "i",
        )
      : object.kind === "function"
        ? new RegExp(
            `create\\s+(?:or\\s+replace\\s+)?function\\s+${qualifiedName}\\s*\\(`,
            "i",
          )
        : new RegExp(`create\\s+policy\\s+${name}`, "i");
  for (const file of files) {
    const line = lineOf(file.text, pattern);
    if (line) {
      return { file: file.path, line };
    }
  }
  return undefined;
}
