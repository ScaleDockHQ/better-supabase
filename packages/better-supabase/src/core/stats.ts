import type { Executor } from "./executor.ts";

/** Database work for one request (or one `db`). */
export interface DbStats {
  /** Executor calls: repository operations and RPCs. */
  readonly calls: number;
  /**
   * Sequential rounds. A wave starts when a call begins while nothing else is
   * in flight, so `Promise.all` of three reads is one wave.
   */
  readonly waves: number;
  /** App keys of the tables read or written, and `name()` for RPCs. */
  readonly tables: readonly string[];
  /** From the first call's start to the last call's end. */
  readonly ms: number;
  /** Token verifications the request ran (memo misses), across its scopes. */
  readonly verifications: number;
  /** Calls made with the service role while serving a user request. */
  readonly adminCalls: number;
}

export const EMPTY_STATS: DbStats = {
  calls: 0,
  waves: 0,
  tables: [],
  ms: 0,
  verifications: 0,
  adminCalls: 0,
};

/**
 * Counts calls and waves. A recorder with a `parent` also reports to it, so a
 * request-wide recorder sees every scope's calls.
 */
export class StatsRecorder {
  readonly #parent: StatsRecorder | undefined;
  readonly #now: () => number;
  readonly #admin: boolean;
  readonly #tables = new Set<string>();
  #calls = 0;
  #waves = 0;
  #verifications = 0;
  #adminCalls = 0;
  #inFlight = 0;
  #first: number | undefined;
  #last: number | undefined;

  constructor(
    parent?: StatsRecorder,
    now: () => number = () => performance.now(),
    /** Marks every call this recorder (and its children) sees as service-role. */
    admin?: boolean,
  ) {
    this.#parent = parent;
    this.#now = now;
    this.#admin = admin ?? parent?.admin ?? false;
  }

  /** Whether this recorder's calls run with the service role. */
  get admin(): boolean {
    return this.#admin;
  }

  /** Records one token verification (a session memo miss). */
  verification(): void {
    this.#verifications += 1;
    this.#parent?.verification();
  }

  /**
   * Records a call to `table`; the returned function ends it. `admin` marks a
   * call made with the service role.
   */
  begin(table: string, service?: boolean): () => void {
    const admin = service ?? this.#admin;
    const end = this.#parent?.begin(table, admin);
    const started = this.#now();

    if (this.#inFlight === 0) {
      this.#waves += 1;
    }

    this.#inFlight += 1;
    this.#calls += 1;

    if (admin) {
      this.#adminCalls += 1;
    }

    this.#tables.add(table);
    this.#first ??= started;
    let ended = false;

    return () => {
      if (ended) {
        return;
      }

      ended = true;
      this.#inFlight -= 1;
      this.#last = Math.max(this.#last ?? 0, this.#now());
      end?.();
    };
  }

  /** The totals so far. */
  snapshot(): DbStats {
    return {
      calls: this.#calls,
      waves: this.#waves,
      tables: [...this.#tables],
      ms:
        this.#first === undefined || this.#last === undefined
          ? 0
          : Math.round((this.#last - this.#first) * 100) / 100,
      verifications: this.#verifications,
      adminCalls: this.#adminCalls,
    };
  }
}

/**
 * What a Supabase API path names: the table, `name()` for an RPC, the function
 * or the bucket. Auth and Realtime calls aren't database work and name
 * nothing.
 */
function callOf(url: string): string | undefined {
  const { pathname } = new URL(url);
  const [, api, version, first, second] = pathname.split("/");

  if (version !== "v1" || first === undefined || first === "") {
    return undefined;
  }

  switch (api ?? "") {
    case "rest": {
      return first === "rpc" && second ? `${second}()` : first;
    }

    case "functions": {
      return `functions/${first}`;
    }

    case "storage": {
      return first === "object" && second ? `storage/${second}` : "storage";
    }

    default: {
      return undefined;
    }
  }
}

/**
 * A fetch that records each PostgREST, RPC, Storage and Edge Function call on
 * `recorder`, for the raw `supabase` client. It sends the request unchanged.
 * `base` is read on every call, so a fetch replaced later is the one used.
 */
export function recordingFetch(
  recorder: StatsRecorder,
  base: () => typeof fetch = () => globalThis.fetch,
): typeof fetch {
  return async (input, init) => {
    const url =
      typeof input === "string"
        ? input
        : input instanceof URL
          ? input.href
          : input.url;

    const call = callOf(url);
    const end = call === undefined ? undefined : recorder.begin(call);

    try {
      return await base()(input, init);
    } finally {
      end?.();
    }
  };
}

/** Wraps an executor so every call is recorded. */
export function recordStats(
  executor: Executor,
  recorder: StatsRecorder,
): Executor {
  const wrapped: Executor = {
    name: executor.name,
    async execute(op, context) {
      const end = recorder.begin(op.table.key);

      try {
        return await executor.execute(op, context);
      } finally {
        end();
      }
    },
  };

  if (executor.rpc) {
    const rpc = executor.rpc.bind(executor);

    return {
      ...wrapped,
      async rpc(name, args, context) {
        const end = recorder.begin(`${name}()`);

        try {
          return await rpc(name, args, context);
        } finally {
          end();
        }
      },
    };
  }

  return wrapped;
}
