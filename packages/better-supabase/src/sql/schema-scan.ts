import { withoutComments } from "./audit-registrations.ts";

/** Privileges one role gets on a table, from the policies that name it. */
export interface PolicyGrant {
  /** `schema.table`, unquoted; an unqualified name is in `public`. */
  readonly table: string;
  readonly role: "anon" | "authenticated";
  readonly privileges: readonly ("select" | "insert" | "update" | "delete")[];
}

const NAME = String.raw`(?:"(?:[^"]|"")+"|[A-Za-z_][\w$]*)`;
const POLICY = new RegExp(
  String.raw`\bcreate\s+policy\s+(${NAME})\s+on\s+(${NAME}(?:\s*\.\s*${NAME})?)((?:(?!\bcreate\s+policy\b)[\s\S])*?)(?:\busing\b|\bwith\s+check\b|;)`,
  "gi",
);
const DROP_POLICY = new RegExp(
  String.raw`\bdrop\s+policy\s+(?:if\s+exists\s+)?(${NAME})\s+on\s+(${NAME}(?:\s*\.\s*${NAME})?)`,
  "gi",
);
const TABLE_NAME = String.raw`${NAME}(?:\s*\.\s*${NAME})?`;
const DROP_TABLE = new RegExp(
  String.raw`\bdrop\s+table\s+(?:if\s+exists\s+)?(${TABLE_NAME}(?:\s*,\s*${TABLE_NAME})*)`,
  "gi",
);

function droppedTables(list: string): string[] {
  return (list.match(new RegExp(TABLE_NAME, "g")) ?? []).map(qualified);
}

type Statement = { readonly index: number; readonly apply: () => void };

function inOrder(statements: Statement[][]): void {
  for (const statement of statements.flat().sort((a, b) => a.index - b.index))
    statement.apply();
}
const COMMANDS = ["select", "insert", "update", "delete"] as const;

const unquote = (name: string): string =>
  name.startsWith('"')
    ? name.slice(1, -1).replaceAll('""', '"')
    : name.toLowerCase();

function qualified(target: string): string {
  const parts = (target.match(new RegExp(NAME, "g")) ?? []).map(unquote);
  return parts.length === 1 ? `public.${parts[0]!}` : parts.join(".");
}

const TABLE = new RegExp(
  String.raw`\bcreate\s+(?:unlogged\s+)?table\s+(?:if\s+not\s+exists\s+)?(${NAME}(?:\s*\.\s*${NAME})?)\s*\(`,
  "gi",
);

/** `*` in a `schema.table` glob matches any run of characters. */
export function tableGlobs(globs: readonly string[]): RegExp[] {
  return globs.map(
    (glob) =>
      new RegExp(
        `^${glob
          .split("*")
          .map((part) => part.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&"))
          .join(".*")}$`,
        "i",
      ),
  );
}

/**
 * The tables `files` create (`create table`), as `schema.table`, in the
 * order they first appear. Only tables in `schemas` are kept.
 */
export function declaredTables(
  files: readonly { readonly text: string }[],
  schemas: readonly string[],
): string[] {
  const found = new Set<string>();
  for (const file of files) {
    const text = withoutComments(file.text);
    inOrder([
      [...text.matchAll(TABLE)].map((match) => ({
        index: match.index,
        apply: () => {
          const table = qualified(match[1]!);
          if (schemas.includes(table.slice(0, table.indexOf("."))))
            found.add(table);
        },
      })),
      [...text.matchAll(DROP_TABLE)].map((match) => ({
        index: match.index,
        apply: () => {
          for (const table of droppedTables(match[1]!)) found.delete(table);
        },
      })),
    ]);
  }
  return [...found];
}

/**
 * The privileges the permissive policies in `files` imply, per table and
 * role: `for all` gives the four commands, `to public` (or no `to`) counts
 * for `authenticated` only, so `anon` needs a policy that names it.
 * Restrictive policies grant nothing. Only tables in `schemas` are kept.
 */
export function policyGrants(
  files: readonly { readonly text: string }[],
  schemas: readonly string[],
): PolicyGrant[] {
  type Named = Map<
    string,
    { roles: PolicyGrant["role"][]; privileges: readonly string[] }
  >;
  const policies = new Map<string, Named>();
  for (const file of files) {
    const text = withoutComments(file.text);
    inOrder([
      [...text.matchAll(POLICY)].map((match) => ({
        index: match.index,
        apply: () => {
          const table = qualified(match[2]!);
          if (!schemas.includes(table.slice(0, table.indexOf(".")))) return;
          const clauses = match[3]!;
          if (/\bas\s+restrictive\b/i.test(clauses)) return;
          const command = /\bfor\s+(all|select|insert|update|delete)\b/i
            .exec(clauses)?.[1]
            ?.toLowerCase();
          const privileges =
            command === undefined || command === "all" ? COMMANDS : [command];
          const to = /\bto\s+([\s\S]+)$/i.exec(clauses)?.[1];
          const roles = (to ?? "public")
            .split(",")
            .map((role) => unquote(role.trim()))
            .map((role) => (role === "public" ? "authenticated" : role))
            .filter(
              (role): role is PolicyGrant["role"] =>
                role === "anon" || role === "authenticated",
            );
          const named: Named = policies.get(table) ?? new Map();
          named.set(unquote(match[1]!), { roles, privileges });
          policies.set(table, named);
        },
      })),
      [...text.matchAll(DROP_POLICY)].map((match) => ({
        index: match.index,
        apply: () => {
          policies.get(qualified(match[2]!))?.delete(unquote(match[1]!));
        },
      })),
      [...text.matchAll(DROP_TABLE)].map((match) => ({
        index: match.index,
        apply: () => {
          for (const table of droppedTables(match[1]!)) policies.delete(table);
        },
      })),
    ]);
  }
  const found = new Map<
    string,
    { table: string; role: PolicyGrant["role"]; privileges: Set<string> }
  >();
  for (const [table, named] of policies) {
    for (const { roles, privileges } of named.values()) {
      for (const role of roles) {
        const key = `${table}\u0000${role}`;
        const entry = found.get(key) ?? {
          table,
          role,
          privileges: new Set<string>(),
        };
        for (const privilege of privileges) entry.privileges.add(privilege);
        found.set(key, entry);
      }
    }
  }
  return [...found.values()]
    .map((entry): PolicyGrant => ({
      table: entry.table,
      role: entry.role,
      privileges: COMMANDS.filter((command) => entry.privileges.has(command)),
    }))
    .sort((a, b) =>
      a.table === b.table
        ? a.role < b.role
          ? -1
          : 1
        : a.table < b.table
          ? -1
          : 1,
    );
}

const EXTENSION = new RegExp(
  String.raw`\bcreate\s+extension\s+(?:if\s+not\s+exists\s+)?(${NAME})(?:\s+with)?\s+schema\s+(${NAME})`,
  "gi",
);

const MODULE_FILE = /^-- @bs-module /m;

export function extensionSchema(
  sources: readonly { readonly text: string }[],
  extension: string,
): string | undefined {
  for (const source of sources) {
    if (MODULE_FILE.test(source.text)) continue;
    for (const match of withoutComments(source.text).matchAll(EXTENSION)) {
      if (unquote(match[1]!) === extension) return unquote(match[2]!);
    }
  }
  return undefined;
}
