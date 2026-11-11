import type { BlockSqlFile, BlockSqlLayout } from "../module-types.ts";

import { CONFIG_DEFAULTS } from "../../config/defaults.ts";
import { moduleHeader } from "./assemble.ts";

/**
 * The `module` of the file that holds the statements no schema filter covers.
 * Like the prelude it is not a block.
 */
export const UNSCOPED_MODULE = "unscoped";

const VERSION = 1;

const DESCRIPTION =
  "Event triggers and triggers on auth tables. They belong to no schema of the app, so a diff limited to some schemas never plans them; keeping them here puts them in one place to read.";

/**
 * An event trigger, or a trigger on a table of the `auth` schema, with the
 * comment lines just above it.
 */
const UNSCOPED =
  /(?:^--[^\n]*\n)*(?:^drop event trigger [^;]*;[ \t]*\n)*^create (?:event trigger [^;]*|(?:or replace )?(?:constraint )?trigger [^;]*?\bon\s+"?auth"?\.[^;]*);[ \t]*\n?/gim;

/** The `drop event trigger` lines a declarative file must not carry. */
const DROP_EVENT_TRIGGER = /^drop event trigger [^;]*;[ \t]*\n/gim;

/** `contents` without its unscoped statements, and those statements. */
export function takeUnscoped(contents: string): {
  readonly rest: string;
  readonly statements: readonly string[];
} {
  const statements = [...contents.matchAll(UNSCOPED)].map((match) =>
    match[0].trim(),
  );

  return {
    rest:
      statements.length === 0 ? contents : contents.replaceAll(UNSCOPED, ""),
    statements,
  };
}

/**
 * The files with their unscoped statements moved into one file that sorts after
 * every module. The migrations workflow applies statements in file order, so it
 * keeps them where the module wrote them.
 */
export function withUnscopedFile(
  files: readonly BlockSqlFile[],
  layout: BlockSqlLayout,
): readonly BlockSqlFile[] {
  if (layout.rerunnable === true) {
    return files;
  }

  const found: string[] = [];

  const rest = files.map((file) => {
    if (file.kind !== "schema") {
      return file;
    }

    const taken = takeUnscoped(file.contents);
    found.push(
      ...taken.statements.map((statement) =>
        statement.replaceAll(DROP_EVENT_TRIGGER, "").trim(),
      ),
    );

    return taken.statements.length === 0
      ? file
      : { ...file, contents: taken.rest };
  });

  if (found.length === 0) {
    return files;
  }

  const dir = (layout.dir ?? CONFIG_DEFAULTS.sql.dir).replace(/\/$/, "");
  const prefix = layout.prefix ?? CONFIG_DEFAULTS.sql.prefix;

  const header = moduleHeader({
    instance: UNSCOPED_MODULE,
    version: VERSION,
    mode: "managed",
    description: DESCRIPTION,
    block: undefined,
    entities: [],
  });

  return [
    ...rest,
    {
      module: UNSCOPED_MODULE,
      kind: "schema",
      path: `${dir}/${prefix}_999_${UNSCOPED_MODULE}.sql`,
      contents: `${header}\n\n${found.join("\n\n")}\n`,
    },
  ];
}
