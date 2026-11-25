import type { Executor } from "./executor.ts";

/**
 * What a call belongs to. `action` is inside `bsb.action`, `authorization` and
 * `write` are what `bsb.phase()` marks, and `render` is everything else.
 */
export type StatsPhase = "action" | "authorization" | "write" | "render";

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
  /**
   * Session cookies the request parsed (parse misses). A hit on the parsed
   * cookie memo isn't counted, so this is what the decoding cost.
   */
  readonly decodes?: number;
  /** Calls per phase, for the phases the request used. */
  readonly phases?: Readonly<Partial<Record<StatsPhase, number>>>;
  /**
   * Kept entries served without a fill (`bsb.kept()` and `bsb.cached({ keep })`
   * reads that hit), per phase, so an action shows what its reads saved.
   */
  readonly keptHits?: Readonly<Partial<Record<StatsPhase, number>>>;
  /** Calls made with the service role while serving a user request. */
  readonly adminCalls: number;
  /**
   * Cache tag calls the request made: one per `updateTag` or `revalidateTag`,
   * one per batch a store expires.
   */
  readonly tagCalls?: number;
  /**
   * The names of the tags those calls expired, in call order. A write that
   * expires many tags shows which ones (and so which entries it refills).
   */
  readonly expiredTags?: readonly string[];
  /** One record per `bsb.kept` and `bsb.remote` call the request made. */
  readonly entries?: readonly CacheEntryStat[];
  /**
   * Every call in start order, with its wave and phase. Times are milliseconds
   * from the first call's start.
   */
  readonly trace?: readonly TraceCall[];
}

/**
 * One database call of a request. `phase` is `action` for a call made inside
 * `bsb.action` and `render` for every other call, including the re-render a
 * server action starts.
 */
export interface TraceCall {
  readonly name: string;
  readonly startMs: number;
  readonly endMs: number;
  readonly wave: number;
  readonly phase: StatsPhase;
}

interface OpenTrace {
  readonly name: string;
  readonly start: number;
  readonly wave: number;
  readonly phase: StatsPhase;
  end: number;
}

/**
 * How one cached call was served. `wait` waited for a fill another call or
 * instance ran; `fillMs` is the time the fill took on a miss.
 */
export interface CacheEntryStat {
  /**
   * The kept function's `name`, the remote function's name, or for a private or
   * public entry its first table or tag.
   */
  readonly id: string;
  /**
   * `private` and `public` entries (`bsb.cached()` and `bsb.public()`) record
   * only a miss, when the wrapped body runs; a hit never runs it, so the
   * harness counts hits as visits minus misses.
   */
  readonly kind: "remote" | "kept" | "private" | "public";
  readonly outcome: "hit" | "miss" | "stale" | "wait";
  readonly fillMs?: number;
  /**
   * The size of the cached value as JSON, in bytes. Recorded for `kept`
   * entries; the value of a `remote`, `private` or `public` entry never reaches
   * the recorder (the sample's remote handler counts its own bytes).
   */
  readonly bytes?: number;
}

// Created on first use: the root entry loads on runtimes without TextEncoder.
let encoder: TextEncoder | undefined;

/** The size of `value` as JSON in bytes, or `undefined` when it has none. */
export function byteSizeOf(value: unknown): number | undefined {
  try {
    // `JSON.stringify` returns `undefined` for a function or `undefined`.
    const json: unknown = JSON.stringify(value);

    return typeof json === "string"
      ? (encoder ??= new TextEncoder()).encode(json).length
      : undefined;
  } catch {
    return undefined;
  }
}

const round = (ms: number): number => Math.round(ms * 100) / 100;

export const EMPTY_STATS: DbStats = {
  calls: 0,
  waves: 0,
  tables: [],
  ms: 0,
  verifications: 0,
  decodes: 0,
  phases: {},
  keptHits: {},
  adminCalls: 0,
  tagCalls: 0,
  expiredTags: [],
  entries: [],
  trace: [],
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
  #decodes = 0;
  #adminCalls = 0;
  #tagCalls = 0;
  readonly #expiredTags: string[] = [];
  readonly #entries: CacheEntryStat[] = [];
  readonly #trace: OpenTrace[] = [];
  #phase: StatsPhase = "render";
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

  /** Whether the calls also report to a parent recorder. */
  get linked(): boolean {
    return this.#parent !== undefined;
  }

  /**
   * Set when the connection's client already counts its own calls on the
   * ambient request recorder, so the executor must not count them again.
   */
  covered = false;

  /** Marks the phase the calls that start from now on belong to. */
  setPhase(phase: StatsPhase): void {
    this.#phase = phase;
  }

  /** The phase calls that start now belong to. */
  get phase(): StatsPhase {
    return this.#phase;
  }

  /** Records one session cookie parse. */
  decode(): void {
    this.#decodes += 1;
    this.#parent?.decode();
  }

  /** Records one token verification (a session memo miss). */
  verification(): void {
    this.#verifications += 1;
    this.#parent?.verification();
  }

  /** Records `count` cache tag calls, and the tag names when they are known. */
  tagCalls(count: number, tags?: readonly string[]): void {
    this.#tagCalls += count;

    if (tags) {
      this.#expiredTags.push(...tags);
    }

    this.#parent?.tagCalls(count, tags);
  }

  /** Records how one cached call was served. */
  entry(record: CacheEntryStat): void {
    this.#entries.push(record);

    if (record.kind === "kept" && record.outcome !== "miss") {
      this.#keptHits[this.#phase] = (this.#keptHits[this.#phase] ?? 0) + 1;
    }

    this.#parent?.entry(record);
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

    const traced: OpenTrace = {
      name: table,
      start: started,
      wave: this.#waves,
      phase: this.#phase,
      end: started,
    };

    this.#trace.push(traced);
    let ended = false;

    return () => {
      if (ended) {
        return;
      }

      ended = true;
      this.#inFlight -= 1;
      traced.end = this.#now();
      this.#last = Math.max(this.#last ?? 0, traced.end);
      end?.();
    };
  }

  #keptHits: Partial<Record<StatsPhase, number>> = {};

  #phaseCounts(): Partial<Record<StatsPhase, number>> {
    const counts: Partial<Record<StatsPhase, number>> = {};

    for (const call of this.#trace) {
      counts[call.phase] = (counts[call.phase] ?? 0) + 1;
    }

    return counts;
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
      decodes: this.#decodes,
      phases: this.#phaseCounts(),
      keptHits: { ...this.#keptHits },
      adminCalls: this.#adminCalls,
      tagCalls: this.#tagCalls,
      expiredTags: [...this.#expiredTags],
      entries: [...this.#entries],
      trace: this.#trace.map((call) => ({
        name: call.name,
        startMs: round(call.start - (this.#first ?? call.start)),
        endMs: round(call.end - (this.#first ?? call.start)),
        wave: call.wave,
        phase: call.phase,
      })),
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

const AMBIENT = Symbol.for("better-supabase.ambientStats");

/** Finds the recorder of the request the caller runs in, if there is one. */
export type AmbientStats = () => Promise<StatsRecorder | undefined>;

interface AmbientSlot {
  [AMBIENT]?: AmbientStats;
}

/**
 * Registers how a connection with no recorder of its own finds the current
 * request's recorder. `createNext` does it when debug is on, so a service that
 * calls `connect()` itself is counted in the request's stats.
 */
export function setAmbientStats(resolver: AmbientStats | undefined): void {
  // SAFETY: the symbol key is this module's own slot on the global object.
  const slot = globalThis as AmbientSlot;

  if (resolver) {
    slot[AMBIENT] = resolver;
  } else {
    delete slot[AMBIENT];
  }
}

/** The registered resolver, `undefined` when no `createNext` has debug on. */
export function ambientStats(): AmbientStats | undefined {
  // SAFETY: the symbol key is this module's own slot on the global object.
  return (globalThis as AmbientSlot)[AMBIENT];
}

const ambientRecorder = async (): Promise<StatsRecorder | undefined> => {
  try {
    return await ambientStats()?.();
  } catch {
    // Outside a request there is no recorder to find.
    return undefined;
  }
};

const ambientClients = new WeakSet<object>();

/**
 * Marks `client` as one whose fetch is `ambientFetch`, so `connect()` over it
 * doesn't count its calls a second time.
 */
export function markAmbientClient<T extends object>(client: T): T {
  ambientClients.add(client);

  return client;
}

/** Whether `client` counts its own calls on the ambient recorder. */
export const isAmbientClient = (client: unknown): boolean =>
  typeof client === "object" && client !== null && ambientClients.has(client);

/**
 * A fetch that records each call on the current request's recorder, found per
 * call, and sends it unchanged when there is none.
 */
export function ambientFetch(
  base: () => typeof fetch = () => globalThis.fetch,
): typeof fetch {
  return async (input, init) => {
    const request = await ambientRecorder();

    return request
      ? recordingFetch(request, base)(input, init)
      : base()(input, init);
  };
}

/** Wraps an executor so every call is recorded. */
export function recordStats(
  executor: Executor,
  recorder: StatsRecorder,
): Executor {
  // A connection with no parent also counts on the request it runs in.
  const begin = async (name: string): Promise<() => void> => {
    const own = recorder.begin(name);

    if (recorder.linked || recorder.covered) {
      return own;
    }

    const request = await ambientRecorder();
    const mirrored = request?.begin(name);

    return () => {
      own();
      mirrored?.();
    };
  };

  const wrapped: Executor = {
    name: executor.name,
    async execute(op, context) {
      const end = await begin(op.table.key);

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
        const end = await begin(`${name}()`);

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
