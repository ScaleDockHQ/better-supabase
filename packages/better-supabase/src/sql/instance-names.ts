import type { ResolvedInstance } from "../config/instances.ts";
import type { BlockSqlLayout } from "./module-types.ts";

import { isRenamedInstance } from "../config/instances.ts";

/**
 * Whether `block` renders under its own name: an instance is named after it, or
 * no instance installs it and it came in as a dependency.
 */
export function rendersOwnInstance(
  block: string,
  layout: BlockSqlLayout,
): boolean {
  const instances = Object.values(layout.instances ?? {});

  return (
    !instances.some((instance) => instance.block === block) ||
    instances.some(
      (instance) => instance.block === block && !isRenamedInstance(instance),
    )
  );
}

/** The instances that install `block` under another name. */
export function renamedInstances(
  block: string,
  layout: BlockSqlLayout,
): readonly ResolvedInstance[] {
  return Object.values(layout.instances ?? {}).filter(
    (instance) => instance.block === block && isRenamedInstance(instance),
  );
}

const IDENT = String.raw`(?:"[^"]+"|[A-Za-z_][\w$]*)`;

const CREATED = new RegExp(
  String.raw`\bcreate\s+(?:or\s+replace\s+)?(?:unique\s+)?(?:function|procedure|index|type|sequence|view|materialized\s+view|table|trigger|event\s+trigger|aggregate|domain)\s+(?:concurrently\s+)?(?:if\s+not\s+exists\s+)?(?:${IDENT}\.)?(${IDENT})`,
  "gi",
);

const CONSTRAINT = new RegExp(String.raw`\bconstraint\s+(${IDENT})`, "gi");

const unquote = (name: string): string =>
  name.startsWith('"') ? name.slice(1, -1) : name;

/**
 * The functions, indexes, types, sequences, views, tables, triggers and
 * constraints `sql` creates.
 */
export function createdNames(sql: string): ReadonlySet<string> {
  return new Set(
    [...sql.matchAll(CREATED), ...sql.matchAll(CONSTRAINT)].map((match) =>
      unquote(match[1] ?? ""),
    ),
  );
}

/**
 * The names an instance's SQL creates that the module's own instance creates
 * too, each to the name with the instance's prefix. Its context already
 * prefixes the tables and functions it names; this catches the indexes,
 * constraints and types a module writes by hand.
 */
export function instanceRenames(
  sql: string,
  moduleSql: string,
  prefix: string,
): ReadonlyMap<string, string> {
  const own = createdNames(moduleSql);

  return new Map(
    [...createdNames(sql)]
      .filter((name) => own.has(name) && !name.startsWith(`${prefix}_`))
      .map((name) => [name, `${prefix}_${name}`]),
  );
}

const TOKEN = /'(?:[^']|'')*'|--[^\n]*|"[^"]+"|[A-Za-z_][\w$]*/g;

/**
 * `sql` with every identifier in `renames` renamed. Inside a string literal
 * only a qualified name (`schema.name`) or a quoted one is renamed, so a job
 * body or a hook target follows while message text stays as written. Comments
 * stay as written.
 */
export function renameIdentifiers(
  sql: string,
  renames: ReadonlyMap<string, string>,
): string {
  if (renames.size === 0) {
    return sql;
  }

  return sql.replaceAll(TOKEN, (token) => {
    if (token.startsWith("--")) {
      return token;
    }

    if (token.startsWith("'")) {
      return token.replaceAll(/(?<=\.)[A-Za-z_][\w$]*|"[^"]+"/g, (name) => {
        const quoted = name.startsWith('"');
        const renamed = renames.get(quoted ? name.slice(1, -1) : name);

        return renamed === undefined ? name : quoted ? `"${renamed}"` : renamed;
      });
    }

    if (token.startsWith('"')) {
      const renamed = renames.get(token.slice(1, -1));

      return renamed === undefined ? token : `"${renamed}"`;
    }

    return renames.get(token) ?? token;
  });
}
