import type { CatalogPolicy } from "../config/snapshot.ts";

/** A command a policy applies to. */
export type PolicyCommand = "all" | "select" | "insert" | "update" | "delete";

/**
 * One row level security policy (ADR 0103). `table` is `schema.table`,
 * unquoted; a name without a schema is in `public`. `roles` lists the roles it
 * applies to, `["public"]` when the statement names none.
 */
export interface Policy {
  readonly table: string;
  readonly name: string;
  readonly command: PolicyCommand;
  readonly roles: readonly string[];
  readonly permissive: boolean;
  readonly using: string | null;
  readonly check: string | null;
}

/** What `policy()` takes: only the table and the name are required. */
export interface PolicyInput {
  readonly table: string;
  readonly name: string;
  readonly command?: PolicyCommand;
  readonly roles?: readonly string[];
  readonly permissive?: boolean;
  readonly using?: string | null;
  readonly check?: string | null;
}

/** A policy with the defaults Postgres uses: `for all to public`, permissive. */
export function policy(input: PolicyInput): Policy {
  return {
    table: qualifiedName(input.table),
    name: input.name,
    command: input.command ?? "all",
    roles: input.roles ?? ["public"],
    permissive: input.permissive ?? true,
    using: input.using ?? null,
    check: input.check ?? null,
  };
}

/** The catalog shape of `policy`, without its table. */
export function catalogPolicy(entry: Policy): CatalogPolicy {
  return {
    name: entry.name,
    command: entry.command,
    roles: entry.roles,
    permissive: entry.permissive,
    using: entry.using,
    check: entry.check,
  };
}

const PLAIN = /^[a-z_][a-z0-9_$]*$/;

/** `name`, double quoted unless it is a plain lowercase identifier. */
function quoteIdentifier(name: string): string {
  return PLAIN.test(name) ? name : `"${name.replaceAll('"', '""')}"`;
}

/** `schema.table` quoted for SQL. */
function quotedTable(table: string): string {
  return qualifiedName(table).split(".").map(quoteIdentifier).join(".");
}

function qualifiedName(table: string): string {
  const parts = splitName(table);

  return parts.length === 1 ? `public.${parts[0] ?? ""}` : parts.join(".");
}

/** The parts of a possibly quoted `a.b` name, unquoted. */
function splitName(name: string): string[] {
  const parts: string[] = [];
  let current = "";
  let quoted = false;

  for (let index = 0; index < name.length; index += 1) {
    const char = name[index] ?? "";

    if (quoted) {
      if (char === '"' && name[index + 1] === '"') {
        current += '"';
        index += 1;
      } else if (char === '"') {
        quoted = false;
      } else {
        current += char;
      }
    } else if (char === '"') {
      quoted = true;
    } else if (char === ".") {
      parts.push(current);
      current = "";
    } else if (!/\s/.test(char)) {
      current += char.toLowerCase();
    }
  }

  return [...parts, current];
}

export interface RenderPolicyOptions {
  /** A `drop policy if exists` line before the `create policy`. */
  readonly drop?: boolean;
  /** The table as the caller writes it, instead of the quoted `schema.table`. */
  readonly target?: string;
}

/**
 * The `create policy` statement for `entry`, in the layout the block modules
 * use: the header on one line, then `for`, `using` and `with check` on their
 * own lines, ending with a semicolon.
 */
export function renderPolicy(
  entry: Policy,
  options: RenderPolicyOptions = {},
): string {
  const table = options.target ?? quotedTable(entry.table);

  const lines = [
    `create policy ${quoteIdentifier(entry.name)} on ${table}${entry.permissive ? "" : " as restrictive"}`,
    `  for ${entry.command} to ${entry.roles.map(quoteIdentifier).join(", ")}`,
  ];

  if (entry.using !== null) {
    lines.push(`  using (${entry.using})`);
  }

  if (entry.check !== null) {
    lines.push(`  with check (${entry.check})`);
  }

  const statement = `${lines.join("\n")};`;

  return options.drop === true
    ? `drop policy if exists ${quoteIdentifier(entry.name)} on ${table};\n${statement}`
    : statement;
}

export interface MaskOptions {
  /**
   * `"scan"` leaves the text of dollar-quoted bodies as code, so a scan finds
   * the statements a `do` block or a function runs. Default: they are blanked.
   */
  readonly dollarBodies?: "mask" | "scan";
}

const DOLLAR_TAG = /\$(?:[A-Za-z_]\w*)?\$/y;

/**
 * `sql` with the text of comments, string literals, dollar-quoted bodies and
 * quoted identifiers blanked, so a scan for keywords and parentheses can't
 * match inside them. Offsets stay the same; line breaks stay.
 */
export function maskSql(sql: string, options: MaskOptions = {}): string {
  const special =
    options.dollarBodies === "scan" ? /--|\/\*|['"]/g : /--|\/\*|['"$]/g;

  const parts: string[] = [];
  let copied = 0;

  const blank = (from: number, to: number, fill = " "): void => {
    const stop = Math.min(to, sql.length);

    if (from < stop) {
      parts.push(
        sql.slice(copied, from),
        sql.slice(from, stop).replaceAll(/[^\n]/g, fill),
      );
      copied = stop;
    }
  };

  let at = 0;

  while (at < sql.length) {
    special.lastIndex = at;
    const match = special.exec(sql);

    if (match === null) {
      break;
    }

    at = match.index;
    const token = match[0];

    if (token === "--") {
      const end = sql.indexOf("\n", at);
      const stop = end === -1 ? sql.length : end;

      blank(at, stop);
      at = stop;
    } else if (token === "/*") {
      let depth = 1;
      let end = at + 2;

      while (end < sql.length && depth > 0) {
        if (sql.startsWith("/*", end)) {
          depth += 1;
          end += 2;
        } else if (sql.startsWith("*/", end)) {
          depth -= 1;
          end += 2;
        } else {
          end += 1;
        }
      }

      blank(at, end);
      at = end;
    } else if (token === "'") {
      const escaped =
        /[eE]/.test(sql[at - 1] ?? "") && !/\w/.test(sql[at - 2] ?? " ");

      let end = at + 1;

      while (end < sql.length) {
        if (escaped && sql[end] === "\\") {
          end += 2;
        } else if (sql[end] === "'" && sql[end + 1] === "'") {
          end += 2;
        } else if (sql[end] === "'") {
          break;
        } else {
          end += 1;
        }
      }

      blank(at + 1, end);
      at = Math.min(end + 1, sql.length);
    } else if (token === '"') {
      let end = at + 1;

      while (end < sql.length) {
        if (sql[end] === '"' && sql[end + 1] === '"') {
          end += 2;
        } else if (sql[end] === '"') {
          break;
        } else {
          end += 1;
        }
      }

      blank(at + 1, end, "_");
      at = Math.min(end + 1, sql.length);
    } else {
      DOLLAR_TAG.lastIndex = at;
      const tag = DOLLAR_TAG.exec(sql)?.[0];

      if (tag !== undefined && !/\w/.test(sql[at - 1] ?? " ")) {
        const close = sql.indexOf(tag, at + tag.length);
        const stop = close === -1 ? sql.length : close;

        blank(at + tag.length, stop);
        at = Math.min(stop + tag.length, sql.length);
      } else {
        at += 1;
      }
    }
  }

  parts.push(sql.slice(copied));

  return parts.join("");
}

/**
 * The `[start, end)` of each statement of masked SQL that starts with
 * `keyword`: from the keyword to the first semicolon outside parentheses.
 */
function keywordRanges(masked: string, keyword: RegExp): [number, number][] {
  const ranges: [number, number][] = [];
  const pattern = new RegExp(keyword.source, "gi");

  for (const match of masked.matchAll(pattern)) {
    let depth = 0;
    let end = masked.length;

    for (let index = match.index; index < masked.length; index += 1) {
      const char = masked[index];

      if (char === "(") {
        depth += 1;
      } else if (char === ")") {
        depth -= 1;
      } else if (char === ";" && depth <= 0) {
        end = index + 1;
        break;
      }
    }

    ranges.push([match.index, end]);
  }

  return ranges;
}

const HEADER =
  /^\s*create\s+policy\s+("(?:[^"]|"")+"|[a-z_][\w$]*)\s+on\s+("(?:[^"]|"")+"|[a-z_][\w$]*)(?:\s*\.\s*("(?:[^"]|"")+"|[a-z_][\w$]*))?/diy;

/** A policy found in a script, with where its statement sits. */
export interface ReadPolicy {
  readonly policy: Policy;
  /** The statement, from `create policy` to its semicolon, as written. */
  readonly statement: string;
  /** The `[start, end)` of the statement in the script. */
  readonly span: readonly [number, number];
}

function clauseBody(
  original: string,
  masked: string,
  keyword: RegExp,
): { readonly at: number; readonly body: string } | "unbalanced" | undefined {
  const match = keyword.exec(masked);

  if (match === null) {
    return undefined;
  }

  const open = match.index + match[0].length - 1;
  const close = closingParen(masked, open);

  return close === -1
    ? "unbalanced"
    : { at: match.index, body: original.slice(open + 1, close) };
}

/** The first of `statement`'s clauses that sit at the top level. */
function readStatement(original: string, masked: string): Policy | undefined {
  HEADER.lastIndex = 0;
  const head = HEADER.exec(masked);

  if (head === null) {
    return undefined;
  }

  const raw = (group: number): string => {
    const span = head.indices?.[group];

    return span === undefined ? "" : original.slice(span[0], span[1]);
  };

  const first = raw(2);
  const second = head[3] === undefined ? undefined : raw(3);
  const name = splitName(raw(1)).join(".");

  const table = qualifiedName(
    second === undefined ? first : `${first}.${second}`,
  );

  const using = clauseBody(original, masked, /\busing\s*\(/i);
  const check = clauseBody(original, masked, /\bwith\s+check\s*\(/i);

  if (using === "unbalanced" || check === "unbalanced") {
    return undefined;
  }

  const header = masked.slice(
    head[0].length,
    Math.min(using?.at ?? masked.length, check?.at ?? masked.length),
  );

  const named = /\bfor\s+(all|select|insert|update|delete)\b/i
    .exec(header)?.[1]
    ?.toLowerCase();

  const commands: readonly PolicyCommand[] = [
    "all",
    "select",
    "insert",
    "update",
    "delete",
  ];

  const roles = /\bto\s+([\s\S]+?);?\s*$/i.exec(header)?.[1];

  return {
    table,
    name,
    command: commands.find((entry) => entry === named) ?? "all",
    roles:
      roles === undefined
        ? ["public"]
        : roles
            .split(",")
            .map((role) => splitName(role.trim()).join("."))
            .filter((role) => role !== ""),
    permissive: !/\bas\s+restrictive\b/i.test(header),
    using: using?.body ?? null,
    check: check?.body ?? null,
  };
}

/**
 * Every `create policy` statement of `sql`. Comments, string literals,
 * dollar-quoted bodies and quoted names can't confuse the scan. A statement
 * that isn't a well-formed `create policy` is skipped.
 */
export function readPolicies(sql: string): ReadPolicy[] {
  const masked = maskSql(sql, { dollarBodies: "scan" });
  const found: ReadPolicy[] = [];

  for (const [from, to] of keywordRanges(masked, /\bcreate\s+policy\b/)) {
    const original = sql.slice(from, to);
    const read = readStatement(original, masked.slice(from, to));

    if (read !== undefined) {
      found.push({
        policy: read,
        statement: original.trim(),
        span: [from + (original.length - original.trimStart().length), to],
      });
    }
  }

  return found;
}

/** The policy one `create policy` statement creates. */
export function readPolicy(statement: string): Policy | undefined {
  return readPolicies(statement)[0]?.policy;
}

/** A grant of privileges on a table to roles. */
export interface Grant {
  /** `schema.table`, unquoted. */
  readonly table: string;
  readonly roles: readonly string[];
}

const GRANT =
  /^\s*grant\s+[\s\S]+?\s+on\s+(?:table\s+)?("(?:[^"]|"")+"|[a-z_][\w$]*)(?:\s*\.\s*("(?:[^"]|"")+"|[a-z_][\w$]*))?\s+to\s+([\s\S]+?);?\s*$/di;

/** The table grants of `sql`, read past comments, strings and dollar quotes. */
export function readGrants(sql: string): Grant[] {
  const masked = maskSql(sql, { dollarBodies: "scan" });
  const grants: Grant[] = [];

  for (const [from, to] of keywordRanges(masked, /\bgrant\b/)) {
    const statement = masked.slice(from, to);
    const match = GRANT.exec(statement);

    if (match !== null) {
      const pick = (group: number): string | undefined => {
        const span = match.indices?.[group];

        return span === undefined
          ? undefined
          : sql.slice(from + span[0], from + span[1]);
      };

      const first = pick(1) ?? "";
      const second = pick(2);

      grants.push({
        table: qualifiedName(
          second === undefined ? first : `${first}.${second}`,
        ),
        roles: (match[3] ?? "")
          .split(",")
          .map((role) => role.trim().toLowerCase())
          .filter((role) => role !== ""),
      });
    }
  }

  return grants;
}

/** The index of the `)` that closes the `(` at `open`, or -1. */
export function closingParen(text: string, open: number): number {
  let depth = 0;
  let quote: string | undefined;

  for (let i = open; i < text.length; i += 1) {
    const char = text[i]!;

    if (quote) {
      if (char === quote && text[i + 1] === quote) {
        i += 1;
      } else if (char === quote) {
        quote = undefined;
      }
    } else if (char === "'") {
      quote = char;
    } else if (char === "(") {
      depth += 1;
    } else if (char === ")") {
      depth -= 1;

      if (depth === 0) {
        return i;
      }
    }
  }

  return -1;
}
