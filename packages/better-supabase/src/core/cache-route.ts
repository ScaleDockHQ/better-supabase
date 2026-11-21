import type { SchemaMeta, TableMeta } from "../schema/types.ts";
import type { CacheAdapter, CacheTarget } from "./cache.ts";
import type { ProblemFormat } from "./problem.ts";
import type { VerifyOptions } from "./signatures.ts";

import { invalidationTargets } from "../ir/tables.ts";
import { toApp } from "../schema/casing.ts";
import { rowKey } from "./cache.ts";
import { dbError } from "./errors.ts";
import { methodNotAllowed, problemResponse } from "./problem.ts";
import { verifySharedSecret, verifyWebhook } from "./signatures.ts";

export interface CacheRouteOptions {
  /** The definition, for the table names, primary keys and tenant columns. */
  readonly betterSupabase: { readonly meta: SchemaMeta };
  /** Adapters to expire, such as `nextCache()` or `vercelCdnCache(...)`. */
  readonly caches: readonly CacheAdapter[];
  /**
   * Standard Webhooks secret (`whsec_...`), or several while you roll it. It
   * verifies deliveries signed with a `webhook-signature` header: the webhooks
   * block and the outbox relay.
   */
  readonly secret?: string | readonly string[] | undefined;
  /**
   * Bearer token for Supabase Database Webhooks and the `notify_cache` trigger
   * from `cacheInvalidationSql`, which send it in `Authorization`.
   */
  readonly bearer?: string | undefined;
  /** Replay protection and clock options for the signed path. */
  readonly verify?: VerifyOptions | undefined;
  /** Rewrites the Problem Details body of an error. */
  readonly problem?: ProblemFormat | undefined;
}

interface Change {
  readonly table: TableMeta;
  readonly deleted: boolean;
  readonly ids: readonly string[];
  /** `undefined` is a change without a tenant, which expires every tenant. */
  readonly tenants: readonly (string | undefined)[];
}

type Json = Readonly<Record<string, unknown>>;

function isObject(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function findTable(
  meta: SchemaMeta,
  name: string,
  schema: string | undefined,
): TableMeta | undefined {
  return Object.values(meta.tables).find(
    (table) =>
      table.key === name ||
      (table.name === name &&
        (schema === undefined || table.schema === schema)),
  );
}

function tenantOf(table: TableMeta, row: Json): string | undefined {
  const column = table.flags.tenant;
  const value = column === undefined ? undefined : row[column];

  return typeof value === "string" || typeof value === "number"
    ? String(value)
    : undefined;
}

/** A Supabase Database Webhook (`INSERT`, `UPDATE` or `DELETE` with rows). */
function fromDatabaseWebhook(
  meta: SchemaMeta,
  payload: Json,
): Change | undefined {
  const { type, table: name, schema, record, old_record: oldRecord } = payload;

  if (
    (type !== "INSERT" && type !== "UPDATE" && type !== "DELETE") ||
    typeof name !== "string" ||
    typeof schema !== "string"
  ) {
    return undefined;
  }

  const table = findTable(meta, name, schema);

  if (!table) {
    return undefined;
  }

  const rows = [record, oldRecord]
    .filter(isObject)
    .map((row) => toApp(table, row));

  return {
    table,
    deleted: type === "DELETE",
    ids: [...new Set(rows.flatMap((row) => rowKey(table, row) ?? []))],
    tenants: [...new Set(rows.map((row) => tenantOf(table, row)))],
  };
}

/** The `notify_cache` envelope: `{ table, schema?, op?, ids?, tenants? }`. */
function fromEnvelope(meta: SchemaMeta, payload: Json): Change | undefined {
  const { table: name, schema, op, ids, tenants, tenant } = payload;

  if (typeof name !== "string") {
    return undefined;
  }

  const table = findTable(
    meta,
    name,
    typeof schema === "string" ? schema : undefined,
  );

  if (!table) {
    return undefined;
  }

  const listed = Array.isArray(tenants)
    ? tenants.map((value) =>
        typeof value === "string" || typeof value === "number"
          ? String(value)
          : undefined,
      )
    : [typeof tenant === "string" ? tenant : undefined];

  return {
    table,
    deleted: typeof op === "string" && op.toUpperCase() === "DELETE",
    ids: Array.isArray(ids)
      ? [
          ...new Set(
            ids.flatMap((id) =>
              typeof id === "string" || typeof id === "number"
                ? String(id)
                : [],
            ),
          ),
        ]
      : [],
    tenants: [...new Set(listed.length === 0 ? [undefined] : listed)],
  };
}

function changeOf(meta: SchemaMeta, payload: unknown): Change | undefined {
  if (!isObject(payload)) {
    return undefined;
  }

  // CloudEvents from the outbox carry the envelope in `data`.
  const inner = isObject(payload["data"]) ? payload["data"] : payload;

  return fromDatabaseWebhook(meta, inner) ?? fromEnvelope(meta, inner);
}

/** One target per tenant of the change. */
function cacheTargetsOfChange(meta: SchemaMeta, change: Change): CacheTarget[] {
  const key = change.table.key;

  return change.tenants.map((tenant) => ({
    table: key,
    tables: change.deleted ? invalidationTargets(meta, key) : [key],
    ids: change.ids,
    ...(tenant === undefined ? {} : { tenant }),
  }));
}

/**
 * A `POST` handler that expires cache tags for a write made outside the app:
 * SQL, `pg_cron` or another service. It accepts a signed delivery (Standard
 * Webhooks: the webhooks block, the outbox relay), or a Supabase Database
 * Webhook or `notify_cache` trigger call with a bearer token, and hands the
 * table, row ids and tenant to `caches`. A payload for a table the definition
 * doesn't know answers 200 and expires nothing. When an adapter throws, the
 * route answers 502 so the sender retries.
 *
 * ```ts
 * export const POST = cacheRoute({
 *   betterSupabase,
 *   caches: [nextCache()],
 *   secret: process.env.BETTER_SUPABASE_CACHE_WEBHOOK_SECRET,
 *   bearer: process.env.BETTER_SUPABASE_CACHE_WEBHOOK_BEARER,
 * });
 * ```
 */
export function cacheRoute(
  options: CacheRouteOptions,
): (request: Request) => Promise<Response> {
  const { meta } = options.betterSupabase;

  const secrets =
    typeof options.secret === "string" ? [options.secret] : options.secret;

  if ((secrets === undefined || secrets.length === 0) && !options.bearer) {
    throw new TypeError("cacheRoute needs a secret, a bearer token or both");
  }

  const refuse = (message: string, request: Request): Response =>
    problemResponse(dbError("unauthorized", message), {
      instance: new URL(request.url).pathname,
      format: options.problem,
    });

  /** The parsed body, or a response that refuses the request. */
  const authorize = async (
    request: Request,
  ): Promise<{ readonly payload: unknown } | Response> => {
    const signed =
      secrets !== undefined &&
      secrets.length > 0 &&
      request.headers.has("webhook-signature");

    if (signed) {
      const verified = await verifyWebhook(request, secrets, options.verify);

      return verified.error
        ? problemResponse(verified.error, {
            instance: new URL(request.url).pathname,
            format: options.problem,
          })
        : { payload: verified.data.payload };
    }

    if (options.bearer && verifySharedSecret(request, options.bearer)) {
      try {
        return { payload: await request.json() };
      } catch {
        return problemResponse(
          dbError("invalid_request", "The body is not JSON"),
          { instance: new URL(request.url).pathname, format: options.problem },
        );
      }
    }

    return refuse(
      "The cache route needs a signed delivery or its bearer",
      request,
    );
  };

  return async (request) => {
    if (request.method !== "POST") {
      return methodNotAllowed(["POST"]);
    }

    const checked = await authorize(request);

    if (checked instanceof Response) {
      return checked;
    }

    const items = Array.isArray(checked.payload)
      ? checked.payload
      : [checked.payload];

    const targets = items.flatMap((item) => {
      const change = changeOf(meta, item);

      return change ? cacheTargetsOfChange(meta, change) : [];
    });

    try {
      for (const target of targets) {
        await Promise.all(
          options.caches.map(async (cache) => {
            await cache.invalidate(target);
          }),
        );
      }
    } catch {
      return Response.json(
        { error: "cache invalidation failed" },
        { status: 502 },
      );
    }

    return Response.json({ invalidated: targets.length });
  };
}
