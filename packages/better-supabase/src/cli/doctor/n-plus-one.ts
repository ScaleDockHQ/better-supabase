import type { Snapshot } from "../../config/index.ts";
import type { DoctorContext, FindingInput, Rule, TextFile } from "./rules.ts";

import {
  CLOSE,
  closeOf,
  codeOnly,
  functionsIn,
  OPEN,
  statementEnd,
  targetKeys,
} from "./source-scan.ts";

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
  /** What the target key names: the call, or the local reader's name. */
  readonly callee: string;
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
  /** The to-one include on the outer table that the relation hangs from. */
  readonly through?: string;
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
  /^(?:create|insert|update|upsert|delete|remove|set|add|save|send|enqueue|record|mark|approve|reject|cancel|archive|restore|move|assign|unassign|post|submit|publish|attach|detach|link|unlink|invite|revoke|grant|start|stop|complete|close|open|lock|unlock|apply|import|sync|refresh|recompute|merge|reorder|rename|toggle|track|emit|notify|write|put|patch|claim|release|issue|void|pay|charge|refund|transfer|book|confirm|accept|decline|resolve|reopen|pin|unpin|join|leave|subscribe|unsubscribe|upload|clear|reset|seed|ensure|process|run|execute|handle|dispatch|schedule|retry|replace|increment|decrement|bump|touch|finalize|commit|enable|disable|activate|deactivate|generate|log|accrue|decide|escalate|expire|deliver|broadcast|transition|advance|convert|clone|duplicate|copy|share|sign|invalidate|revalidate)(?:[A-Z_\d]|$)/;

const REPOSITORY_WRITE = new RegExp(
  String.raw`${DB}\s*\.\s*[A-Za-z_][\w$]*\s*\.\s*(?:create|update|upsert|delete)\s*\(|\.\s*from\s*\([\w$.\s]*\)\s*\.\s*(?:insert|update|upsert|delete)\s*\(`,
);

/**
 * A call whose name says it has a side effect, such as `notifyAgendaUpdated(`
 * or `events.publish(`: a loop that makes one per item is not a read pattern.
 */
const SIDE_EFFECT_CALL =
  /(?<![\w$])(?:notify|publish|send|emit|enqueue|dispatch|broadcast|deliver|revalidate)(?:[A-Z_][\w$]*)?\s*\(/g;

/** A parameter or field typed as a service: `customers: CustomersService`. */
const SERVICE_TYPED =
  /(?<![\w$.])([\w$]+)\s*\??\s*:\s*(?:Readonly<\s*)?[\w$.]*(?:Services?|Repositor(?:y|ies)|Repos?|Queries)\b(?!\s*[<[.])/g;

/**
 * A helper that runs a callback per item: `mapInChunks(ids, 20, async (id) =>
 * ...)`, `pMap(ids, (id) => ...)`.
 */
const HELPER_CALL =
  /(?<![\w$.])(?<!new\s+)([A-Za-z_$][\w$]*)\s*(?:<[^>()]*>)?\s*\(/g;

const HELPER_NAME = /map|each|chunk|batch|concurren|parallel|limit/i;

/** Filters an `in` list can't batch: text search and JSON containment. */
const SEARCH_FILTER =
  /(?<![\w$])(contains|containedBy|ilike|iLike|like|startsWith|endsWith|search|q|query|textSearch|match|fts)\s*([:(])/g;

const LOCAL_FUNCTION =
  /(?:function\s*\*?\s*([\w$]+)\s*(?:<[^>]*>)?\s*\(|(?:const|let)\s+([\w$]+)\s*(?::[^=]+)?=\s*(?:async\s+)?(?:function\b[^(]*\(|\(|[\w$]+\s*=>))/g;

const WAVE = /\bPromise\.all\s*\(\s*\[/g;

const LOOP = /(?<![\w$.])for\s*(?:await\s*)?\(/g;

const CALLBACK = /\.\s*(?:map|flatMap|forEach)\s*\(/g;

const DECLARATION =
  /(?<![\w$.])(?:const|let|var)\s+([\w$]+|\{[^=;]*?\}|\[[^=;]*?\])\s*(?::[^=;]+)?=(?!=|>)/g;

/**
 * Loop variables that are already batches, or retries of one read: `for (const
 * chunk of chunks)`, `for (const attempt of attempts)`. `chunk.map((id) =>
 * ...)` still runs once per item.
 */
const BATCHES = /chunk|batch|attempt|retr/i;

/** Iterables of batches or retries, whatever the loop variable is called. */
const BATCH_ITEMS = /(?:chunks|batches)\b|chunked|attempt|retr/i;

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
 * methods and service methods named for a write (`services.agenda.assignTask`
 * too), and calls named for a side effect such as `notify...` or `publish...`.
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
    const owner = /([\w$]+)\s*\.\s*$/.exec(
      code.slice(Math.max(0, match.index - 200), match.index),
    )?.[1];

    if (
      (isService(match[1]!, services) ||
        (owner !== undefined && isService(owner, services))) &&
      WRITE_NAME.test(match[2]!)
    ) {
      writes.push(match.index);
    }
  }

  for (const match of code.matchAll(SIDE_EFFECT_CALL)) {
    writes.push(match.index);
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
      callee: call,
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

  for (const match of code.matchAll(SERVICE_TYPED)) {
    services.add(match[1]!);
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
        callee: name,
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
      callee: `${receiver}.${match[2]!}`,
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
    const callback = callbackAt(code, open + 1, close);

    if (callback) {
      scopes.push({
        ...callback,
        items: compact(receiverBefore(code, match.index)),
      });
    }
  }

  for (const match of code.matchAll(HELPER_CALL)) {
    const name = match[1]!;

    if (
      !HELPER_NAME.test(name) ||
      /^(?:Map|WeakMap|function)$/.test(name) ||
      /(?:function\s*\*?\s*|async\s+)$/.test(
        code.slice(Math.max(0, match.index - 40), match.index),
      )
    ) {
      continue;
    }

    const open = match.index + match[0].length - 1;
    const close = closeOf(code, open);
    const args = splitTop(code.slice(open + 1, close));
    let from = open + 1 + args[0]!.length + 1;

    for (const arg of args.slice(1)) {
      const callback = callbackAt(code, from, from + arg.length);

      if (callback) {
        scopes.push({ ...callback, items: compact(args[0]!) });
        break;
      }

      from += arg.length + 1;
    }
  }

  return scopes.toSorted((a, b) => a.end - a.start - (b.end - b.start));
}

/**
 * The parameters and body of a function written at `from` (`async (a, b) =>
 * ...`, `x => ...`, `function (x) {...}`), ending at `end`.
 */
function callbackAt(
  code: string,
  from: number,
  end: number,
): Pick<Scope, "start" | "end" | "names"> | undefined {
  const callback =
    /^\s*(?:async\s+)?(?:function\s*[\w$]*\s*\(|\(|([\w$]+)\s*=>)/.exec(
      code.slice(from, end),
    );

  if (!callback) {
    return undefined;
  }

  if (callback[1] !== undefined) {
    return { start: from + callback[0].length, end, names: [callback[1]] };
  }

  const params = from + callback[0].length - 1;
  const paramsEnd = closeOf(code, params);

  if (
    !callback[0].includes("function") &&
    !/^\s*(?::[^=;{]+)?=>/.test(code.slice(paramsEnd + 1, end))
  ) {
    return undefined;
  }

  return {
    start: paramsEnd + 1,
    end,
    names: parameterNames(code.slice(params + 1, paramsEnd)),
  };
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
  via?: string,
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

  if (candidates.length > 0 || via === undefined) {
    return candidates[0];
  }

  return throughRelation(snapshot, outer, table, args, via, name);
}

/**
 * Two tables that both reference a third, such as `quote_tasks` and
 * `invoice_tasks` through `tasks`, when the inner read filters its key column
 * by the outer rows (`taskId: { in: taskIds }`): `include: { task: { include: {
 * invoiceTasks: true } } }` on the outer read.
 */
function throughRelation(
  snapshot: Snapshot,
  outer: string,
  inner: string,
  args: string,
  via: string,
  name: (raw: string) => string,
): Relation | undefined {
  const relationships = snapshot.generator.relationships;

  // Columns that ride along in composite foreign keys, such as a tenant column:
  // every row of a tenant shares them, so they link no particular rows.
  const shared = new Set(
    relationships.flatMap((relation) => relation.columns.slice(1)),
  );

  for (const hop of relationships) {
    const [hopColumn] = hop.columns;
    const middle = tableKey(hop.referenced_relation);

    // An include can't pass through a table of another schema, such as auth.users.
    if (
      hopColumn === undefined ||
      shared.has(hopColumn) ||
      hop.referenced_schema !== hop.schema ||
      tableKey(hop.relation) !== tableKey(outer) ||
      middle === tableKey(inner) ||
      middle === tableKey(outer)
    ) {
      continue;
    }

    for (const back of relationships) {
      const [column] = back.columns;

      if (
        column !== undefined &&
        back.schema === hop.schema &&
        back.referenced_schema === hop.schema &&
        tableKey(back.relation) === tableKey(inner) &&
        tableKey(back.referenced_relation) === middle &&
        back.referenced_columns[0] === hop.referenced_columns[0] &&
        filterMentions(args, column, via)
      ) {
        return {
          name: name(back.relation),
          many: true,
          through: name(hopColumn.replace(/_id$/, "")),
        };
      }
    }
  }

  return undefined;
}

/** Whether the filter on `column` (`taskId: { in: taskIds }`) uses `name`. */
function filterMentions(args: string, column: string, name: string): boolean {
  const key = new RegExp(
    String.raw`(?<![\w$])(?:${column}|${camel(column)})\s*:`,
    "g",
  );

  for (const match of args.matchAll(key)) {
    const from = match.index + match[0].length;

    if (mentions(args.slice(from, statementEnd(args, from)), name)) {
      return true;
    }
  }

  return false;
}

/** `include: { quote: true }`, or `_count` for a count of related rows. */
function includeOf(relation: Relation, read: Read): string {
  const inner =
    relation.many && read.method === "count"
      ? `include: { _count: { ${relation.name}: true } }`
      : `include: { ${relation.name}: true }`;

  return relation.through === undefined
    ? inner
    : `include: { ${relation.through}: { ${inner} } }`;
}

/**
 * How the read matches the loop variable when an `in` list can't: a text search
 * (`contains: term`, `q: term`, `.ilike(...)`) or JSON containment (`contains:
 * { nodes: [{ id }] }`).
 */
function searchMatch(
  args: string,
  names: readonly string[],
): { readonly kind: "search" | "json"; readonly name: string } | undefined {
  for (const match of args.matchAll(SEARCH_FILTER)) {
    const from = match.index + match[0].length;

    const value =
      match[2] === "("
        ? args.slice(from, closeOf(args, from - 1))
        : args.slice(from, statementEnd(args, from));

    const name = names.find((candidate) => mentions(value, candidate));

    if (name !== undefined) {
      const json = match[1]!.startsWith("contain") && /^\s*[[{]/.test(value);

      return { kind: json ? "json" : "search", name };
    }
  }

  return undefined;
}

function searchHint(
  match: NonNullable<ReturnType<typeof searchMatch>>,
): string {
  return match.kind === "json"
    ? `The read matches \`${match.name}\` inside a JSON column with \`contains\`, which an \`in\` filter can't do. Fold the values into one read with an \`OR\` of the \`contains\` conditions, or call an RPC that takes them as an array and matches with \`@> any (...)\`. When neither fits, accept the finding in the baseline.`
    : `\`${match.name}\` is a search term, and an \`in\` filter only matches whole values. Fold the terms into one read with an \`OR\` of the conditions (\`where: { OR: terms.map((term) => ({ name: { contains: term } })) }\`), or call an RPC that takes the terms as \`text[]\` and matches with \`ilike any (...)\`. When each term needs its own limit or ranking, no batched form applies: accept the finding in the baseline.`;
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
    scope.names.some((name) => BATCHES.test(name)) ||
    BATCH_ITEMS.test(scope.items) ||
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
  let keys: Map<number, string> | undefined;

  const targetOf = (read: Read): string => {
    keys ??= targetKeys(file.path, functionsIn(code), reads);

    return keys.get(read.start)!;
  };

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

      const search = searchMatch(args, names);

      const hint =
        outer && relation
          ? `${outer.table} and ${read.table!} are related: add \`${includeOf(relation, read)}\` to ${outer.call} at line ${String(outer.line)} and drop this read.`
          : search
            ? searchHint(search)
            : batchHint(read);

      perItem.push({
        message: `${file.path}:${String(line)} calls ${read.call} once per item of \`${scope.items}\`, so n items make n requests (N+1). ${hint}`,
        target: targetOf(read),
        location: { file: file.path, line },
      });
    }
  }

  const waves = [...code.matchAll(WAVE)].map((match): [number, number] => {
    const open = match.index + match[0].length - 1;

    return [open, closeOf(code, open)];
  });

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
      ? relationTo(snapshot, origin.table, read, rawArgs(read), origin.name)
      : undefined;

    if (!origin || !relation) {
      continue;
    }

    const line = lineAt(read.start);
    const include = `\`${includeOf(relation, read)}\``;

    const wave = waves.find(
      ([open, close]) => read.start > open && read.start < close,
    );

    const sameWave =
      wave !== undefined &&
      reads.some(
        (other) =>
          other !== read &&
          other.start > wave[0] &&
          other.start < wave[1] &&
          (other.start > read.close || other.close < read.start) &&
          mentions(code.slice(other.open + 1, other.close), origin.name),
      );

    waterfalls.push({
      message: sameWave
        ? `${file.path}:${String(line)} reads ${read.call} filtered by the rows of ${origin.call} at line ${String(origin.line)} (\`${origin.name}\`), in one Promise.all with other reads that wait for the same rows. An include saves a request, not a wait: add ${include} to the first read to drop this one.`
        : `${file.path}:${String(line)} waits for ${origin.call} at line ${String(origin.line)}, then reads ${read.call} filtered by its rows (\`${origin.name}\`). The tables are related: add ${include} to the first read so one request returns both.`,
      target: targetOf(read),
      location: { file: file.path, line },
      ...(sameWave ? { severity: "info" as const } : {}),
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

/**
 * Checks that read only source files. Without a database or a snapshot they
 * still run; BS634 and BS635 then lack the foreign keys that name includes.
 */
export const SOURCE_ONLY_CODES: ReadonlySet<string> = new Set([
  "BS609",
  "BS634",
  "BS635",
]);

/** The snapshot of a run that could not read one: no tables, no foreign keys. */
export const NO_SNAPSHOT: Snapshot = {
  version: 2,
  schemas: [],
  generator: {
    version: 1,
    schemas: [],
    tables: [],
    foreignTables: [],
    views: [],
    materializedViews: [],
    columns: [],
    primaryKeys: [],
    relationships: [],
    functions: [],
    types: [],
  },
  extras: { tables: [], buckets: [], realtime: [] },
};

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
