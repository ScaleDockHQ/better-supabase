import type { BlockCall } from "./block-helpers.ts";
import type { BlockTransport } from "./block-transport.ts";
import type { Logger } from "./logger.ts";

import { blockCall, DEFAULT_BLOCK_SCHEMA } from "./block-helpers.ts";
import {
  type DbError,
  dbError,
  type ErrorMapper,
  isDbError,
} from "./errors.ts";
import { consoleLogger } from "./logger.ts";
import { AsyncResult, err, type Result } from "./result.ts";

/** A block method: anything that returns an `AsyncResult`. */
type BlockMethod = (...args: never[]) => AsyncResult<unknown>;

/** The names of a block client's methods that return an `AsyncResult`. */
export type BlockMethodName<C> = {
  [K in keyof C]: C[K] extends BlockMethod ? K : never;
}[keyof C] &
  string;

type ArgsOf<F> = F extends (...args: infer A) => AsyncResult<unknown>
  ? A
  : never;
type DataOf<F> = F extends (...args: never[]) => AsyncResult<infer T>
  ? T
  : never;

/** Which call a hook runs for. */
export interface BlockHookInfo {
  /** The block, as `createBlocks` names it, or the name `withBlockHooks` got. */
  readonly block: string;
  readonly method: string;
}

/**
 * Hooks for one block method. `before` runs first: return nothing to keep
 * the arguments, a new argument list to replace them, or a `DbError` to
 * refuse the call, which then returns that error without reaching the
 * database. `after` observes a copy of the result and can't change it; when
 * it throws, the logger gets the error and the caller still gets the result.
 */
export interface BlockMethodHooks<A extends readonly unknown[], T> {
  readonly before?: (
    args: A,
    info: BlockHookInfo,
  ) => Readonly<A> | DbError | void | Promise<Readonly<A> | DbError | void>;
  readonly after?: (
    result: Result<T>,
    args: A,
    info: BlockHookInfo,
  ) => void | Promise<void>;
}

/** Hooks keyed by the block client's method names. */
export type BlockHooks<C> = {
  readonly [K in BlockMethodName<C>]?: BlockMethodHooks<
    ArgsOf<C[K]>,
    DataOf<C[K]>
  >;
};

export interface WithBlockHooksOptions {
  /** The block's name in `BlockHookInfo` and log messages. Default `block`. */
  readonly block?: string;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

const isPlainObject = (value: object): boolean => {
  const proto: unknown = Object.getPrototypeOf(value);
  return proto === Object.prototype || proto === null;
};

/** A copy of plain objects and arrays; class instances (Temporal values) are immutable and stay shared. */
function copyOf(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(copyOf);
  if (typeof value === "object" && value !== null && isPlainObject(value)) {
    return Object.fromEntries(
      Object.entries(value).map(([key, entry]) => [key, copyOf(entry)]),
    );
  }
  return value;
}

/** A new client with the same methods: a spread for object literals, a child object otherwise. */
function cloneClient(client: object): Record<string, unknown> {
  if (isPlainObject(client)) return { ...client };
  // SAFETY: Object.create returns an empty object whose prototype is client;
  // the caller only adds string-keyed methods to it.
  return Object.create(client) as Record<string, unknown>;
}

type Method = (...args: unknown[]) => unknown;

/** The client's method named `name`, or undefined when it has none. */
function methodOf(client: object, name: string): Method | undefined {
  // SAFETY: a read of one string key; the result is checked before use.
  const value = (client as Readonly<Record<string, unknown>>)[name];
  if (typeof value !== "function") return undefined;
  // SAFETY: any function accepts unknown arguments at runtime; the hook
  // passes it the arguments its caller gave.
  return value as Method;
}

/**
 * Runs `hooks` around a block client's methods. Use it to add a rule the
 * block doesn't know (refuse `invite` above a seat limit), rewrite arguments
 * (fill a default), or observe results (metrics, an audit line). Methods
 * without hooks are unchanged.
 *
 * ```ts
 * const orgs = withBlockHooks(createOrganizations(options), {
 *   invite: { before: ([input]) => (input.role === "owner" ? dbError("forbidden", "Owners are added by support") : undefined) },
 * });
 * ```
 */
export function withBlockHooks<C extends object>(
  client: C,
  hooks: BlockHooks<C> | undefined,
  options: WithBlockHooksOptions = {},
): C {
  if (hooks === undefined) return client;
  const block = options.block ?? "block";
  const logger = options.logger ?? consoleLogger;
  const wrapped = cloneClient(client);
  for (const [method, hook] of Object.entries(hooks)) {
    if (hook === undefined) continue;
    const original = methodOf(client, method);
    if (original === undefined) {
      throw new TypeError(
        `better-supabase: ${block} has no method "${method}" to hook`,
      );
    }
    // SAFETY: the key came from BlockHooks<C>, whose values are these hooks.
    const { before, after } = hook as BlockMethodHooks<unknown[], unknown>;
    const info: BlockHookInfo = { block, method };
    wrapped[method] = (...args: unknown[]): AsyncResult<unknown> =>
      AsyncResult.from(async () => {
        let current = args;
        if (before) {
          const outcome = await before(current, info);
          if (isDbError(outcome)) return err(outcome);
          if (Array.isArray(outcome)) current = outcome;
        }
        // SAFETY: original is one of the client's AsyncResult methods.
        const result = await (original.apply(
          client,
          current,
        ) as AsyncResult<unknown>);
        if (after) {
          try {
            // SAFETY: copyOf keeps the shape of the value it copies.
            await after(copyOf(result) as Result<unknown>, current, info);
          } catch (cause) {
            logger.error(`${block}.${method} after hook threw`, { cause });
          }
        }
        return result;
      });
  }
  // SAFETY: wrapped has every member of client, with hooked methods replaced
  // by functions of the same signature.
  return wrapped as C;
}

/** What `extendBlock` hands the builder besides the base client. */
export interface ExtendBlockTools {
  /**
   * Calls a SQL function in the block's schema over its transport and maps a
   * rejection to a `DbError`, as the block's own methods do. Needs the
   * `transport` option.
   */
  readonly call: BlockCall;
}

export interface ExtendBlockOptions {
  /** The transport `call` uses: the one the block was created with. */
  readonly transport?: BlockTransport;
  /** The schema `call` targets. Default `better_supabase`. */
  readonly schema?: string;
  /** Error mappers `call` runs before the built-in ones. */
  readonly mappers?: readonly ErrorMapper[];
}

/**
 * Adds methods to a block client. The builder gets the base client, so a
 * new method can compose existing ones, and `call` for SQL functions the
 * app adds to the block's schema. Redefining a base method throws: wrap it
 * with `withBlockHooks` instead.
 *
 * ```ts
 * const orgs = extendBlock(createOrganizations(options), (base, { call }) => ({
 *   archive: (id: string) => call("archive_organization", { id }, () => undefined),
 * }), { transport: options.transport });
 * ```
 */
export function extendBlock<C extends object, X extends object>(
  client: C,
  build: (base: C, tools: ExtendBlockTools) => X,
  options: ExtendBlockOptions = {},
): C & X {
  const { transport } = options;
  const call: BlockCall = transport
    ? blockCall(
        transport,
        options.schema ?? DEFAULT_BLOCK_SCHEMA,
        options.mappers ?? [],
      )
    : () =>
        AsyncResult.err(
          dbError(
            "unsupported",
            "extendBlock needs the transport option to call SQL functions",
          ),
        );
  const additions = build(client, { call });
  const taken = Object.keys(additions).filter((key) => key in client);
  if (taken.length > 0) {
    throw new TypeError(
      `better-supabase: extendBlock can't redefine ${taken.map((key) => `"${key}"`).join(", ")}; wrap a base method with withBlockHooks instead`,
    );
  }
  // SAFETY: the clone has every member of client and Object.assign adds
  // every member of additions, which share no keys.
  return Object.assign(cloneClient(client), additions) as C & X;
}

/** One transport call, as middleware sees it. */
export interface BlockTransportRequest {
  readonly schema: string;
  readonly fn: string;
  readonly args: Readonly<Record<string, unknown>>;
}

/**
 * Runs around every call a transport makes: tracing, a statement timeout,
 * an extra argument every function takes. Pass a changed request to `next`
 * to rewrite it. Reject with the error `next` rejected with so the block
 * still maps it to a `DbError`.
 */
export interface BlockTransportMiddleware {
  readonly apiVersion: 1;
  readonly name: string;
  call(
    request: BlockTransportRequest,
    next: (request: BlockTransportRequest) => Promise<unknown>,
  ): Promise<unknown>;
}

/** Fills in `apiVersion: 1`. */
export function defineTransportMiddleware(
  middleware: Omit<BlockTransportMiddleware, "apiVersion"> & {
    readonly apiVersion?: 1;
  },
): BlockTransportMiddleware {
  return { ...middleware, apiVersion: 1 };
}

/**
 * A transport that runs `middleware` around `transport`, the first one
 * outermost. Throws when a middleware targets an API other than 1.
 */
export function wrapTransport(
  transport: BlockTransport,
  ...middleware: readonly BlockTransportMiddleware[]
): BlockTransport {
  for (const entry of middleware) {
    const version: unknown = entry.apiVersion;
    if (version !== 1) {
      throw new TypeError(
        `better-supabase: transport middleware "${entry.name}" targets API ${String(version)}; this better-supabase supports 1`,
      );
    }
  }
  const run = middleware.reduceRight<
    (request: BlockTransportRequest) => Promise<unknown>
  >(
    (next, entry) => (request) => entry.call(request, next),
    (request) => transport.call(request.schema, request.fn, request.args),
  );
  return {
    call: (schema, fn, args) => run({ schema, fn, args }),
  };
}
