import type { Queryable } from "./typegen.ts";

import { connect } from "../db.ts";

export type { Queryable };

/** A connection introspection can query, plus how to release it. */
export interface IntrospectionSource {
  readonly queryable: Queryable;
  readonly describe: string;
  close(): Promise<void>;
}

/**
 * A `pg` connection. Typegen issues its queries concurrently; one `pg.Client`
 * must run them one at a time, so calls are queued.
 */
export async function pgSource(url: string): Promise<IntrospectionSource> {
  const { client, close, describe } = await connect(url);
  let queue: Promise<unknown> = Promise.resolve();
  const queryable: Queryable = {
    query(sql: string) {
      const next = queue.then(() => client.query(sql));
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
      });
      const text = await response.text();
      if (!response.ok) {
        throw new Error(
          `Management API query failed (${response.status}) for project ${options.projectRef}: ${text.slice(0, 500)}`,
        );
      }
      // SAFETY: widens the any from JSON.parse to unknown; the shape is checked below.
      const rows = JSON.parse(text) as unknown;
      if (!Array.isArray(rows)) {
        throw new Error(
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
