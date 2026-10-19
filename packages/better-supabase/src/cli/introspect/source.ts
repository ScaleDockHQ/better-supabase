import type { Queryable } from "./typegen.ts";

import { connect } from "../db.ts";
import { CliError } from "../errors.ts";

export type { Queryable };

/** A connection introspection can query, plus how to release it. */
export interface IntrospectionSource {
  readonly queryable: Queryable;
  readonly describe: string;
  /**
   * Set when the schema was replayed into a throwaway database rather than
   * read from the one the app runs on, saying why live checks are skipped.
   */
  readonly replay?: string;
  close(): Promise<void>;
}

const POOL_SIZE = 4;
const STATEMENT_TIMEOUT_MS = 120_000;

/**
 * Leads every introspection query. `pg_stat_statements` keeps a leading
 * comment in its text, so doctor (BS208) can tell the CLI's catalog reads
 * from the app's statements.
 */
export const CLI_QUERY_TAG = "/* better-supabase */";

const tagged = (sql: string): string => `${CLI_QUERY_TAG}\n${sql}`;

/**
 * A small `pg` pool, since introspection issues its queries concurrently. A
 * `connect` that returns a single client gets its queries queued, because one
 * `pg.Client` runs them one at a time.
 */
export async function pgSource(
  url: string,
  open: typeof connect = connect,
  signal?: AbortSignal,
): Promise<IntrospectionSource> {
  const { client, pooled, close, describe } = await open(url, undefined, {
    pool: POOL_SIZE,
    statementTimeout: STATEMENT_TIMEOUT_MS,
    ...(signal ? { signal } : {}),
  });

  if (pooled) {
    return {
      queryable: { query: (sql: string) => client.query(tagged(sql)) },
      close,
      describe,
    };
  }

  let queue: Promise<unknown> = Promise.resolve();

  const queryable: Queryable = {
    query(sql: string) {
      const next = queue.then(() => client.query(tagged(sql)));
      queue = next.catch(() => undefined);

      return next;
    },
  };

  return { queryable, close, describe };
}

export interface ManagementSourceOptions {
  readonly projectRef: string;
  readonly accessToken: string;
  /** Defaults to `https://api.supabase.com`. */
  readonly apiUrl?: string;
  readonly fetch?: typeof fetch;
  /** Cancels in-flight queries (Ctrl-C). */
  readonly signal?: AbortSignal;
}

/**
 * Runs introspection SQL through the Supabase Management API as the
 * read-only database user, so hosted projects need no database password.
 */
export function managementSource(
  options: ManagementSourceOptions,
): IntrospectionSource {
  const base = (options.apiUrl ?? "https://api.supabase.com").replace(
    /\/$/,
    "",
  );

  const doFetch = options.fetch ?? fetch;
  const endpoint = `${base}/v1/projects/${encodeURIComponent(options.projectRef)}/database/query/read-only`;

  const queryable: Queryable = {
    async query(sql: string) {
      const response = await doFetch(endpoint, {
        method: "POST",
        headers: {
          authorization: `Bearer ${options.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({ query: sql }),
        ...(options.signal ? { signal: options.signal } : {}),
      });

      const text = await response.text();

      if (!response.ok) {
        throw new CliError(
          response.status === 401 || response.status === 403
            ? "auth_required"
            : "request_failed",
          `Management API query failed (${response.status}) for project ${options.projectRef}: ${text.slice(0, 500)}`,
        );
      }

      // SAFETY: widens the any from JSON.parse to unknown; the shape is checked below.
      const rows = JSON.parse(text) as unknown;

      if (!Array.isArray(rows)) {
        throw new TypeError(
          `Management API returned an unexpected body for project ${options.projectRef}.`,
        );
      }

      return { rows };
    },
  };

  return {
    queryable,
    describe: `project ${options.projectRef} (Management API)`,
    close: () => Promise.resolve(),
  };
}
