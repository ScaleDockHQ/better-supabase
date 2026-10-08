import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { JobHandler } from "../jobs/queue.ts";

import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  sha256Hex,
  textOf,
  toInstant,
} from "../shared.ts";

/** What an entry caches: a whole generation, a replayable stream, embeddings, or anything else. */
export type AiCacheKind = "generate" | "stream" | "embed" | "other";

export interface AiCacheEntry<T = unknown> {
  readonly key: string;
  readonly organizationId: string | undefined;
  readonly kind: AiCacheKind;
  readonly model: string | undefined;
  readonly value: T;
  readonly hits: number;
  readonly createdAt: Temporal.Instant;
  readonly lastHitAt: Temporal.Instant | undefined;
  readonly expiresAt: Temporal.Instant;
}

export interface AiCacheSetOptions {
  /** Seconds the entry lives, capped by the module's `maxTtl`. */
  readonly ttl: number;
  /** The tenant the entry belongs to, so `clear` and tenant deletion find it. */
  readonly organizationId?: string;
  readonly kind?: AiCacheKind;
  readonly model?: string;
}

export interface AiCacheOptions extends BlockTemporalOptions {
  /** Calls as the service role: entries hold prompts and outputs. */
  readonly transport: BlockTransport;
  /** The module schema (`sql.modules.ai-cache.schema`), default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface AiCache {
  /** The entry under `key`, or `undefined` when there is none or it expired. Counts a hit. */
  get<T = unknown>(key: string): AsyncResult<AiCacheEntry<T> | undefined>;
  /** Stores or replaces the entry under `key`. `value` must be JSON. */
  set(
    key: string,
    value: unknown,
    options: AiCacheSetOptions,
  ): AsyncResult<Omit<AiCacheEntry<undefined>, "value">>;
  delete(key: string): AsyncResult<boolean>;
  /** Deletes every entry of a tenant, or of a model. Returns how many. */
  clear(filter: {
    readonly organizationId?: string;
    readonly model?: string;
  }): AsyncResult<number>;
  /** Deletes up to `batch` expired entries. Returns how many. */
  purge(options?: { readonly batch?: number }): AsyncResult<number>;
  /** A job handler that runs `purge`; schedule it hourly. */
  purgeJob(options?: { readonly batch?: number }): JobHandler<unknown>;
}

const KINDS: ReadonlySet<string> = new Set([
  "generate",
  "stream",
  "embed",
  "other",
]);

const instant = (value: unknown): Temporal.Instant =>
  value instanceof Date ? toInstant(value) : toInstant(textOf(value));

function entryOf<T>(value: unknown): AiCacheEntry<T> {
  const row = recordOf(value, "ai_cache_entries");
  const kind = textOf(row["kind"]);
  return {
    key: textOf(row["key"]),
    organizationId: optionalText(row["organization_id"]),
    // SAFETY: KINDS holds exactly the AiCacheKind members.
    kind: KINDS.has(kind) ? (kind as AiCacheKind) : "other",
    model: optionalText(row["model"]),
    // SAFETY: the caller stored this value under the key it reads with.
    value: row["value"] as T,
    hits: typeof row["hits"] === "number" ? row["hits"] : 0,
    createdAt: instant(row["created_at"]),
    lastHitAt: optionalInstant(row["last_hit_at"]),
    expiresAt: instant(row["expires_at"]),
  };
}

function canonical(value: unknown): unknown {
  if (value instanceof Uint8Array) {
    let binary = "";
    for (const byte of value) binary += String.fromCodePoint(byte);
    return { $bytes: btoa(binary) };
  }
  if (value instanceof Date) return value.toISOString();
  if (value instanceof URL) return value.href;
  if (Array.isArray(value)) return value.map(canonical);
  if (isRecord(value)) {
    const out: Record<string, unknown> = {};
    for (const key of Object.keys(value).toSorted()) {
      const item = value[key];
      if (item !== undefined && typeof item !== "function")
        out[key] = canonical(item);
    }
    return out;
  }
  return value;
}

/**
 * A cache key for `parts`: SHA-256 of their JSON with object keys sorted, so
 * the same model, prompt and settings give the same key. Bytes count by
 * content and `undefined` fields are left out.
 */
export function cacheKey(parts: unknown): Promise<string> {
  return sha256Hex(JSON.stringify(canonical(parts) ?? null));
}

/** Model responses cached in Postgres with a TTL, read and written as the service role. */
export function createAiCache(options: AiCacheOptions): AiCache {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const purge = (purgeOptions: { readonly batch?: number } = {}) =>
    call("purge_ai_cache", { batch: purgeOptions.batch }, (value) =>
      Number(value ?? 0),
    );
  return {
    get: <T>(key: string) =>
      call("ai_cache_get", { key }, (value) =>
        value === null || value === undefined ? undefined : entryOf<T>(value),
      ),
    set: (key, value, setOptions) =>
      call(
        "ai_cache_set",
        {
          key,
          value,
          ttl: Math.max(1, Math.ceil(setOptions.ttl)),
          tenant: setOptions.organizationId,
          kind: setOptions.kind,
          model: setOptions.model,
        },
        (row) => {
          const { value: _value, ...entry } = entryOf<undefined>(row);
          return entry;
        },
      ),
    delete: (key) =>
      call("ai_cache_delete", { key }, (value) => Number(value ?? 0) > 0),
    clear: (filter) =>
      call(
        "ai_cache_delete",
        { tenant: filter.organizationId, model: filter.model },
        (value) => Number(value ?? 0),
      ),
    purge,
    purgeJob: (jobOptions) => async () => purge(jobOptions).orThrow(),
  };
}
