/** A request the fake client recorded, in PostgREST terms. */
export interface FakeRequest {
  readonly method: "GET" | "POST" | "PATCH" | "DELETE";
  /** `/table` or `/rpc/name`. */
  readonly path: string;
  readonly schema: string;
  /** Filters, ordering and paging as PostgREST query parameters. */
  readonly query: Readonly<Record<string, string>>;
  readonly body?: unknown;
  /**
   * The `Prefer` header values the call implies, such as
   * `resolution=merge-duplicates`.
   */
  readonly prefer: readonly string[];
}

export interface FakeReply {
  readonly data?: unknown;
  readonly error?: {
    readonly message: string;
    readonly code?: string;
    readonly details?: string;
    readonly hint?: string;
  };
  readonly count?: number;
}

export type FakeHandler = (
  request: FakeRequest,
) => FakeReply | Promise<FakeReply>;

interface Settled {
  readonly data: unknown;
  readonly error: FakeReply["error"] | null;
  readonly count: number | null;
  readonly status: number;
  readonly statusText: string;
}

type Cardinality = "many" | "single" | "maybe";

/** PostgREST's answer to `.single()` when the result is not exactly one row. */
function pgrst116(rows: number) {
  return {
    message: "JSON object requested, multiple (or no) rows returned",
    code: "PGRST116",
    details: `The result contains ${rows} rows`,
    hint: "",
  } as const;
}

function filterValue(operator: string, value: unknown): string {
  if (Array.isArray(value)) {
    const items = value.map(String).join(",");

    return operator === "cs" || operator === "cd" || operator === "ov"
      ? `{${items}}`
      : `(${items})`;
  }

  return String(value);
}

class FakeQuery implements PromiseLike<Settled> {
  private readonly query: Record<string, string> = {};
  private cardinality: Cardinality = "many";
  private body: unknown;
  private readonly prefer: string[] = [];

  private readonly handler: FakeHandler;
  private readonly sink: FakeRequest[];
  private method: FakeRequest["method"];
  private readonly path: string;
  private readonly schemaName: string;

  constructor(
    handler: FakeHandler,
    sink: FakeRequest[],
    method: FakeRequest["method"],
    path: string,
    schemaName: string,
  ) {
    this.handler = handler;
    this.sink = sink;
    this.method = method;
    this.path = path;
    this.schemaName = schemaName;
  }

  select(columns = "*"): this {
    this.query["select"] = columns;

    return this;
  }

  insert(values: unknown): this {
    this.method = "POST";
    this.body = values;

    return this;
  }

  upsert(
    values: unknown,
    options: { readonly onConflict?: string } = {},
  ): this {
    this.method = "POST";
    this.body = values;
    this.prefer.push("resolution=merge-duplicates");

    if (options.onConflict) {
      this.query["on_conflict"] = options.onConflict;
    }

    return this;
  }

  update(values: unknown): this {
    this.method = "PATCH";
    this.body = values;

    return this;
  }

  delete(): this {
    this.method = "DELETE";

    return this;
  }

  eq(column: string, value: unknown): this {
    return this.filter(column, "eq", value);
  }

  neq(column: string, value: unknown): this {
    return this.filter(column, "neq", value);
  }

  gt(column: string, value: unknown): this {
    return this.filter(column, "gt", value);
  }

  gte(column: string, value: unknown): this {
    return this.filter(column, "gte", value);
  }

  lt(column: string, value: unknown): this {
    return this.filter(column, "lt", value);
  }

  lte(column: string, value: unknown): this {
    return this.filter(column, "lte", value);
  }

  like(column: string, value: unknown): this {
    return this.filter(column, "like", value);
  }

  ilike(column: string, value: unknown): this {
    return this.filter(column, "ilike", value);
  }

  is(column: string, value: unknown): this {
    return this.filter(column, "is", value);
  }

  contains(column: string, value: unknown): this {
    return this.filter(column, "cs", value);
  }

  containedBy(column: string, value: unknown): this {
    return this.filter(column, "cd", value);
  }

  overlaps(column: string, value: unknown): this {
    return this.filter(column, "ov", value);
  }

  in(column: string, values: readonly unknown[]): this {
    this.query[column] = `in.${filterValue("in", values)}`;

    return this;
  }

  not(column: string, operator: string, value: unknown): this {
    this.query[column] = `not.${operator}.${filterValue(operator, value)}`;

    return this;
  }

  or(filters: string): this {
    this.query["or"] = `(${filters})`;

    return this;
  }

  match(values: Readonly<Record<string, unknown>>): this {
    for (const [column, value] of Object.entries(values)) {
      this.query[column] = `eq.${String(value)}`;
    }

    return this;
  }

  filter(column: string, operator: string, value: unknown): this {
    this.query[column] = `${operator}.${filterValue(operator, value)}`;

    return this;
  }

  order(
    column: string,
    options: {
      readonly ascending?: boolean;
      readonly nullsFirst?: boolean;
    } = {},
  ): this {
    const part = `${column}.${options.ascending === false ? "desc" : "asc"}${
      options.nullsFirst === undefined
        ? ""
        : options.nullsFirst
          ? ".nullsfirst"
          : ".nullslast"
    }`;

    this.query["order"] = this.query["order"]
      ? `${this.query["order"]},${part}`
      : part;

    return this;
  }

  limit(count: number): this {
    this.query["limit"] = String(count);

    return this;
  }

  range(from: number, to: number): this {
    this.query["offset"] = String(from);
    this.query["limit"] = String(to - from + 1);

    return this;
  }

  single(): this {
    this.cardinality = "single";

    return this;
  }

  maybeSingle(): this {
    this.cardinality = "maybe";

    return this;
  }

  /** `.rpc()` arguments for a GET are query parameters; for a POST, the body. */
  withRpcArgs(args: unknown, head: boolean): this {
    if (head) {
      this.method = "GET";

      for (const [key, value] of Object.entries(
        typeof args === "object" && args !== null ? args : {},
      )) {
        this.query[key] = String(value);
      }
    } else {
      this.method = "POST";
      this.body = args;
    }

    return this;
  }

  private async run(): Promise<Settled> {
    const request: FakeRequest = {
      method: this.method,
      path: this.path,
      schema: this.schemaName,
      query: { ...this.query },
      prefer: [...this.prefer],
      ...(this.body === undefined ? {} : { body: this.body }),
    };

    this.sink.push(request);
    const reply = await this.handler(request);

    if (reply.error) {
      return {
        data: null,
        error: reply.error,
        count: null,
        status: 400,
        statusText: "Bad Request",
      };
    }

    // SAFETY: Array.isArray narrowed it; the elements are opaque rows.
    const rows = Array.isArray(reply.data)
      ? (reply.data as unknown[])
      : undefined;

    let { data } = reply;

    if (
      this.cardinality === "single" &&
      !rows &&
      (data === null || data === undefined)
    ) {
      return {
        data: null,
        error: pgrst116(0),
        count: null,
        status: 406,
        statusText: "Not Acceptable",
      };
    }

    if (this.cardinality !== "many" && rows) {
      if (rows.length === 1) {
        data = rows[0];
      } else if (this.cardinality === "maybe" && rows.length === 0) {
        data = null;
      } else {
        return {
          data: null,
          error: pgrst116(rows.length),
          count: null,
          status: 406,
          statusText: "Not Acceptable",
        };
      }
    }

    return {
      data: data ?? null,
      error: null,
      count: reply.count ?? null,
      status: 200,
      statusText: "OK",
    };
  }

  // oxlint-disable-next-line unicorn/no-thenable -- supabase-js builders are awaited
  then<R1 = Settled, R2 = never>(
    onfulfilled?: ((value: Settled) => R1 | PromiseLike<R1>) | null,
    onrejected?: ((reason: unknown) => R2 | PromiseLike<R2>) | null,
  ): PromiseLike<R1 | R2> {
    return this.run().then(onfulfilled, onrejected);
  }
}

export interface FakeClient {
  /** Every request, in order. */
  readonly requests: readonly FakeRequest[];
  from(table: string): FakeQuery;
  rpc(
    name: string,
    args?: unknown,
    options?: { readonly head?: boolean; readonly get?: boolean },
  ): FakeQuery;
  schema(name: string): FakeClient;
}

/**
 * A stand-in for the supabase-js client in unit tests. The handler answers each
 * request (`method`, `path`, `query`, `body`); the client records them in
 * `requests`. It covers `from`, `rpc`, `schema`, the common filters,
 * `.single()` and `.maybeSingle()` (a miss is PGRST116, as on a real server).
 * Pass it where a `SupabaseClient` is expected, with a cast in the test.
 *
 * Test tokens come from `signTestJwt` and `createTestSigner`.
 */
export function createFakeClient(handler: FakeHandler): FakeClient {
  const requests: FakeRequest[] = [];

  const build = (schemaName: string): FakeClient => {
    const query = (method: FakeRequest["method"], path: string): FakeQuery =>
      new FakeQuery(handler, requests, method, path, schemaName);

    const client: FakeClient = {
      requests,
      from: (table) => query("GET", `/${table}`),
      rpc: (name, args, options) =>
        query("POST", `/rpc/${name}`).withRpcArgs(
          args,
          options?.head === true || options?.get === true,
        ),
      schema: build,
    };

    return client;
  };

  return build("public");
}
