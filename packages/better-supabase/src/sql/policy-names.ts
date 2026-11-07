import { maskSql } from "./policy.ts";
import { shortHash } from "./shared.ts";

const MAX_NAME = 63;

/**
 * The name a generated policy carries: `bsb_` ahead of the name a module wrote,
 * shortened with a hash when it passes 63 bytes (ADR 0272). A name that already
 * starts with `bsb_` and fits stays as it is.
 */
export function bsbPolicyName(name: string): string {
  const full = name.startsWith("bsb_") ? name : `bsb_${name}`;

  return full.length <= MAX_NAME
    ? full
    : `${full.slice(0, MAX_NAME - 9)}_${shortHash(full)}`;
}

const STATEMENT =
  /\b(create|drop|alter)\s+policy\s+(if\s+exists\s+)?(?=("(?:[^"]|"")+"|[a-z_][\w$]*))/gi;

interface Found {
  readonly kind: string;
  /** `[start, end)` of the name as written, quotes included. */
  readonly span: readonly [number, number];
  readonly name: string;
}

function found(sql: string): Found[] {
  const masked = maskSql(sql, { dollarBodies: "scan" });
  const out: Found[] = [];

  for (const match of masked.matchAll(STATEMENT)) {
    const start = match.index + match[0].length;
    const rest = sql.slice(start);
    const quoted = /^"((?:[^"]|"")+)"/.exec(rest);
    const bare = /^[a-z_][\w$]*/i.exec(rest);

    if (quoted !== null) {
      out.push({
        kind: match[1]!.toLowerCase(),
        span: [start, start + quoted[0].length],
        name: quoted[1]!.replaceAll('""', '"'),
      });
    } else if (bare !== null) {
      out.push({
        kind: match[1]!.toLowerCase(),
        span: [start, start + bare[0].length],
        name: bare[0].toLowerCase(),
      });
    }
  }

  return out;
}

const PLAIN = /^[a-z_][a-z0-9_$]*$/;

const write = (name: string): string =>
  PLAIN.test(name) ? name : `"${name.replaceAll('"', '""')}"`;

/**
 * `sql` with every policy it creates named `bsb_*`, in the `create`, `alter`
 * and `drop` statements alike. A `drop policy if exists` for a name the text
 * never creates stays: it removes a policy an earlier release wrote.
 */
export function bsbPolicyNames(sql: string): string {
  const all = found(sql);

  const created = new Set(
    all.filter((entry) => entry.kind === "create").map((entry) => entry.name),
  );

  let out = "";
  let cursor = 0;

  for (const entry of all) {
    if (!created.has(entry.name)) {
      continue;
    }

    const next = bsbPolicyName(entry.name);

    if (next !== entry.name) {
      out += sql.slice(cursor, entry.span[0]) + write(next);
      cursor = entry.span[1];
    }
  }

  return out + sql.slice(cursor);
}
