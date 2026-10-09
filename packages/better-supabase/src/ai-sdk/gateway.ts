import type { JSONValue, LanguageModelUsage } from "ai";

import type {
  AiChat,
  AiModelInput,
  AiRunRelease,
  AiRunStatus,
} from "../blocks/ai-chat/ai-chat.ts";
import type { JobHandler } from "../blocks/jobs/queue.ts";
import type { Usage, UsageEntry, UsageStatus } from "../blocks/usage/usage.ts";
import type { DbError } from "../core/errors.ts";

import { isRecord } from "../core/block-helpers.ts";
import { dbError } from "../core/errors.ts";
import { problemResponse } from "../core/problem.ts";
import { nowInstant } from "../core/temporal.ts";

/** Who a generation is for, as the AI Gateway reports spend. */
export interface GatewayContext {
  readonly userId?: string;
  readonly organizationId?: string;
  readonly chatId?: string;
  /** What the generation is for, such as `chat` or `summary`. */
  readonly feature?: string;
}

/** The AI Gateway's own options (`providerOptions.gateway`). */
export type GatewayOptions = { readonly [key: string]: JSONValue | undefined };

/**
 * `providerOptions` for `streamText` and agents that attribute the spend in
 * the AI Gateway: `user` is the user id, and `tags` name the tenant, the chat
 * and the feature. `extra` adds gateway options such as `order` or
 * `zeroDataRetention`; its `tags` are appended.
 */
export function gatewayOptions(
  context: GatewayContext,
  extra: GatewayOptions = {},
): { readonly gateway: GatewayOptions } {
  const tags: string[] = [];
  if (context.organizationId !== undefined)
    tags.push(`org:${context.organizationId}`);
  if (context.chatId !== undefined) tags.push(`chat:${context.chatId}`);
  if (context.feature !== undefined) tags.push(`feature:${context.feature}`);
  const more = extra["tags"];
  if (Array.isArray(more))
    for (const tag of more) if (typeof tag === "string") tags.push(tag);
  return {
    gateway: {
      ...extra,
      ...(context.userId === undefined ? {} : { user: context.userId }),
      ...(tags.length === 0 ? {} : { tags }),
    },
  };
}

/** Token counts and the gateway's cost of one generation. */
export interface AiUsage {
  readonly inputTokens: number;
  readonly outputTokens: number;
  readonly totalTokens: number;
  readonly cachedInputTokens: number;
  readonly reasoningTokens: number;
  /** The gateway's generation id, for `costBackfill` when the cost isn't known yet. */
  readonly generationId: string | undefined;
  /** The cost in millionths of a US dollar, when the gateway reported it. */
  readonly costMicroUsd: number | undefined;
}

/** What `usageOf` reads: a `streamText` or `generateText` result, awaited. */
export interface UsageSource {
  readonly totalUsage?: Partial<LanguageModelUsage> | undefined;
  readonly usage?: Partial<LanguageModelUsage> | undefined;
  readonly providerMetadata?: unknown;
}

const count = (value: number | undefined): number =>
  typeof value === "number" && Number.isFinite(value) ? value : 0;

/** Parses a USD amount (`"0.00042"` or a number) into micro-USD. */
function microUsd(value: unknown): number | undefined {
  const amount =
    typeof value === "number"
      ? value
      : typeof value === "string" && value.trim() !== ""
        ? Number(value)
        : Number.NaN;
  return Number.isFinite(amount) && amount >= 0
    ? Math.round(amount * 1_000_000)
    : undefined;
}

/** The usage of a finished generation, with the gateway's cost when it has one. */
export function usageOf(source: UsageSource): AiUsage {
  const usage = source.totalUsage ?? source.usage ?? {};
  const input = count(usage.inputTokens);
  const output = count(usage.outputTokens);
  const gateway =
    isRecord(source.providerMetadata) &&
    isRecord(source.providerMetadata["gateway"])
      ? source.providerMetadata["gateway"]
      : {};
  const generationId = gateway["generationId"];
  return {
    inputTokens: input,
    outputTokens: output,
    totalTokens: count(usage.totalTokens) || input + output,
    cachedInputTokens: count(usage.inputTokenDetails?.cacheReadTokens),
    reasoningTokens: count(usage.outputTokenDetails?.reasoningTokens),
    generationId: typeof generationId === "string" ? generationId : undefined,
    costMicroUsd: microUsd(gateway["cost"]),
  };
}

/** What `runs.release` stores for a generation that ended. */
export function runRelease(
  status: AiRunStatus,
  usage?: AiUsage,
  error?: string,
): AiRunRelease {
  return {
    status,
    ...(usage === undefined
      ? {}
      : {
          usage: {
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            totalTokens: usage.totalTokens,
            cachedInputTokens: usage.cachedInputTokens,
            reasoningTokens: usage.reasoningTokens,
          },
        }),
    ...(usage?.generationId === undefined
      ? {}
      : { generationId: usage.generationId }),
    ...(usage?.costMicroUsd === undefined
      ? {}
      : { costMicroUsd: usage.costMicroUsd }),
    ...(error === undefined ? {} : { error }),
  };
}

/** The usage meters `usageEntries` writes, by default `ai.input_tokens` and `ai.output_tokens`. */
export interface AiUsageMeters {
  readonly input?: string;
  readonly output?: string;
  /** Micro-USD; left out unless named. */
  readonly cost?: string;
}

/** The entries to pass to `usage.recordMany` for a generation. */
export function usageEntries(
  usage: AiUsage,
  meters: AiUsageMeters = {},
): UsageEntry[] {
  const entries: UsageEntry[] = [
    { meter: meters.input ?? "ai.input_tokens", quantity: usage.inputTokens },
    {
      meter: meters.output ?? "ai.output_tokens",
      quantity: usage.outputTokens,
    },
  ];
  if (meters.cost !== undefined && usage.costMicroUsd !== undefined)
    entries.push({ meter: meters.cost, quantity: usage.costMicroUsd });
  return entries.filter((entry) => (entry.quantity ?? 0) > 0);
}

/**
 * A 429 Problem Details response for a quota or rate limit: pass the
 * `quota_exceeded` or `rate_limited` error a block returned, or the
 * `UsageStatus` of a meter with nothing left. It carries `Retry-After`.
 */
export function problem429(
  decision: DbError | UsageStatus,
  now: Temporal.Instant = nowInstant(),
): Response {
  if ("kind" in decision) return problemResponse(decision);
  const retryAfter = Math.max(
    1,
    Math.ceil(now.until(decision.resetsAt).total("seconds")),
  );
  return problemResponse(
    dbError("quota_exceeded", `The ${decision.meter} quota is used up.`, {
      meter: decision.meter,
      ...(decision.limit === undefined ? {} : { limit: decision.limit }),
      retryAfter,
    }),
  );
}

/**
 * The quota check `createAssistant` runs before a generation: the error when
 * `meter` has nothing left for the tenant, otherwise `undefined`.
 */
export function usageQuota(
  usage: Pick<Usage, "current">,
  meter: string,
): (organizationId: string) => Promise<DbError | undefined> {
  return async (organizationId) => {
    const status = await usage.current(organizationId, meter);
    if (!status.ok) return status.error;
    const { remaining, limit } = status.data;
    if (remaining === undefined || remaining > 0) return;
    const retryAfter = Math.max(
      1,
      Math.ceil(nowInstant().until(status.data.resetsAt).total("seconds")),
    );
    return dbError("quota_exceeded", `The ${meter} quota is used up.`, {
      meter,
      ...(limit === undefined ? {} : { limit }),
      retryAfter,
    });
  };
}

/** The AI Gateway calls the job handlers make (`gateway` from `ai`). */
export interface GatewayClient {
  getGenerationInfo(params: { id: string }): PromiseLike<{
    readonly totalCost: number;
    readonly model?: string;
    readonly promptTokens?: number;
    readonly completionTokens?: number;
  }>;
  getAvailableModels(): PromiseLike<{
    readonly models: readonly GatewayModelEntry[];
  }>;
}

/** One model of `gateway.getAvailableModels()`. */
export interface GatewayModelEntry {
  readonly id: string;
  readonly name: string;
  readonly description?: string | null;
  readonly pricing?: Readonly<Record<string, string | undefined>> | null;
  readonly modelType?: string | null;
}

/** The payload of a cost backfill job. */
export interface CostBackfillPayload {
  readonly generationId: string;
  /** With `usage` and `meter`, the cost is also recorded on the tenant's meter. */
  readonly organizationId?: string;
}

export interface CostBackfillOptions {
  /** The chat block with a service transport. */
  readonly chats: Pick<AiChat, "runs">;
  readonly gateway: Pick<GatewayClient, "getGenerationInfo">;
  readonly usage?: Pick<Usage, "record">;
  /** The micro-USD meter, such as `ai.cost`. */
  readonly meter?: string;
}

/**
 * A job handler that looks up a generation's cost in the AI Gateway and
 * writes it to the run (`runs.setCost`). Enqueue it when `usageOf` found no
 * cost; it throws so the queue retries while the gateway doesn't know it yet.
 */
export function costBackfill(
  options: CostBackfillOptions,
): JobHandler<CostBackfillPayload> {
  return async (payload) => {
    const info = await options.gateway.getGenerationInfo({
      id: payload.generationId,
    });
    const cost = microUsd(info.totalCost) ?? 0;
    await options.chats.runs
      .setCost(payload.generationId, cost, {
        ...(info.promptTokens === undefined
          ? {}
          : { inputTokens: info.promptTokens }),
        ...(info.completionTokens === undefined
          ? {}
          : { outputTokens: info.completionTokens }),
      })
      .orThrow();
    if (
      options.usage !== undefined &&
      options.meter !== undefined &&
      payload.organizationId !== undefined &&
      cost > 0
    )
      await options.usage
        .record(payload.organizationId, options.meter, {
          quantity: cost,
          idempotencyKey: `ai-cost:${payload.generationId}`,
          source: "ai:gateway",
        })
        .orThrow();
    return cost;
  };
}

export interface ModelCatalogRefreshOptions {
  /** The chat block with a service transport. */
  readonly chats: Pick<AiChat, "models">;
  readonly gateway: Pick<GatewayClient, "getAvailableModels">;
  /** Keeps a model; defaults to language models. */
  readonly filter?: (model: GatewayModelEntry) => boolean;
  /** Plans per model id, for models only some plans may use. */
  readonly plans?: (model: GatewayModelEntry) => readonly string[] | undefined;
  /** Deletes catalog rows the gateway no longer lists. Defaults to false. */
  readonly prune?: boolean;
}

const isLanguageModel = (model: GatewayModelEntry): boolean =>
  model.modelType === undefined ||
  model.modelType === null ||
  model.modelType === "language";

/** The catalog row for a gateway model. */
export function modelInputOf(
  model: GatewayModelEntry,
  plans?: readonly string[],
): AiModelInput {
  const pricing: Record<string, string> = {};
  for (const [key, value] of Object.entries(model.pricing ?? {}))
    if (typeof value === "string") pricing[key] = value;
  return {
    id: model.id,
    provider: model.id.split("/", 1)[0] ?? "gateway",
    name: model.name,
    pricing,
    capabilities: {
      ...(model.modelType ? { modelType: model.modelType } : {}),
      ...(model.description ? { description: model.description } : {}),
    },
    ...(plans === undefined ? {} : { plans }),
  };
}

/**
 * A job handler that copies the AI Gateway's model list into the chat
 * block's catalog (`models.upsert`); schedule it daily.
 */
export function modelCatalogRefresh(
  options: ModelCatalogRefreshOptions,
): JobHandler<unknown> {
  const keep = options.filter ?? isLanguageModel;
  return async () => {
    const { models } = await options.gateway.getAvailableModels();
    const rows = models
      .filter(keep)
      .map((model) => modelInputOf(model, options.plans?.(model)));
    return options.chats.models
      .upsert(rows, { prune: options.prune ?? false })
      .orThrow();
  };
}
