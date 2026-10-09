import type { LanguageModelMiddleware } from "ai";

import { simulateReadableStream } from "ai";

import type { AiCache } from "../../blocks/ai-cache/ai-cache.ts";
import type { DbError } from "../../core/errors.ts";

import { cacheKey } from "../../blocks/ai-cache/ai-cache.ts";
import { isRecord } from "../../blocks/shared.ts";

type WrapGenerate = NonNullable<LanguageModelMiddleware["wrapGenerate"]>;
type WrapStream = NonNullable<LanguageModelMiddleware["wrapStream"]>;
type GenerateResult = Awaited<ReturnType<WrapGenerate>>;
type StreamResult = Awaited<ReturnType<WrapStream>>;
type StreamPart =
  StreamResult["stream"] extends ReadableStream<infer P> ? P : never;

/** The call `cacheMiddleware` derives a key from. */
export type CacheCall = Parameters<WrapGenerate>[0];

export interface CacheMiddlewareOptions {
  /** The AI cache block with a service transport. */
  readonly cache: Pick<AiCache, "get" | "set">;
  /** Seconds an entry lives, capped by the module's `maxTtl`. */
  readonly ttl: number;
  /** Keeps tenants' entries apart and lets `clear` and tenant deletion find them. */
  readonly organizationId?: string;
  /**
   * What the key covers. Defaults to the provider, the model id and the call
   * options without the abort signal and headers.
   */
  readonly key?: (call: CacheCall) => unknown;
  /** Skips the cache for a call, such as one with a high temperature. */
  readonly when?: (call: CacheCall) => boolean;
  /** Pacing for replayed streams, in milliseconds; no delay by default. */
  readonly replay?: {
    readonly initialDelayInMs?: number | null;
    readonly chunkDelayInMs?: number | null;
  };
  /** Called when the cache can't be read or written; the call still runs. */
  readonly onError?: (error: DbError) => void;
}

const BYTES = "$bytes";
const DATE = "$date";
const URL_TAG = "$url";

function encode(value: unknown): unknown {
  if (value instanceof Date) return { [DATE]: value.toISOString() };
  if (value instanceof Uint8Array) {
    let binary = "";
    for (const byte of value) binary += String.fromCodePoint(byte);
    return { [BYTES]: btoa(binary) };
  }
  if (value instanceof URL) return { [URL_TAG]: value.href };
  if (Array.isArray(value)) return value.map(encode);
  if (isRecord(value)) {
    const out: Record<string, unknown> = {};
    for (const [key, item] of Object.entries(value))
      if (item !== undefined && typeof item !== "function")
        out[key] = encode(item);
    return out;
  }
  return value;
}

function decode(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(decode);
  if (!isRecord(value)) return value;
  const keys = Object.keys(value);
  if (keys.length === 1 && typeof value[DATE] === "string")
    return new Date(value[DATE]);
  if (keys.length === 1 && typeof value[URL_TAG] === "string")
    return new URL(value[URL_TAG]);
  if (keys.length === 1 && typeof value[BYTES] === "string")
    return Uint8Array.from(
      atob(value[BYTES]),
      (char) => char.codePointAt(0) ?? 0,
    );
  const out: Record<string, unknown> = {};
  for (const [key, item] of Object.entries(value)) out[key] = decode(item);
  return out;
}

const defaultKey = (call: CacheCall): unknown => {
  const { abortSignal: _signal, headers: _headers, ...params } = call.params;
  return {
    provider: call.model.provider,
    model: call.model.modelId,
    params,
  };
};

/**
 * A `wrapLanguageModel` middleware that answers repeated calls from the AI
 * cache block. A cached generation is returned as is, and a cached stream is
 * replayed through `simulateReadableStream`. Calls that end in an error are
 * never cached, and a cache that fails to answer only costs the lookup.
 */
export function cacheMiddleware(
  options: CacheMiddlewareOptions,
): LanguageModelMiddleware {
  const keyOf = async (
    call: CacheCall,
    type: "generate" | "stream",
  ): Promise<string> =>
    cacheKey({
      type,
      tenant: options.organizationId ?? null,
      parts: (options.key ?? defaultKey)(call),
    });

  const read = async (key: string): Promise<unknown> => {
    const entry = await options.cache.get(key);
    if (!entry.ok) {
      options.onError?.(entry.error);
      return undefined;
    }
    return entry.data?.value;
  };

  const write = async (
    key: string,
    value: unknown,
    call: CacheCall,
    kind: "generate" | "stream",
  ): Promise<void> => {
    const saved = await options.cache.set(key, encode(value), {
      ttl: options.ttl,
      kind,
      model: `${call.model.provider}/${call.model.modelId}`,
      ...(options.organizationId === undefined
        ? {}
        : { organizationId: options.organizationId }),
    });
    if (!saved.ok) options.onError?.(saved.error);
  };

  return {
    specificationVersion: "v4",
    wrapGenerate: async (call) => {
      if (options.when?.(call) === false) return call.doGenerate();
      const key = await keyOf(call, "generate");
      const cached = await read(key);
      if (isRecord(cached)) {
        // SAFETY: the entry was written below from a GenerateResult of this key.
        return decode(cached) as GenerateResult;
      }
      const result = await call.doGenerate();
      if (result.finishReason.unified !== "error") {
        const { request: _request, ...rest } = result;
        const response =
          rest.response === undefined
            ? undefined
            : { ...rest.response, body: undefined, headers: undefined };
        await write(key, { ...rest, response }, call, "generate");
      }
      return result;
    },
    wrapStream: async (call) => {
      if (options.when?.(call) === false) return call.doStream();
      const key = await keyOf(call, "stream");
      const cached = await read(key);
      if (isRecord(cached) && Array.isArray(cached["parts"])) {
        // SAFETY: the parts were written below from this key's stream.
        const parts = decode(cached["parts"]) as StreamPart[];
        return {
          stream: simulateReadableStream({
            chunks: parts,
            initialDelayInMs: options.replay?.initialDelayInMs ?? null,
            chunkDelayInMs: options.replay?.chunkDelayInMs ?? null,
          }),
        };
      }
      const result = await call.doStream();
      const parts: StreamPart[] = [];
      let failed = false;
      const stream = result.stream.pipeThrough(
        new TransformStream<StreamPart, StreamPart>({
          transform(part, controller) {
            if (
              part.type === "error" ||
              (part.type === "finish" && part.finishReason.unified === "error")
            )
              failed = true;
            if (part.type !== "raw") parts.push(part);
            controller.enqueue(part);
          },
          async flush() {
            if (!failed) await write(key, { parts }, call, "stream");
          },
        }),
      );
      return { ...result, stream };
    },
  };
}
