/**
 * One environment variable a block reads at runtime. `init` and `add` list it
 * in `.env.example`, and doctor's BS504 fails when a required one is missing
 * from every env file and the shell.
 */
export interface BlockEnvKey {
  readonly key: string;
  /** What it is for, written above the key in `.env.example`. */
  readonly description: string;
  /** Without it the block's routes or workers fail. Default: true. */
  readonly required?: boolean;
}

/**
 * One versioned interface the app implements for a block, passed as one of the
 * block's options (`blocks.enrichment.with({ provider })`). `init` and `add`
 * write a commented stub to `providers.ts`, and doctor's BS505 fails while a
 * required one is not set.
 */
export interface BlockProvider {
  /** The option of the block's creator that takes it. */
  readonly option: string;
  /** The interface, such as `EnrichmentProvider`. */
  readonly type: string;
  /** The subpath that exports the interface and its built-in implementations. */
  readonly from: string;
  /** Without it the block can't do its job. */
  readonly required: boolean;
  readonly description: string;
  /** An expression that sets it, such as `peopleDataLabsEnrichment({ apiKey })`. */
  readonly example: string;
}

/**
 * Work the block needs run outside a request: a cron calling one of its routes,
 * or a long-running process.
 */
export interface BlockWorker {
  readonly name: string;
  readonly description: string;
  /** The path its cron calls, such as `/api/outbox`. */
  readonly path?: string;
  /** A cron expression, such as `* * * * *` for every minute. */
  readonly schedule?: string;
}

/** What a block needs from the app besides its SQL and client (phase 21). */
export interface BlockWiring {
  readonly env?: readonly BlockEnvKey[];
  readonly providers?: readonly BlockProvider[];
  /**
   * The registry items that hold its routes, without the framework suffix:
   * `outbox-relay` installs `outbox-relay-next` in a Next.js app.
   */
  readonly routes?: readonly string[];
  readonly workers?: readonly BlockWorker[];
}

/** The keys the cron routes check in the `Authorization` header. */
export const CRON_SECRET_ENV: BlockEnvKey = {
  key: "CRON_SECRET",
  description:
    "Server-only: the bearer token the cron routes require (Vercel Cron sends it).",
};

/** The server connection the relay and drain routes use. */
export const DATABASE_URL_ENV: BlockEnvKey = {
  key: "DATABASE_URL",
  description:
    "Server-only: the Postgres connection the registry's queue drain and Stripe processing routes use.",
};
