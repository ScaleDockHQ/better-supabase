import type { Node } from "oxc-parser";

import type { Snapshot } from "../../config/index.ts";
import type { DoctorContext, FindingInput, Rule, TextFile } from "./rules.ts";
import type {
  CallSite,
  Declaration,
  NamedFunction,
  SourceModel,
} from "./source-scan.ts";

import { provablyNotClient } from "./receiver-types.ts";
import {
  bindingNames,
  sourceModel,
  targetKeys,
  unwrap,
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

/** The arguments of a read: their text and each `key: value` inside. */
interface Args {
  readonly text: string;
  readonly props: readonly { readonly key: string; readonly value: string }[];
}

/**
 * A receiver that names the better-supabase client: `db`, `ctx.db`, `tx`,
 * `bsb.db()`.
 */
const DB = String.raw`(?<![\w$])(?:db|[a-z][\w$]*Db|tx|trx)(?:\(\))?`;

/**
 * The callee patterns match the callee path of a call (`db.customers.get`,
 * `supabase.from(...).select`), so only a call can match and a string or a
 * comment never does.
 */
const REPOSITORY_READ = new RegExp(
  String.raw`${DB}\.([A-Za-z_][\w$]*)\.(get|list|page|count|counted|aggregate|first|find[A-Z]?[\w$]*)$`,
);

const BLOCK_CALL = new RegExp(
  String.raw`(?:${DB}\.\$blocks|(?<![\w$])blocks)\.[\w$]+\.([\w$]+)$`,
);

const RPC_CALL = /\.\$(?:rpc|search|run|many)$/i;

const SUPABASE_RPC = /(?<![\w$])[\w$]*supabase[\w$]*\.rpc$/i;

const FROM_CHAIN =
  /\.from\((?:\.\.\.)?\)\.(select|insert|update|upsert|delete)$/;

const SERVICE_READ_NAME =
  /^(?:get|list|load|find|fetch|count|read|search)[A-Z][\w$]*$/;

const SERVICE_NAME =
  /(?:services?|repositor(?:y|ies)|repos?|queries|readers?)$/i;

const SERVICE_FACTORY = /^create[\w$]*(?:Services?|Repositor(?:y|ies)|Repos?)$/;

/** A block method or a local function whose name says it writes. */
const WRITE_NAME =
  /^(?:create|insert|update|upsert|delete|remove|set|add|save|send|enqueue|record|mark|approve|reject|cancel|archive|restore|move|assign|unassign|post|submit|publish|attach|detach|link|unlink|invite|revoke|grant|start|stop|complete|close|open|lock|unlock|apply|import|sync|refresh|recompute|merge|reorder|rename|toggle|track|emit|notify|write|put|patch|claim|release|issue|void|pay|charge|refund|transfer|book|confirm|accept|decline|resolve|reopen|pin|unpin|join|leave|subscribe|unsubscribe|upload|clear|reset|seed|ensure|process|run|execute|handle|dispatch|schedule|retry|replace|increment|decrement|bump|touch|finalize|commit|enable|disable|activate|deactivate|generate|log|accrue|decide|escalate|expire|deliver|broadcast|transition|advance|convert|clone|duplicate|copy|share|sign|invalidate|revalidate)(?:[A-Z_\d]|$)/;

const REPOSITORY_WRITE = new RegExp(
  String.raw`${DB}\.[A-Za-z_][\w$]*\.(?:create|update|upsert|delete)$`,
);

/**
 * A call whose name says it has a side effect, such as `notifyAgendaUpdated(`
 * or `events.publish(`: a loop that makes one per item is not a read pattern.
 */
const SIDE_EFFECT_NAME =
  /^(?:notify|publish|send|emit|enqueue|dispatch|broadcast|deliver|revalidate)(?:[A-Z_][\w$]*)?$/;

/**
 * A helper that runs a callback per item: `mapInChunks(ids, 20, async (id) =>
 * ...)`, `pMap(ids, (id) => ...)`.
 */
const HELPER_NAME = /map|each|chunk|batch|concurren|parallel|limit/i;

/** Filters an `in` list can't batch: text search and JSON containment. */
const SEARCH_FILTERS: ReadonlySet<string> = new Set([
  "contains",
  "containedBy",
  "ilike",
  "iLike",
  "like",
  "startsWith",
  "endsWith",
  "search",
  "q",
  "query",
  "textSearch",
  "match",
  "fts",
]);

const CALLBACK_METHODS: ReadonlySet<string> = new Set([
  "map",
  "flatMap",
  "forEach",
]);

/**
 * Loop variables that are already batches, or retries of one read: `for (const
 * chunk of chunks)`, `for (const attempt of attempts)`. `chunk.map((id) =>
 * ...)` still runs once per item.
 */
const BATCHES = /chunk|batch|attempt|retr/i;

/** Iterables of batches or retries, whatever the loop variable is called. */
const BATCH_ITEMS = /(?:chunks|batches)\b|chunked|attempt|retr/i;

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

/** The last name of `node`: `rows` of `rows`, `items` of `page.items`. */
function lastName(
  node: Node,
): { readonly name: string; readonly start: number } | undefined {
  const inner = unwrap(node);

  if (inner.type === "Identifier") {
    return { name: inner.name, start: inner.start };
  }

  return inner.type === "MemberExpression" &&
    !inner.computed &&
    inner.property.type === "Identifier"
    ? { name: inner.property.name, start: inner.property.start }
    : undefined;
}

/** The method call `receiver.method(...)` of `call`, with what it names. */
function methodCall(
  call: CallSite,
):
  | {
      readonly method: { readonly name: string; readonly start: number };
      readonly receiver?: { readonly name: string; readonly start: number };
      readonly owner?: string;
    }
  | undefined {
  const callee = unwrap(call.node.callee);

  if (
    callee.type !== "MemberExpression" ||
    callee.computed ||
    callee.property.type !== "Identifier"
  ) {
    return undefined;
  }

  const object = unwrap(callee.object);
  const receiver = lastName(object);

  const owner =
    object.type === "MemberExpression"
      ? lastName(object.object)?.name
      : undefined;

  return {
    method: { name: callee.property.name, start: callee.property.start },
    ...(receiver === undefined ? {} : { receiver }),
    ...(owner === undefined ? {} : { owner }),
  };
}

/** The offset of the `.` before the name at path index `index`. */
function dotBefore(model: SourceModel, call: CallSite, index: number): number {
  return model.text.lastIndexOf(".", call.names.get(index) ?? call.start);
}

/** The table `supabase.from("customers")` names, when it names one. */
function fromTable(call: CallSite): string | undefined {
  const select = unwrap(call.node.callee);

  if (select.type !== "MemberExpression") {
    return undefined;
  }

  const from = unwrap(select.object);
  const [argument] = from.type === "CallExpression" ? from.arguments : [];

  const name =
    argument?.type === "Literal" && typeof argument.value === "string"
      ? argument.value
      : argument?.type === "TemplateLiteral" &&
          argument.expressions.length === 0
        ? argument.quasis[0]?.value.cooked
        : undefined;

  return typeof name === "string" && /^[\w.]+$/.test(name)
    ? name.split(".").at(-1)
    : undefined;
}

const isService = (receiver: string, services: ReadonlySet<string>): boolean =>
  services.has(receiver) || SERVICE_NAME.test(receiver);

/** Names bound to the result of a `create...Service(...)` factory. */
function serviceNames(model: SourceModel): Set<string> {
  const services = new Set<string>(model.typedServices);

  for (const declaration of model.declarations) {
    const init = unwrap(declaration.init);

    if (
      init.type === "CallExpression" &&
      init.callee.type === "Identifier" &&
      SERVICE_FACTORY.test(init.callee.name)
    ) {
      for (const name of declaration.names) {
        services.add(name);
      }
    }
  }

  return services;
}

/** The offsets of calls that write, and those that write through a repository. */
interface Writes {
  readonly all: readonly number[];
  readonly repository: readonly number[];
}

/**
 * Offsets of calls that write: repository and supabase-js writes, RPCs, block
 * methods and service methods named for a write (`services.agenda.assignTask`
 * too), and calls named for a side effect such as `notify...` or `publish...`.
 */
function writesIn(model: SourceModel, services: ReadonlySet<string>): Writes {
  const all: number[] = [];
  const repository: number[] = [];

  for (const call of model.calls) {
    const { path } = call;
    const method = methodCall(call);

    if (path !== undefined) {
      const write = REPOSITORY_WRITE.exec(path);
      const from = FROM_CHAIN.exec(path);
      const rpc = RPC_CALL.exec(path);
      const supabase = SUPABASE_RPC.exec(path);
      const block = BLOCK_CALL.exec(path);

      if (write) {
        const start = call.names.get(write.index) ?? call.start;

        repository.push(start);
        all.push(start);
      }

      if (from && from[1] !== "select") {
        const start = dotBefore(model, call, from.index + 1);

        repository.push(start);
        all.push(start);
      }

      if (rpc || supabase) {
        const name = rpcName(model.text, call.open);

        if (name !== undefined && WRITE_NAME.test(camel(name))) {
          all.push(
            rpc
              ? dotBefore(model, call, rpc.index + 1)
              : (call.names.get(supabase!.index) ?? call.start),
          );
        }
      }

      if (block && WRITE_NAME.test(block[1]!)) {
        all.push(call.names.get(block.index) ?? call.start);
      }
    }

    if (
      method?.receiver &&
      /^[a-z]/.test(method.method.name) &&
      WRITE_NAME.test(method.method.name) &&
      (isService(method.receiver.name, services) ||
        (method.owner !== undefined && isService(method.owner, services)))
    ) {
      all.push(method.receiver.start);
    }

    const callee = unwrap(call.node.callee);

    const effect =
      callee.type === "Identifier"
        ? { name: callee.name, start: callee.start }
        : method?.method;

    if (effect && SIDE_EFFECT_NAME.test(effect.name)) {
      all.push(effect.start);
    }
  }

  return { all, repository };
}

/** Reads by the database client itself, before following local functions. */
function directReads(model: SourceModel): Read[] {
  const { text } = model;
  const reads: Read[] = [];

  const add = (
    call: CallSite,
    start: number,
    kind: Read["kind"],
    table?: string,
    method?: string,
  ): void => {
    let name = compact(text.slice(start, call.open));

    if (kind === "rpc") {
      const rpc = rpcName(text, call.open);

      if (rpc !== undefined && WRITE_NAME.test(camel(rpc))) {
        return;
      }

      name = rpc === undefined ? name : `${name}("${rpc}")`;
    }

    reads.push({
      start,
      open: call.open,
      close:
        kind === "table" && method === undefined ? call.chainClose : call.close,
      call: name,
      callee: name,
      kind,
      ...(table === undefined ? {} : { table }),
      ...(method === undefined ? {} : { method }),
    });
  };

  const paths = model.calls.filter(
    (call): call is CallSite & { path: string } => call.path !== undefined,
  );

  for (const call of paths) {
    const match = REPOSITORY_READ.exec(call.path);

    if (match) {
      add(
        call,
        call.names.get(match.index) ?? call.start,
        "table",
        match[1],
        match[2],
      );
    }
  }

  for (const call of paths) {
    const match = BLOCK_CALL.exec(call.path);

    if (match && !WRITE_NAME.test(match[1]!)) {
      add(call, call.names.get(match.index) ?? call.start, "other");
    }
  }

  for (const call of paths) {
    const rpc = RPC_CALL.exec(call.path);
    const supabase = SUPABASE_RPC.exec(call.path);

    if (rpc) {
      add(call, dotBefore(model, call, rpc.index + 1), "rpc");
    } else if (supabase) {
      add(call, call.names.get(supabase.index) ?? call.start, "rpc");
    }
  }

  for (const call of paths) {
    const match = FROM_CHAIN.exec(call.path);

    if (match?.[1] === "select") {
      add(
        call,
        dotBefore(model, call, match.index + 1),
        "table",
        fromTable(call),
      );
    }
  }

  return reads;
}

/** The calls in `model` to the local function `name`. */
function callsTo(model: SourceModel, name: string): CallSite[] {
  return model.calls.filter(
    (call) =>
      call.node.callee.type === "Identifier" && call.node.callee.name === name,
  );
}

/**
 * Local functions that read and never write, followed through each other within
 * the file, mapped to the read they make.
 */
function readerFunctions(
  model: SourceModel,
  direct: readonly Read[],
  writes: Writes,
): Map<string, Read> {
  const bodies = new Map<string, NamedFunction>();

  for (const fn of model.functions) {
    if (fn.local === true && !WRITE_NAME.test(fn.name)) {
      bodies.set(fn.name, fn);
    }
  }

  const inside = (at: number, body: NamedFunction): boolean =>
    at >= body.start && at < body.end;

  const writesIn = (body: NamedFunction): boolean =>
    writes.repository.some((at) => inside(at, body));

  const readers = new Map<string, Read>();

  for (const [name, body] of bodies) {
    const read = direct.find((candidate) => inside(candidate.start, body));

    if (read !== undefined && !writesIn(body)) {
      readers.set(name, read);
    }
  }

  let grew = true;

  while (grew) {
    grew = false;

    for (const [name, body] of bodies) {
      if (readers.has(name) || writesIn(body)) {
        continue;
      }

      for (const [reader, read] of readers) {
        if (
          reader !== name &&
          callsTo(model, reader).some((call) => inside(call.start, body))
        ) {
          readers.set(name, read);
          grew = true;
          break;
        }
      }
    }
  }

  return readers;
}

/** Every read in the file, including calls to readers and service reads. */
function readsIn(
  model: SourceModel,
  services: ReadonlySet<string>,
  writes: Writes,
): Read[] {
  const direct = directReads(model);
  const reads = [...direct];

  for (const [name, read] of readerFunctions(model, direct, writes)) {
    for (const call of callsTo(model, name)) {
      reads.push({
        start: call.start,
        open: call.open,
        close: call.close,
        call: `${name} (which calls ${read.call})`,
        callee: name,
        kind: "other",
      });
    }
  }

  for (const call of model.calls) {
    const method = methodCall(call);

    if (
      method?.receiver &&
      SERVICE_READ_NAME.test(method.method.name) &&
      isService(method.receiver.name, services)
    ) {
      const name = `${method.receiver.name}.${method.method.name}`;

      reads.push({
        start: method.receiver.start,
        open: call.open,
        close: call.close,
        call: name,
        callee: name,
        kind: "other",
      });
    }
  }

  return reads.toSorted((a, b) => a.start - b.start);
}

const isFunction = (
  node: Node | undefined,
): node is Node & { type: "ArrowFunctionExpression" | "FunctionExpression" } =>
  node?.type === "ArrowFunctionExpression" ||
  node?.type === "FunctionExpression";

/** `for (... of ...)` bodies, `.map/.flatMap/.forEach` callbacks and helpers. */
function scopesIn(model: SourceModel): Scope[] {
  const { text } = model;
  const scopes: Scope[] = [];
  const source = (node: Node): string => text.slice(node.start, node.end);

  for (const loop of model.loops) {
    const [declaration] =
      loop.left.type === "VariableDeclaration" ? loop.left.declarations : [];

    if (declaration) {
      scopes.push({
        start: loop.body.start,
        end: loop.body.end,
        items: compact(source(loop.right)),
        names: bindingNames(declaration.id),
      });
    }
  }

  for (const call of model.calls) {
    const [first] = call.node.arguments;
    const method = methodCall(call);
    const callee = unwrap(call.node.callee);

    if (
      method &&
      CALLBACK_METHODS.has(method.method.name) &&
      callee.type === "MemberExpression" &&
      isFunction(first) &&
      first.body
    ) {
      scopes.push({
        start: first.body.start,
        end: call.close,
        items: compact(source(callee.object)).replace(/^\.\.\./, ""),
        names: first.params.flatMap((param) => bindingNames(param)),
      });
    }

    if (
      callee.type === "Identifier" &&
      HELPER_NAME.test(callee.name) &&
      first !== undefined
    ) {
      const callback = call.node.arguments
        .slice(1)
        .find((item) => isFunction(item));

      if (isFunction(callback) && callback.body) {
        scopes.push({
          start: callback.body.start,
          end: callback.end,
          items: compact(source(first)),
          names: callback.params.flatMap((param) => bindingNames(param)),
        });
      }
    }
  }

  return scopes.toSorted((a, b) => a.end - a.start - (b.end - b.start));
}

/** Names in `scope` that hold the loop variable, or something derived from it. */
function scopeNames(model: SourceModel, scope: Scope): string[] {
  const names = [...scope.names];

  for (const declaration of model.declarations) {
    if (declaration.start < scope.start || declaration.start >= scope.end) {
      continue;
    }

    const init = model.code.slice(declaration.init.start, declaration.init.end);

    if (names.some((name) => mentions(init, name))) {
      names.push(...declaration.names);
    }
  }

  return names;
}

/** Variables that hold rows of an earlier awaited table read, and their scope. */
function originsIn(
  model: SourceModel,
  reads: readonly Read[],
  lineAt: (index: number) => number,
): Origin[] {
  const origins: Origin[] = [];

  const push = (
    declaration: Declaration,
    name: string,
    read: Read & { readonly table: string },
  ): void => {
    origins.push({
      name,
      table: read.table,
      call: read.call,
      line: lineAt(read.start),
      from: declaration.init.end,
      to: declaration.scopeEnd,
    });
  };

  for (const declaration of model.declarations) {
    const { init, pattern } = declaration;
    const initCode = model.code.slice(init.start, init.end);

    const inside = reads.filter(
      (read) => read.start >= init.start && read.start < init.end,
    );

    if (init.type === "AwaitExpression" && inside.length > 0) {
      const call = init.argument;

      const [list] = call.type === "CallExpression" ? call.arguments : [];

      if (
        call.type === "CallExpression" &&
        list?.type === "ArrayExpression" &&
        pattern.type === "ArrayPattern" &&
        model.text
          .slice(call.callee.start, call.callee.end)
          .replaceAll(/\s/g, "") === "Promise.all"
      ) {
        for (const [index, entry] of list.elements.entries()) {
          const read = entry
            ? inside.find(
                (candidate) =>
                  candidate.start >= entry.start && candidate.start < entry.end,
              )
            : undefined;

          const name = bindingNames(pattern.elements[index])[0];

          if (read?.table !== undefined && name !== undefined) {
            push(declaration, name, { ...read, table: read.table });
          }
        }

        continue;
      }

      const [read] = inside;

      if (read?.table !== undefined) {
        for (const name of declaration.names) {
          push(declaration, name, { ...read, table: read.table });
        }
      }

      continue;
    }

    const source = origins.findLast(
      (origin) =>
        declaration.start >= origin.from &&
        declaration.start < origin.to &&
        mentions(initCode, origin.name),
    );

    if (source) {
      for (const name of declaration.names) {
        origins.push({
          ...source,
          name,
          from: init.end,
          to: declaration.scopeEnd,
        });
      }
    }
  }

  return origins;
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
/**
 * The relationships with no view on either side. A view's relationships carry
 * none of gen's `relations`, so an include on it would not compile. Views match
 * by name, since a repository names no schema: `db.memberships` over a
 * `public.memberships` view of `better_supabase.memberships` reads the view.
 */
function tableRelationships(
  snapshot: Snapshot,
): Snapshot["generator"]["relationships"] {
  const views = new Set(
    [...snapshot.generator.views, ...snapshot.generator.materializedViews].map(
      (view) => tableKey(view.name),
    ),
  );

  return snapshot.generator.relationships.filter(
    (relation) =>
      !views.has(tableKey(relation.relation)) &&
      !views.has(tableKey(relation.referenced_relation)),
  );
}

function relationTo(
  snapshot: Snapshot,
  outer: string,
  inner: Read,
  args: Args,
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
    ).test(args.text);

  const candidates: Relation[] = [];

  const named = (column: string): boolean =>
    new RegExp(
      String.raw`(?<![\w$])(?:${column}|${camel(column)})(?![\w$])`,
    ).test(args.text);

  for (const relation of tableRelationships(snapshot)) {
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
  args: Args,
  via: string,
  name: (raw: string) => string,
): Relation | undefined {
  const relationships = tableRelationships(snapshot);

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
function filterMentions(args: Args, column: string, name: string): boolean {
  return args.props.some(
    (prop) =>
      (prop.key === column || prop.key === camel(column)) &&
      mentions(prop.value, name),
  );
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
  model: SourceModel,
  read: Read,
  names: readonly string[],
): { readonly kind: "search" | "json"; readonly name: string } | undefined {
  const candidates: { start: number; key: string; value: string }[] = [];

  for (const prop of model.properties) {
    if (
      prop.start > read.open &&
      prop.valueEnd <= read.close &&
      SEARCH_FILTERS.has(prop.key)
    ) {
      candidates.push({
        start: prop.start,
        key: prop.key,
        value: model.code.slice(prop.valueStart, prop.valueEnd),
      });
    }
  }

  for (const call of model.calls) {
    const callee = unwrap(call.node.callee);

    const named =
      callee.type === "Identifier"
        ? callee
        : callee.type === "MemberExpression" &&
            callee.property.type === "Identifier"
          ? callee.property
          : undefined;

    const key = named?.name;

    if (
      key !== undefined &&
      SEARCH_FILTERS.has(key) &&
      named !== undefined &&
      named.start > read.open &&
      named.start < read.close
    ) {
      candidates.push({
        start: named.start,
        key,
        value: model.code.slice(call.open + 1, call.close),
      });
    }
  }

  for (const { key, value } of candidates.toSorted(
    (a, b) => a.start - b.start,
  )) {
    const name = names.find((candidate) => mentions(value, candidate));

    if (name !== undefined) {
      const json = key.startsWith("contain") && /^\s*[[{]/.test(value);

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
function analyze(
  file: TextFile,
  snapshot: Snapshot,
  symbols: DoctorContext["symbols"],
): FileAnalysis {
  const perItem: FindingInput[] = [];
  const waterfalls: FindingInput[] = [];

  if (!/\bdb\b|\$rpc|supabase|Db\b|blocks|Service/.test(file.text)) {
    return { perItem, waterfalls };
  }

  const model = sourceModel(file.text);
  const { code } = model;
  const services = serviceNames(model);
  const writes = writesIn(model, services);

  const reads = readsIn(model, services, writes).filter(
    (read) => provablyNotClient(symbols, file.path, read.start) !== true,
  );

  if (reads.length === 0) {
    return { perItem, waterfalls };
  }

  const argsOf = (read: Read): Args => ({
    text: file.text.slice(read.open + 1, read.close),
    props: model.properties
      .filter((prop) => prop.start > read.open && prop.valueEnd <= read.close)
      .map((prop) => ({
        key: prop.key,
        value: code.slice(prop.valueStart, prop.valueEnd),
      })),
  });

  const lineAt = lines(file.text);
  const origins = originsIn(model, reads, lineAt);
  const reported = new Set<number>();
  let keys: Map<number, string> | undefined;

  const targetOf = (read: Read): string => {
    keys ??= targetKeys(file.path, model.functions, reads);

    return keys.get(read.start)!;
  };

  for (const scope of scopesIn(model)) {
    if (skipScope(scope, writes.all)) {
      continue;
    }

    const names = scopeNames(model, scope);

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
        ? relationTo(snapshot, outer.table, read, argsOf(read))
        : undefined;

      const search = searchMatch(model, read, names);

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

  const waves = model.calls.flatMap((call): [number, number][] => {
    const [list] = call.node.arguments;

    return call.path === "Promise.all" && list?.type === "ArrayExpression"
      ? [[list.start, list.end - 1]]
      : [];
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
      ? relationTo(snapshot, origin.table, read, argsOf(read), origin.name)
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
    result = context.sources.map((file) =>
      analyze(file, context.snapshot, context.symbols),
    );
    analyses.set(context.sources, result);
  }

  return result;
}

/**
 * Checks that read only source files. Without a database or a snapshot they
 * still run; BS634 and BS635 then lack the foreign keys that name includes.
 */
export const SOURCE_ONLY_CODES: ReadonlySet<string> = new Set([
  "BS513",
  "BS514",
  "BS515",
  "BS609",
  "BS634",
  "BS635",
]);

/** The snapshot of a run that could not read one: no tables, no foreign keys. */
export const NO_SNAPSHOT: Snapshot = {
  version: 3,
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
