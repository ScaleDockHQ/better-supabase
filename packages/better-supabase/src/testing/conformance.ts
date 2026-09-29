import type { AuthResolver, AuthState } from '../auth/resolve.ts';
import type { CacheAdapter, CacheTarget } from '../core/cache.ts';
import type { BetterSupabase } from '../core/define.ts';
import type { ExecuteContext, Executor } from '../core/executor.ts';
import type { AnyPlugin, HookArgs, RequestContext } from '../core/plugin.ts';
import type { CloudEvent, EventSink } from '../events/index.ts';
import type { Operation } from '../ir/types.ts';
import type { SchemaMeta } from '../schema/types.ts';

import {
  type Generator,
  type GeneratorInput,
  type ResolvedConfig,
  resolveConfig,
} from '../config/index.ts';
import { dbError } from '../core/errors.ts';
import { ok } from '../core/result.ts';
import { toCloudEvents } from '../events/index.ts';

export interface ConformanceCheck {
  readonly name: string;
  readonly ok: boolean;
  readonly message?: string;
}

export interface ConformanceReport {
  /** `Executor "postgrest"`, `CacheAdapter "next"`, ... */
  readonly subject: string;
  readonly checks: readonly ConformanceCheck[];
}

/** Thrown by a conformance kit when any check fails. Lists every failure, not just the first. */
export class ConformanceError extends Error {
  readonly report: ConformanceReport;

  constructor(report: ConformanceReport) {
    const failed = report.checks.filter((check) => !check.ok);
    super(
      `${report.subject} failed ${failed.length} of ${report.checks.length} conformance checks:\n${failed
        .map((check) => `  - ${check.name}: ${check.message ?? 'failed'}`)
        .join('\n')}`,
    );
    this.name = 'ConformanceError';
    this.report = report;
  }
}

export type Check = readonly [name: string, run: () => void | Promise<void>];

export class Violation extends Error {}

export function expect(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Violation(message);
}

export async function conform(
  subject: string,
  checks: readonly (Check | false | undefined)[],
): Promise<ConformanceReport> {
  const results: ConformanceCheck[] = [];
  for (const entry of checks) {
    if (!entry) continue;
    const [name, run] = entry;
    try {
      await run();
      results.push({ name, ok: true });
    } catch (cause) {
      const message =
        cause instanceof Violation
          ? cause.message
          : `threw ${cause instanceof Error ? `${cause.name}: ${cause.message}` : String(cause)}`;
      results.push({ name, ok: false, message });
    }
  }
  const report = { subject, checks: results };
  if (results.some((check) => !check.ok)) throw new ConformanceError(report);
  return report;
}

function deepFreeze<T>(value: T): T {
  if (typeof value === 'object' && value !== null && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const key of Reflect.ownKeys(value))
      deepFreeze((value as Record<PropertyKey, unknown>)[key]);
  }
  return value;
}

const frozenCopy = <T>(value: T): T => deepFreeze(structuredClone(value));

const same = (a: unknown, b: unknown): boolean =>
  JSON.stringify(a) === JSON.stringify(b);

// oxlint-disable-next-line typescript/no-explicit-any
type AnySupabase = BetterSupabase<any, any, any, any>;
type AnyDb = Record<
  string,
  Record<
    string,
    (
      ...args: unknown[]
    ) => PromiseLike<{ ok: boolean; data?: unknown; error?: unknown }>
  >
>;

const recorder = (ops: Operation[]): Executor => ({
  name: 'recorder',
  execute: (op) => {
    ops.push(op);
    return Promise.resolve(ok({ rows: [], count: 0 }));
  },
});

/** The operation `run` sends to the executor, built by `sb` without touching a database. */
async function captureOp(
  sb: AnySupabase,
  run: (db: AnyDb) => PromiseLike<unknown>,
): Promise<Operation> {
  const ops: Operation[] = [];
  await run(sb.connect(recorder(ops)));
  const [op] = ops;
  if (!op) throw new Error('the repository call did not reach the executor');
  return op;
}

function tableKey(sb: AnySupabase, table: string | undefined): string {
  const key = table ?? Object.keys(sb.meta.tables)[0];
  if (!key || !(key in sb.meta.tables))
    throw new TypeError(`better-supabase: unknown table "${String(key)}"`);
  return key;
}

const hasName = (subject: { readonly name?: unknown }): Check => [
  'has a name',
  () =>
    expect(
      typeof subject.name === 'string' && subject.name.length > 0,
      'name must be a non-empty string',
    ),
];

export interface TestExecutorOptions {
  /** A definition whose schema matches the executor's database. Install no plugins. */
  readonly sb: AnySupabase;
  /** App key of a table with rows the executor can read. Defaults to the first table. */
  readonly table?: string;
  /** A row to insert and delete again, to check writes. Skips write checks when omitted. */
  readonly create?: Readonly<Record<string, unknown>>;
}

/**
 * Proves an `Executor` meets the contract: rows keyed by the selection's
 * aliases, counts, `aborted` errors, failures returned as `Result`s rather
 * than thrown, and (with `create`) a write round trip.
 *
 * ```ts
 * it('conforms', () => testExecutor(myExecutor, { sb, table: 'tags', create: { name: 'x' } }));
 * ```
 */
export function testExecutor(
  executor: Executor,
  options: TestExecutorOptions,
): Promise<ConformanceReport> {
  const { sb } = options;
  const table = tableKey(sb, options.table);
  const context: ExecuteContext = { errorMappers: [] };
  const read = (): Promise<Operation> =>
    captureOp(sb, (db) => db[table]!.findMany!({ limit: 2 }));
  const create = options.create;
  return conform(`Executor "${executor.name}"`, [
    hasName(executor),
    [
      'reads rows keyed by the selection aliases',
      async () => {
        const op = await read();
        const result = await executor.execute(op, context);
        expect(
          result.ok,
          `select failed: ${result.ok ? '' : result.error.message}`,
        );
        expect(Array.isArray(result.data.rows), 'rows must be an array');
        expect(
          result.data.rows.length <= 2,
          `limit 2 returned ${result.data.rows.length} rows`,
        );
        expect(
          result.data.count === null || typeof result.data.count === 'number',
          'count must be a number or null',
        );
        if (op.kind !== 'select') return;
        const aliases = new Set(
          op.selection.columns.map((column) => column.alias),
        );
        for (const row of result.data.rows) {
          const extra = Object.keys(row).filter((key) => !aliases.has(key));
          expect(
            extra.length === 0,
            `rows must use selection aliases; got ${extra.join(', ')}`,
          );
        }
      },
    ],
    [
      'counts rows',
      async () => {
        const op = await captureOp(sb, (db) => db[table]!.count!());
        const result = await executor.execute(op, context);
        expect(
          result.ok,
          `count failed: ${result.ok ? '' : result.error.message}`,
        );
        expect(
          typeof result.data.count === 'number' && result.data.count >= 0,
          'count must be a number',
        );
      },
    ],
    [
      'returns an aborted error for an aborted signal',
      async () => {
        const controller = new AbortController();
        controller.abort();
        const result = await executor.execute(await read(), {
          ...context,
          signal: controller.signal,
        });
        expect(!result.ok, 'an aborted request must fail');
        expect(
          result.error.kind === 'aborted',
          `expected kind "aborted", got "${result.error.kind}"`,
        );
      },
    ],
    [
      'returns failures as results instead of throwing',
      async () => {
        const op = await read();
        const missing = {
          ...op,
          table: { ...op.table, name: '__better_supabase_missing__' },
        } as Operation;
        const result = await executor.execute(missing, context);
        expect(!result.ok, 'a missing table must fail');
        expect(
          typeof result.error.kind === 'string' &&
            typeof result.error.message === 'string',
          'errors must be DbErrors',
        );
      },
    ],
    executor.rpc && [
      'returns rpc failures as results',
      async () => {
        const result = await executor.rpc!(
          '__better_supabase_missing__',
          {},
          { ...context, schema: 'public' },
        );
        expect(!result.ok, 'calling a missing function must fail');
      },
    ],
    executor.functionSources && [
      'reads from SelectOp.source instead of the table',
      async () => {
        const op = await read();
        if (op.kind !== 'select') return;
        const result = await executor.execute(
          {
            ...op,
            source: {
              schema: op.table.schema,
              name: '__better_supabase_missing__',
              args: {},
            },
          },
          context,
        );
        expect(
          !result.ok,
          'a missing source function must fail; reading the table ignores source',
        );
      },
    ],
    executor.batch && [
      'batch returns one result per operation, in order',
      async () => {
        const rows = await read();
        const count = await captureOp(sb, (db) => db[table]!.count!());
        const missing = {
          ...rows,
          table: { ...rows.table, name: '__better_supabase_missing__' },
        } as Operation;
        const results = await executor.batch!([rows, count, missing], context);
        expect(
          results.length === 3,
          `expected 3 results, got ${results.length}`,
        );
        const [first, second, third] = results;
        expect(
          first?.ok === true && Array.isArray(first.data.rows),
          'the first operation must return rows',
        );
        expect(
          second?.ok === true && typeof second.data.count === 'number',
          'the second operation must return a count',
        );
        expect(
          third?.ok === false,
          'a failing operation must fail on its own, as a result',
        );
      },
    ],
    create && [
      'round-trips a write',
      async () => {
        // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- the kit runs against any schema, so repositories are indexed by name.
        const repository = (sb.connect(executor) as unknown as AnyDb)[table]!;
        const created = await repository.create!(create);
        expect(created.ok, `create failed: ${JSON.stringify(created.error)}`);
        const row = created.data as Record<string, unknown>;
        for (const [key, value] of Object.entries(create)) {
          expect(
            same(row[key], value),
            `created row has ${key} = ${JSON.stringify(row[key])}`,
          );
        }
        const [primary] = sb.meta.tables[table]!.primaryKey;
        expect(primary, 'write checks need a table with a primary key');
        const removed = await repository.delete!(row[primary]);
        expect(removed.ok, `delete failed: ${JSON.stringify(removed.error)}`);
        const again = await repository.findFirst!({
          where: { [primary]: row[primary] },
        });
        expect(
          again.ok && again.data === null,
          'the deleted row is still readable',
        );
      },
    ],
  ]);
}

/**
 * Proves a `CacheAdapter` accepts table and row targets, repeated and
 * concurrent calls, and never mutates its input.
 */
export function testCacheAdapter(
  adapter: CacheAdapter,
  options: { readonly table?: string } = {},
): Promise<ConformanceReport> {
  const table = options.table ?? 'customers';
  const invalidate = (target: CacheTarget): Promise<void> =>
    Promise.resolve(adapter.invalidate(deepFreeze(target)));
  return conform(`CacheAdapter "${adapter.name}"`, [
    hasName(adapter),
    [
      'invalidates a table',
      () => invalidate({ table, tables: [table], ids: [] }),
    ],
    [
      'invalidates rows of a tenant',
      () =>
        invalidate({
          table,
          tables: [table],
          ids: ['1', 'a,b'],
          tenant: 'org_1',
        }),
    ],
    [
      'accepts repeated and concurrent calls',
      async () => {
        await invalidate({ table, tables: [table], ids: ['1'] });
        await Promise.all(
          Array.from({ length: 10 }, (_, index) =>
            invalidate({ table, tables: [table], ids: [String(index)] }),
          ),
        );
      },
    ],
    [
      'accepts tables it has never seen',
      () =>
        invalidate({
          table: '__better_supabase_unknown__',
          tables: ['__better_supabase_unknown__'],
          ids: [],
        }),
    ],
    [
      'invalidates tables reached through foreign keys',
      () =>
        invalidate({ table, tables: [table, `${table}_children`], ids: ['1'] }),
    ],
  ]);
}

export interface TestEventSinkOptions {
  /** Events the sink delivered, for sinks that can be read back (an outbox, a test queue). */
  readonly received?: () =>
    | readonly CloudEvent[]
    | Promise<readonly CloudEvent[]>;
}

/** Proves an `EventSink` accepts empty and full batches without mutating them, and delivers them when readable. */
export function testEventSink(
  sink: EventSink,
  options: TestEventSinkOptions = {},
): Promise<ConformanceReport> {
  const events = toCloudEvents(
    {
      table: 'customers',
      kind: 'insert',
      rows: [
        { id: '1', name: 'Acme' },
        { id: '2', name: 'Globex' },
      ],
      context: { tenant: 'org_1' },
    },
    { source: '/better-supabase/conformance' },
  );
  return conform('EventSink', [
    ['accepts an empty batch', () => sink.send(deepFreeze([]))],
    [
      'accepts a batch without mutating it',
      () => sink.send(frozenCopy(events)),
    ],
    options.received && [
      'delivers every event',
      async () => {
        const ids = new Set(
          (await options.received!()).map((event) => event.id),
        );
        const missing = events.filter((event) => !ids.has(event.id));
        expect(
          missing.length === 0,
          `${missing.length} of ${events.length} events were not delivered`,
        );
      },
    ],
  ]);
}

export interface TestAuthResolverOptions {
  /** Requests with credentials this resolver owns but that must not verify. */
  readonly invalid: readonly Request[];
  /** Requests that must resolve to a user or service, optionally with the expected user id. */
  readonly valid?: readonly {
    readonly request: Request;
    readonly userId?: string;
  }[];
  /** A request without this resolver's credentials. Defaults to a bare GET. */
  readonly unrelated?: Request;
}

async function resolveSafely(
  resolver: AuthResolver,
  request: Request,
): Promise<AuthState | undefined> {
  try {
    return await resolver.resolve(request);
  } catch (cause) {
    throw new Violation(
      `resolve() threw: ${cause instanceof Error ? cause.message : String(cause)}`,
    );
  }
}

/**
 * Proves an `AuthResolver` passes on requests it doesn't understand, fails
 * closed (`invalid`, never anon) on bad credentials, and never throws.
 */
export function testAuthResolver(
  resolver: AuthResolver,
  options: TestAuthResolverOptions,
): Promise<ConformanceReport> {
  return conform(`AuthResolver "${resolver.name}"`, [
    hasName(resolver),
    [
      'passes on requests without its credentials',
      async () => {
        const state = await resolveSafely(
          resolver,
          options.unrelated ?? new Request('https://example.com/'),
        );
        expect(
          state === undefined,
          `expected undefined, got kind "${state?.kind}"`,
        );
      },
    ],
    [
      'fails closed on invalid credentials',
      async () => {
        expect(options.invalid.length > 0, 'pass at least one invalid request');
        for (const request of options.invalid) {
          const state = await resolveSafely(resolver, request);
          expect(
            state?.kind === 'invalid',
            `expected kind "invalid", got "${state?.kind ?? 'undefined'}"`,
          );
          expect(
            typeof state.error.kind === 'string',
            'invalid states carry a DbError',
          );
        }
      },
    ],
    options.valid && [
      'resolves valid credentials',
      async () => {
        for (const { request, userId } of options.valid!) {
          const state = await resolveSafely(resolver, request);
          expect(
            state?.kind === 'user' || state?.kind === 'service',
            `expected a user or service, got "${state?.kind}"`,
          );
          if (userId !== undefined) {
            expect(
              state.kind === 'user' && state.user.id === userId,
              `expected user ${userId}`,
            );
          }
        }
      },
    ],
  ]);
}

function relativeImport(from: string, to: string): string {
  const fromParts = from.split('/').slice(0, -1);
  const toParts = to.split('/');
  let common = 0;
  while (common < fromParts.length && fromParts[common] === toParts[common])
    common += 1;
  const path = [
    ...Array.from({ length: fromParts.length - common }, () => '..'),
    ...toParts.slice(common),
  ].join('/');
  return path.startsWith('.') ? path : `./${path}`;
}

export interface TestGeneratorOptions {
  /** Schema metadata to generate from: `schema.meta` from your generated module. */
  readonly meta: SchemaMeta;
  /** Typegen metadata; defaults to an empty database. */
  readonly introspection?: GeneratorInput['introspection'];
  readonly extras?: GeneratorInput['extras'];
  readonly config?: ResolvedConfig;
}

const EMPTY_INTROSPECTION: GeneratorInput['introspection'] = {
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
};

/** Proves a `Generator` writes relative, unique paths, is deterministic and doesn't mutate its input. */
export function testGenerator(
  generator: Generator,
  options: TestGeneratorOptions,
): Promise<ConformanceReport> {
  const config = options.config ?? resolveConfig({}, '/project');
  const input = (): GeneratorInput => ({
    meta: frozenCopy(options.meta),
    introspection: frozenCopy(options.introspection ?? EMPTY_INTROSPECTION),
    extras: frozenCopy(
      options.extras ?? { tables: [], buckets: [], realtime: [] },
    ),
    config,
    output: `${config.root}/${config.output}`,
    importPath: (from, to) => relativeImport(from, to),
  });
  return conform(`Generator "${generator.name}"`, [
    hasName(generator),
    [
      'writes files inside the project',
      async () => {
        const files = await generator.generate(input());
        expect(Array.isArray(files), 'generate() must return an array');
        for (const file of files) {
          expect(
            typeof file.path === 'string' && typeof file.contents === 'string',
            'files need a path and contents',
          );
          expect(
            !file.path.startsWith('/') && !/^[A-Za-z]:/.test(file.path),
            `${file.path} must be relative`,
          );
          expect(
            !file.path.split(/[\\/]/).includes('..'),
            `${file.path} must stay inside the project`,
          );
        }
        const paths = files.map((file) => file.path);
        expect(new Set(paths).size === paths.length, 'paths must be unique');
      },
    ],
    [
      'is deterministic and does not mutate its input',
      async () => {
        const first = await generator.generate(input());
        const second = await generator.generate(input());
        expect(same(first, second), 'two runs on the same input differ');
      },
    ],
  ]);
}

export interface TestPluginOptions {
  /** The definition without this plugin. */
  readonly sb: AnySupabase;
  /** Table to exercise. Defaults to the first table. */
  readonly table?: string;
  /** Context the plugin needs, such as `{ tenant }` for `tenant()`. */
  readonly context?: RequestContext;
  /** Row for `create`, to exercise `beforeMutation`. */
  readonly create?: Readonly<Record<string, unknown>>;
}

/**
 * Proves a `Plugin` targets API v1, installs cleanly, keeps `transformQuery`
 * and `beforeMutation` pure and deterministic, and keeps executors'
 * results intact when it wraps them.
 */
export function testPlugin(
  plugin: AnyPlugin,
  options: TestPluginOptions,
): Promise<ConformanceReport> {
  const { sb } = options;
  const table = tableKey(sb, options.table);
  const context = options.context ?? {};
  const hook = (op: Operation): HookArgs => ({
    table: op.table,
    schema: sb.meta,
    context,
    options: {},
    now: () => new Date(0),
  });
  const create = options.create;
  return conform(`Plugin "${plugin.name}"`, [
    hasName(plugin),
    [
      'targets plugin API v1',
      () =>
        expect(
          plugin.apiVersion === 1,
          `apiVersion is ${String(plugin.apiVersion)}`,
        ),
    ],
    [
      'installs and builds repositories',
      () => {
        // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- the kit runs against any schema, so repositories are indexed by name.
        const db = sb
          .use(plugin)
          .connect(recorder([]), context) as unknown as AnyDb;
        for (const key of Object.keys(sb.meta.tables))
          expect(db[key], `db.${key} is missing`);
      },
    ],
    plugin.transformQuery && [
      'transformQuery is pure and deterministic',
      async () => {
        const op = await captureOp(sb, (db) =>
          db[table]!.findMany!({ limit: 1 }),
        );
        const first = plugin.transformQuery!(frozenCopy(op), hook(op));
        const second = plugin.transformQuery!(frozenCopy(op), hook(op));
        expect(
          typeof first === 'object' && first !== null && first.kind === op.kind,
          'must return an operation of the same kind',
        );
        expect(same(first, second), 'two calls with the same input differ');
      },
    ],
    plugin.beforeMutation &&
      create && [
        'beforeMutation is pure and deterministic',
        async () => {
          const op = await captureOp(sb, (db) => db[table]!.create!(create));
          if (op.kind === 'select')
            throw new Violation('create did not produce a mutation');
          const first = await plugin.beforeMutation!(frozenCopy(op), hook(op));
          const second = await plugin.beforeMutation!(frozenCopy(op), hook(op));
          expect(
            first.kind === op.kind,
            'must return a mutation of the same kind',
          );
          expect(same(first, second), 'two calls with the same input differ');
        },
      ],
    plugin.wrapExecutor && [
      'wrapExecutor keeps results intact',
      async () => {
        const op = await captureOp(sb, (db) =>
          db[table]!.findMany!({ limit: 1 }),
        );
        const data = { rows: [{ marker: 'conformance' }], count: 1 };
        const wrapped = plugin.wrapExecutor!({
          name: 'inner',
          execute: () => Promise.resolve(ok(data)),
        });
        expect(
          typeof wrapped.name === 'string',
          'the wrapped executor needs a name',
        );
        const result = await wrapped.execute(op, { errorMappers: [] });
        expect(
          result.ok && same(result.data, data),
          'the wrapped executor changed the result',
        );
      },
    ],
    plugin.mapError && [
      'mapError returns a DbError or undefined',
      () => {
        const fallback = dbError('unexpected', 'internal error');
        const mapped = plugin.mapError!(
          { code: 'XX000', message: 'internal error' },
          fallback,
        );
        expect(
          mapped === undefined ||
            (typeof mapped === 'object' && typeof mapped.kind === 'string'),
          'must return a DbError or undefined',
        );
      },
    ],
  ]);
}
