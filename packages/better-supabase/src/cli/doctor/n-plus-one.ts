import type { Snapshot } from "../../config/index.ts";
import type { DoctorContext, FindingInput, Rule, TextFile } from "./rules.ts";

import { codeRanges } from "../code-ranges.ts";

/**
 * A database read in app code: a repository read, a block client call, an RPC,
 * a supabase-js `.from().select()`, a local function that only reads, or a read
 * method on a service object.
 */
interface Read {
  readonly start: number;
  /** The `(` that opens the call's arguments. */
  readonly open: number;
  readonly close: number;
  /** `db.customers.get`, as written. */
  readonly call: string;
  /** The repository or `.from()` table, when the call names one. */
  readonly table?: string;
  /** The repository method: `get`, `list`, `count`. */
  readonly method?: string;
  readonly kind: "table" | "rpc" | "other";
}

/** An include on one table that loads rows of another. */
interface Relation {
  readonly name: string;
  readonly many: boolean;
}

interface Scope {
  readonly start: number;
  readonly end: number;
  /** The iterated expression, such as `rows` or `page.ids`. */
  readonly items: string;
  /** The loop variable and the callback parameters. */
  readonly names: readonly string[];
}

/** A variable that holds rows an earlier awaited read returned. */
interface Origin {
  readonly name: string;
  readonly table: string;
  readonly call: string;
  readonly line: number;
  readonly from: number;
  readonly to: number;
}

/**
 * A receiver that names the better-supabase client: `db`, `ctx.db`, `tx`,
 * `bsb.db()`.
 */
const DB = String.raw`(?<![\w$])(?:db|[a-z][\w$]*Db|tx|trx)(?:\(\))?`;

const REPOSITORY_READ = new RegExp(
  String.raw`${DB}\s*\.\s*([A-Za-z_][\w$]*)\s*\.\s*(get|list|page|count|counted|aggregate|first|find[A-Z]?[\w$]*)\s*\(`,
  "g",
);

const BLOCK_CALL = new RegExp(
  String.raw`(?:${DB}\s*\.\s*\$blocks|(?<![\w$])blocks)\s*\.\s*[\w$]+\s*\.\s*([\w$]+)\s*\(`,
  "g",
);

const RPC_CALL =
  /\.\s*\$(?:rpc|search|run|many)\s*\(|(?<![\w$])[\w$]*supabase[\w$]*\s*\.\s*rpc\s*\(/gi;

const FROM_SELECT = /\.\s*from\s*\(([\w$.\s]*)\)\s*\.\s*select\s*\(/g;

const SERVICE_READ =
  /(?<![\w$])([\w$]+)\s*\.\s*((?:get|list|load|find|fetch|count|read|search)[A-Z][\w$]*)\s*\(/g;

const SERVICE_WRITE = /(?<![\w$])([\w$]+)\s*\.\s*([a-z][\w$]*)\s*\(/g;

const SERVICE_NAME =
  /(?:services?|repositor(?:y|ies)|repos?|queries|readers?)$/i;

const SERVICE_FACTORY =
  /(?:const|let)\s+(\{[^}]*\}|[\w$]+)\s*=\s*(?:await\s+)?create[\w$]*(?:Services?|Repositor(?:y|ies)|Repos?)\s*\(/g;

/** A block method or a local function whose name says it writes. */
const WRITE_NAME =
  /^(?:create|insert|update|upsert|delete|remove|set|add|save|send|enqueue|record|mark|approve|reject|cancel|archive|restore|move|assign|unassign|post|submit|publish|attach|detach|link|unlink|invite|revoke|grant|start|stop|complete|close|open|lock|unlock|apply|import|sync|refresh|recompute|merge|reorder|rename|toggle|track|emit|notify|write|put|patch|claim|release|issue|void|pay|charge|refund|transfer|book|confirm|accept|decline|resolve|reopen|pin|unpin|join|leave|subscribe|unsubscribe|upload|clear|reset|seed|ensure|process|run|execute|handle|dispatch|schedule|retry|replace|increment|decrement|bump|touch|finalize|commit|enable|disable|activate|deactivate|generate|log|accrue)(?:[A-Z_\d]|$)/;

const REPOSITORY_WRITE = new RegExp(
  String.raw`${DB}\s*\.\s*[A-Za-z_][\w$]*\s*\.\s*(?:create|update|upsert|delete)\s*\(|\.\s*from\s*\([\w$.\s]*\)\s*\.\s*(?:insert|update|upsert|delete)\s*\(`,
);

const LOCAL_FUNCTION =
  /(?:function\s*\*?\s*([\w$]+)\s*(?:<[^>]*>)?\s*\(|(?:const|let)\s+([\w$]+)\s*(?::[^=]+)?=\s*(?:async\s+)?(?:function\b[^(]*\(|\(|[\w$]+\s*=>))/g;

const LOOP = /(?<![\w$.])for\s*(?:await\s*)?\(/g;

const CALLBACK = /\.\s*(?:map|flatMap|forEach)\s*\(/g;

const DECLARATION =
  /(?<![\w$.])(?:const|let|var)\s+([\w$]+|\{[^=;]*?\}|\[[^=;]*?\])\s*(?::[^=;]+)?=(?!=|>)/g;

/**
 * Iterables that are already batches, or retries of one read: `for (const chunk
 * of chunks)`, `for (const attempt of attempts)`.
 */
const BATCHES = /chunk|batch|attempt|retr/i;

const OPEN = new Set(["(", "[", "{"]);
const CLOSE = new Set([")", "]", "}"]);

/** `text` with strings, template literals and comments blanked, offsets kept. */
function codeOnly(text: string): string {
  let out = "";
  let last = 0;
  const blank = (part: string): string => part.replaceAll(/[^\n]/g, " ");

  for (const [start, end] of codeRanges(text)) {
    out += blank(text.slice(last, start)) + text.slice(start, end);
    last = end;
  }

  return out + blank(text.slice(last));
}

/** The index of the bracket that closes the one at `open`. */
function closeOf(code: string, open: number): number {
  let depth = 0;

  for (let index = open; index < code.length; index += 1) {
    const char = code.charAt(index);

    if (OPEN.has(char)) {
      depth += 1;
    } else if (CLOSE.has(char)) {
      depth -= 1;

      if (depth === 0) {
        return index;
      }
    }
  }

  return code.length;
}

/** The end of the statement or expression that starts at `from`. */
function statementEnd(code: string, from: number): number {
  let depth = 0;

  for (let index = from; index < code.length; index += 1) {
    const char = code.charAt(index);

    if (OPEN.has(char)) {
      depth += 1;
    } else if (CLOSE.has(char)) {
      if (depth === 0) {
        return index;
      }

      depth -= 1;
    } else if ((char === ";" || char === ",") && depth === 0) {
      return index;
    }
  }

  return code.length;
}

/** The names a binding pattern declares: `x`, `{ a, b: c }`, `[d, ...e]`. */
function boundNames(pattern: string): string[] {
  const trimmed = pattern.trim();

  if (!trimmed.startsWith("{") && !trimmed.startsWith("[")) {
    return /^[\w$]+$/.test(trimmed) ? [trimmed] : [];
  }

  return [...trimmed.matchAll(/[A-Za-z_$][\w$]*(?!\s*:)/g)]
    .filter((match) => trimmed.charAt(match.index - 1) !== ".")
    .map((match) => match[0]);
}

/** The bound names of a parameter list, without types and defaults. */
function parameterNames(list: string): string[] {
  const names: string[] = [];
  let depth = 0;
  let start = 0;

  const take = (part: string): void => {
    let inner = 0;
    let end = part.length;

    for (let index = 0; index < part.length; index += 1) {
      const char = part.charAt(index);

      inner += OPEN.has(char) ? 1 : CLOSE.has(char) ? -1 : 0;

      if (inner === 0 && (char === ":" || char === "=")) {
        end = index;
        break;
      }
    }

    names.push(...boundNames(part.slice(0, end).replace(/^\s*\.\.\./, "")));
  };

  for (let index = 0; index < list.length; index += 1) {
    const char = list.charAt(index);

    depth += OPEN.has(char) ? 1 : CLOSE.has(char) ? -1 : 0;

    if (char === "," && depth === 0) {
      take(list.slice(start, index));
      start = index + 1;
    }
  }

  take(list.slice(start));

  return names;
}

/** Whether `text` uses `name` as a value, not as a key or a property. */
function mentions(text: string, name: string): boolean {
  const escaped = name.replaceAll("$", String.raw`\$`);

  return new RegExp(
    String.raw`(?<![\w$.])${escaped}(?![\w$])(?!\s*:(?!:))`,
  ).test(text);
}

const camel = (name: string): string =>
  name.replaceAll(/_([a-z\d])/g, (_, char: string) => char.toUpperCase());

const compact = (text: string): string =>
  text
    .replaceAll(/\s+/g, " ")
    .replaceAll(/\s*\.\s*/g, ".")
    .replaceAll(/([([])\s+|\s+(?=[)\]])/g, "$1")
    .trim();

/** `customer_assets` and `customerAssets` compare equal. */
const tableKey = (name: string): string =>
  name.toLowerCase().replaceAll("_", "");

const rpcName = (text: string, open: number): string | undefined =>
  /^\s*["'`]([\w.]+)/
    .exec(text.slice(open + 1))?.[1]
    ?.split(".")
    .at(-1);

/**
 * Offsets of calls that write: repository and supabase-js writes, RPCs, block
 * methods and service methods named for a write.
 */
function writesIn(
  text: string,
  code: string,
  services: ReadonlySet<string>,
): number[] {
  const writes = [...code.matchAll(new RegExp(REPOSITORY_WRITE, "g"))].map(
    (match) => match.index,
  );

  for (const match of code.matchAll(RPC_CALL)) {
    const name = rpcName(text, match.index + match[0].length - 1);

    if (name !== undefined && WRITE_NAME.test(camel(name))) {
      writes.push(match.index);
    }
  }

  for (const match of code.matchAll(BLOCK_CALL)) {
    if (WRITE_NAME.test(match[1]!)) {
      writes.push(match.index);
    }
  }

  for (const match of code.matchAll(SERVICE_WRITE)) {
    if (isService(match[1]!, services) && WRITE_NAME.test(match[2]!)) {
      writes.push(match.index);
    }
  }

  return writes;
}

/** Reads by the database client itself, before following local functions. */
function directReads(text: string, code: string): Read[] {
  const reads: Read[] = [];

  const add = (
    match: RegExpMatchArray,
    kind: Read["kind"],
    table?: string,
    method?: string,
  ): void => {
    const open = match.index! + match[0].length - 1;
    let call = compact(text.slice(match.index, open));

    if (kind === "rpc") {
      const name = rpcName(text, open);

      if (name !== undefined && WRITE_NAME.test(camel(name))) {
        return;
      }

      call = name === undefined ? call : `${call}("${name}")`;
    }

    let close = closeOf(code, open);

    if (kind === "table" && method === undefined) {
      for (
        let next = /^\s*\.\s*[\w$]+\s*\(/.exec(code.slice(close + 1));
        next;
        next = /^\s*\.\s*[\w$]+\s*\(/.exec(code.slice(close + 1))
      ) {
        close = closeOf(code, close + next[0].length);
      }
    }

    reads.push({
      start: match.index!,
      open,
      close,
      call,
      kind,
      ...(table === undefined ? {} : { table }),
      ...(method === undefined ? {} : { method }),
    });
  };

  for (const match of code.matchAll(REPOSITORY_READ)) {
    add(match, "table", match[1], match[2]);
  }

  for (const match of code.matchAll(BLOCK_CALL)) {
    if (!WRITE_NAME.test(match[1]!)) {
      add(match, "other");
    }
  }

  for (const match of code.matchAll(RPC_CALL)) {
    add(match, "rpc");
  }

  for (const match of code.matchAll(FROM_SELECT)) {
    const from = match.index + match[0].indexOf("(");

    const table = /["'`]([\w.]+)["'`]/.exec(
      text.slice(from, from + match[1]!.length + 2),
    )?.[1];

    add(match, "table", table?.split(".").at(-1));
  }

  return reads;
}

/**
 * Local functions that read and never write, followed through each other within
 * the file, mapped to the read they make.
 */
function readerFunctions(
  code: string,
  direct: readonly Read[],
): Map<string, Read> {
  const bodies = new Map<string, { start: number; end: number }>();

  for (const match of code.matchAll(LOCAL_FUNCTION)) {
    const name = match[1] ?? match[2]!;
    const params = match.index + match[0].length - 1;

    const afterParams =
      code.charAt(params) === "(" ? closeOf(code, params) + 1 : params;

    const arrow = code.indexOf("=>", afterParams);
    const brace = code.indexOf("{", afterParams);

    const start =
      arrow !== -1 && (brace === -1 || arrow < brace) ? arrow + 2 : brace;

    if (start === -1 || WRITE_NAME.test(name)) {
      continue;
    }

    const open = /^\s*\{/.test(code.slice(start))
      ? code.indexOf("{", start)
      : -1;

    const end = open === -1 ? statementEnd(code, start) : closeOf(code, open);

    bodies.set(name, { start, end });
  }

  const readers = new Map<string, Read>();

  for (const [name, body] of bodies) {
    const slice = code.slice(body.start, body.end);

    const read = direct.find(
      (candidate) => candidate.start > body.start && candidate.start < body.end,
    );

    if (read !== undefined && !REPOSITORY_WRITE.test(slice)) {
      readers.set(name, read);
    }
  }

  let grew = true;

  while (grew) {
    grew = false;

    for (const [name, body] of bodies) {
      if (readers.has(name)) {
        continue;
      }

      const slice = code.slice(body.start, body.end);

      if (REPOSITORY_WRITE.test(slice)) {
        continue;
      }

      for (const [reader, read] of readers) {
        if (reader !== name && callsOf(slice, reader).length > 0) {
          readers.set(name, read);
          grew = true;
          break;
        }
      }
    }
  }

  return readers;
}

/** Offsets of `name(` calls that aren't a property, a definition or a method. */
function callsOf(code: string, name: string): number[] {
  const escaped = name.replaceAll("$", String.raw`\$`);

  return [
    ...code.matchAll(new RegExp(String.raw`(?<![\w$.])${escaped}\s*\(`, "g")),
  ]
    .filter(
      (match) =>
        !/(?:function\s*\*?\s*|async\s+)$/.test(code.slice(0, match.index)),
    )
    .map((match) => match.index);
}

/** Names bound to the result of a `create...Service(...)` factory. */
function serviceNames(code: string): Set<string> {
  const services = new Set<string>();

  for (const match of code.matchAll(SERVICE_FACTORY)) {
    for (const name of boundNames(match[1]!)) {
      services.add(name);
    }
  }

  return services;
}

const isService = (receiver: string, services: ReadonlySet<string>): boolean =>
  services.has(receiver) || SERVICE_NAME.test(receiver);

/** Every read in the file, including calls to readers and service reads. */
function readsIn(
  text: string,
  code: string,
  services: ReadonlySet<string>,
): Read[] {
  const direct = directReads(text, code);
  const reads = [...direct];

  for (const [name, read] of readerFunctions(code, direct)) {
    for (const start of callsOf(code, name)) {
      const open = code.indexOf("(", start);

      reads.push({
        start,
        open,
        close: closeOf(code, open),
        call: `${name} (which calls ${read.call})`,
        kind: "other",
      });
    }
  }

  for (const match of code.matchAll(SERVICE_READ)) {
    const receiver = match[1]!;

    if (!isService(receiver, services)) {
      continue;
    }

    const open = match.index + match[0].length - 1;

    reads.push({
      start: match.index,
      open,
      close: closeOf(code, open),
      call: `${receiver}.${match[2]!}`,
      kind: "other",
    });
  }

  return reads.toSorted((a, b) => a.start - b.start);
}

/** The expression before `.map(` that starts at `end`, such as `page.ids`. */
function receiverBefore(code: string, end: number): string {
  let start = end;

  while (start > 0) {
    const char = code.charAt(start - 1);

    if (char === ")" || char === "]") {
      let depth = 0;

      for (start -= 1; start >= 0; start -= 1) {
        const inner = code.charAt(start);

        depth += CLOSE.has(inner) ? 1 : OPEN.has(inner) ? -1 : 0;

        if (depth === 0) {
          break;
        }
      }
    } else if (
      /[\w$.?!]/.test(char) ||
      (/\s/.test(char) && /^\??\./.test(code.slice(start).trimStart()))
    ) {
      start -= 1;
    } else {
      break;
    }
  }

  return code
    .slice(start, end)
    .trim()
    .replace(/^\.\.\./, "");
}

/** `for (... of ...)` bodies and `.map/.flatMap/.forEach` callbacks. */
function scopesIn(code: string): Scope[] {
  const scopes: Scope[] = [];

  for (const match of code.matchAll(LOOP)) {
    const open = match.index + match[0].length - 1;
    const close = closeOf(code, open);

    const header = /^\s*(?:const|let|var)\s+([\s\S]+?)\s+of\s+([\s\S]+)$/.exec(
      code.slice(open + 1, close),
    );

    if (!header) {
      continue;
    }

    const bodyStart = close + 1;
    const brace = /^\s*\{/.test(code.slice(bodyStart));

    const end = brace
      ? closeOf(code, code.indexOf("{", bodyStart))
      : statementEnd(code, bodyStart);

    scopes.push({
      start: bodyStart,
      end,
      items: compact(header[2]!),
      names: boundNames(header[1]!),
    });
  }

  for (const match of code.matchAll(CALLBACK)) {
    const open = match.index + match[0].length - 1;
    const close = closeOf(code, open);

    const callback =
      /^\s*(?:async\s+)?(?:function\s*[\w$]*\s*\(|\(|([\w$]+)\s*=>)/.exec(
        code.slice(open + 1, close),
      );

    if (!callback) {
      continue;
    }

    let names: string[];
    let start: number;

    if (callback[1] === undefined) {
      const params = open + callback[0].length;
      const paramsEnd = closeOf(code, params);

      names = parameterNames(code.slice(params + 1, paramsEnd));
      start = paramsEnd + 1;
    } else {
      names = [callback[1]];
      start = open + 1 + callback[0].length;
    }

    scopes.push({
      start,
      end: close,
      items: compact(receiverBefore(code, match.index)),
      names,
    });
  }

  return scopes.toSorted((a, b) => a.end - a.start - (b.end - b.start));
}

/** Names in `scope` that hold the loop variable, or something derived from it. */
function scopeNames(code: string, scope: Scope): string[] {
  const names = [...scope.names];
  const body = code.slice(scope.start, scope.end);

  for (const match of body.matchAll(DECLARATION)) {
    const from = match.index + match[0].length;
    const init = body.slice(from, statementEnd(body, from));

    if (names.some((name) => mentions(init, name))) {
      names.push(...boundNames(match[1]!));
    }
  }

  return names;
}

/** The innermost `{` before `at` that is still open there, and its close. */
function enclosingEnd(code: string, at: number): number {
  let depth = 0;

  for (let index = at; index < code.length; index += 1) {
    const char = code.charAt(index);

    if (OPEN.has(char)) {
      depth += 1;
    } else if (CLOSE.has(char)) {
      depth -= 1;

      if (depth < 0) {
        return index;
      }
    }
  }

  return code.length;
}

/** Variables that hold rows of an earlier awaited table read, and their scope. */
function originsIn(
  text: string,
  code: string,
  reads: readonly Read[],
): Origin[] {
  const origins: Origin[] = [];
  const lineAt = lines(text);

  for (const match of code.matchAll(DECLARATION)) {
    const from = match.index + match[0].length;
    const end = statementEnd(code, from);
    const init = code.slice(from, end);
    const names = boundNames(match[1]!);
    const scope = { from: end, to: enclosingEnd(code, match.index) };

    const inside = reads.filter(
      (read) => read.start >= from && read.start < end,
    );

    if (/^\s*await\b/.test(init) && inside.length > 0) {
      const all = /^\s*await\s+Promise\.all\s*\(\s*\[/.exec(init);
      const pattern = match[1]!.trim();

      if (all && pattern.startsWith("[")) {
        const entries = splitTop(
          code.slice(
            from + all[0].length,
            closeOf(code, from + all[0].length - 1),
          ),
        );

        let offset = from + all[0].length;

        for (const [index, entry] of entries.entries()) {
          const [low, high] = [offset, offset + entry.length];

          const read = inside.find(
            (candidate) => candidate.start >= low && candidate.start < high,
          );

          const name = boundNames(
            `[${splitTop(pattern.slice(1, -1))[index] ?? ""}]`,
          )[0];

          offset += entry.length + 1;

          if (read?.table !== undefined && name !== undefined) {
            origins.push({
              name,
              table: read.table,
              call: read.call,
              line: lineAt(read.start),
              ...scope,
            });
          }
        }

        continue;
      }

      const read = inside[0]!;

      if (read.table !== undefined) {
        for (const name of names) {
          origins.push({
            name,
            table: read.table,
            call: read.call,
            line: lineAt(read.start),
            ...scope,
          });
        }
      }

      continue;
    }

    const source = origins.findLast(
      (origin) =>
        match.index >= origin.from &&
        match.index < origin.to &&
        mentions(init, origin.name),
    );

    if (source) {
      for (const name of names) {
        origins.push({ ...source, name, ...scope });
      }
    }
  }

  return origins;
}

/** Parts of `list` split at top-level commas. */
function splitTop(list: string): string[] {
  const parts: string[] = [];
  let depth = 0;
  let start = 0;

  for (let index = 0; index < list.length; index += 1) {
    const char = list.charAt(index);

    depth += OPEN.has(char) ? 1 : CLOSE.has(char) ? -1 : 0;

    if (char === "," && depth === 0) {
      parts.push(list.slice(start, index));
      start = index + 1;
    }
  }

  parts.push(list.slice(start));

  return parts;
}

function lines(text: string): (index: number) => number {
  const starts = [0];

  for (let index = 0; index < text.length; index += 1) {
    if (text.charAt(index) === "\n") {
      starts.push(index + 1);
    }
  }

  return (index) => {
    let low = 0;
    let high = starts.length - 1;

    while (low < high) {
      const mid = Math.ceil((low + high) / 2);

      if (starts[mid]! <= index) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }

    return low + 1;
  };
}

/**
 * The include on `outer` that loads the `inner` rows `args` asks for, from the
 * snapshot's foreign keys: `customer` when `outer` holds the key and `args`
 * filters on the column it references, `notes` when `inner` holds the key and
 * `args` filters on it.
 */
function relationTo(
  snapshot: Snapshot,
  outer: string,
  inner: Read,
  args: string,
): Relation | undefined {
  const table = inner.table;

  if (table === undefined || tableKey(outer) === tableKey(table)) {
    return undefined;
  }

  const camelCase = /[A-Z]/.test(outer + table);
  const name = (raw: string): string => (camelCase ? camel(raw) : raw);

  const filters = (column: string | undefined): boolean =>
    column !== undefined &&
    new RegExp(
      String.raw`(?<![\w$])(?:${column}|${camel(column)})\s*:|["'\`]${column}["'\`]\s*,`,
    ).test(args);

  const candidates: Relation[] = [];

  const named = (column: string): boolean =>
    new RegExp(
      String.raw`(?<![\w$])(?:${column}|${camel(column)})(?![\w$])`,
    ).test(args);

  for (const relation of snapshot.generator.relationships) {
    const from = tableKey(relation.relation);
    const to = tableKey(relation.referenced_relation);
    const [column] = relation.columns;

    if (column === undefined) {
      continue;
    }

    if (
      from === tableKey(outer) &&
      to === tableKey(table) &&
      (inner.method === "get" || filters(relation.referenced_columns[0]))
    ) {
      const found = { name: name(column.replace(/_id$/, "")), many: false };

      if (named(column)) {
        return found;
      }

      candidates.push(found);
    }

    if (from === tableKey(table) && to === tableKey(outer) && filters(column)) {
      candidates.push({ name: name(relation.relation), many: true });
    }
  }

  return candidates[0];
}

/** `include: { quote: true }`, or `_count` for a count of related rows. */
function includeOf(relation: Relation, read: Read): string {
  return relation.many && read.method === "count"
    ? `include: { _count: { ${relation.name}: true } }`
    : `include: { ${relation.name}: true }`;
}

function batchHint(read: Read): string {
  switch (read.kind) {
    case "table": {
      return `Read them in one request with an \`in\` filter, such as \`${read.call.replace(/\.(?:get|first|find\w*)$/, ".list")}({ where: { id: { in: ids } } })\`, and group the rows by key.`;
    }

    case "rpc": {
      return "Give the function an array parameter (`uuid[]`) and call it once for every id, or add it to a read set.";
    }

    case "other": {
      return "Add a batched variant that takes every id and reads them with one `in` filter, then call it once outside the loop.";
    }

    default: {
      const kind: never = read.kind;

      return kind;
    }
  }
}

interface FileAnalysis {
  readonly perItem: FindingInput[];
  readonly waterfalls: FindingInput[];
}

/** `in: ids` or `in: [...ids]`: the read is already batched over `name`. */
const batchedOver = (args: string, name: string): boolean =>
  new RegExp(
    String.raw`\bin\s*:\s*(?:\[\s*\.\.\.)?${name.replaceAll("$", String.raw`\$`)}\b`,
  ).test(args);

/**
 * A scope that iterates a literal array (`for (const kind of ["a", "b"])`) runs
 * a fixed number of times; a batch, a retry or a loop that writes per item is
 * not a read pattern to fold into one request.
 */
function skipScope(scope: Scope, writes: readonly number[]): boolean {
  return (
    BATCHES.test(scope.items) ||
    (scope.items.startsWith("[") && !scope.items.includes("...")) ||
    writes.some((at) => at >= scope.start && at < scope.end)
  );
}

/** Both checks share one pass over each file. */
function analyze(file: TextFile, snapshot: Snapshot): FileAnalysis {
  const perItem: FindingInput[] = [];
  const waterfalls: FindingInput[] = [];

  if (!/\bdb\b|\$rpc|supabase|Db\b|blocks|Service/.test(file.text)) {
    return { perItem, waterfalls };
  }

  const code = codeOnly(file.text);
  const services = serviceNames(code);
  const reads = readsIn(file.text, code, services);

  if (reads.length === 0) {
    return { perItem, waterfalls };
  }

  const writes = writesIn(file.text, code, services);

  const rawArgs = (read: Read): string =>
    file.text.slice(read.open + 1, read.close);

  const lineAt = lines(file.text);
  const origins = originsIn(file.text, code, reads);
  const reported = new Set<number>();

  for (const scope of scopesIn(code)) {
    if (skipScope(scope, writes)) {
      continue;
    }

    const names = scopeNames(code, scope);

    for (const read of reads) {
      const args = code.slice(read.open + 1, read.close);

      if (
        read.start < scope.start ||
        read.start >= scope.end ||
        reported.has(read.start) ||
        read.method === "page" ||
        !names.some((name) => mentions(args, name)) ||
        names.some((name) => batchedOver(args, name))
      ) {
        continue;
      }

      reported.add(read.start);

      const line = lineAt(read.start);
      const root = /^[\w$]+/.exec(scope.items)?.[0];

      const outer = origins.findLast(
        (origin) =>
          origin.name === root &&
          scope.start >= origin.from &&
          scope.start < origin.to,
      );

      const relation = outer
        ? relationTo(snapshot, outer.table, read, rawArgs(read))
        : undefined;

      const hint =
        outer && relation
          ? `${outer.table} and ${read.table!} are related: add \`${includeOf(relation, read)}\` to ${outer.call} at line ${String(outer.line)} and drop this read.`
          : batchHint(read);

      perItem.push({
        message: `${file.path}:${String(line)} calls ${read.call} once per item of \`${scope.items}\`, so n items make n requests (N+1). ${hint}`,
        target: `${file.path}:${String(line)}`,
        location: { file: file.path, line },
      });
    }
  }

  for (const read of reads) {
    if (read.table === undefined || reported.has(read.start)) {
      continue;
    }

    const args = code.slice(read.open + 1, read.close);

    const origin = origins.findLast(
      (candidate) =>
        read.start >= candidate.from &&
        read.start < candidate.to &&
        mentions(args, candidate.name),
    );

    const relation = origin
      ? relationTo(snapshot, origin.table, read, rawArgs(read))
      : undefined;

    if (!origin || !relation) {
      continue;
    }

    const line = lineAt(read.start);

    waterfalls.push({
      message: `${file.path}:${String(line)} waits for ${origin.call} at line ${String(origin.line)}, then reads ${read.call} filtered by its rows (\`${origin.name}\`). The tables are related: add \`${includeOf(relation, read)}\` to the first read so one request returns both.`,
      target: `${file.path}:${String(line)}`,
      location: { file: file.path, line },
    });
  }

  const byLine = (a: FindingInput, b: FindingInput): number =>
    (a.location?.line ?? 0) - (b.location?.line ?? 0);

  return { perItem: perItem.toSorted(byLine), waterfalls };
}

const analyses = new WeakMap<readonly TextFile[], FileAnalysis[]>();

function analyzeAll(context: DoctorContext): FileAnalysis[] {
  let result = analyses.get(context.sources);

  if (!result) {
    result = context.sources.map((file) => analyze(file, context.snapshot));
    analyses.set(context.sources, result);
  }

  return result;
}

export const N_PLUS_ONE_RULES: readonly Rule[] = [
  {
    code: "BS634",
    severity: "warning",
    title: "Database read once per item (N+1)",
    description:
      "A repository read, block call, RPC or supabase-js select inside a `for ... of` loop or a `map`/`flatMap`/`forEach` callback, filtered by the loop variable, makes one request per item. Load the rows with an `include` on the outer read when the tables are related, or with one `in` read outside the loop.",
    check: (context) => analyzeAll(context).flatMap((file) => file.perItem),
  },
  {
    code: "BS635",
    severity: "warning",
    title: "Dependent read of a related table (waterfall)",
    description:
      "An awaited read whose filter uses the rows of an earlier awaited read in the same function, when the two tables have a foreign key between them. The second request waits for the first; an `include` on the first read returns both in one request.",
    check: (context) => analyzeAll(context).flatMap((file) => file.waterfalls),
  },
];
