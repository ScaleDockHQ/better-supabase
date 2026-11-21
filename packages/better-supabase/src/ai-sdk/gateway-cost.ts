import type {
  AiChat,
  AiRunRelease,
  AiRunStatus,
} from "../blocks/ai-chat/ai-chat.ts";
import type { JobHandler } from "../blocks/queue/types.ts";
import type { Usage, UsageEntry } from "../blocks/usage/usage.ts";
import type { UsageSource } from "./gateway.ts";

import { isRecord } from "../core/block-helpers.ts";
import { dbError } from "../core/errors.ts";
import { AsyncResult, err, ok } from "../core/result.ts";
import { nowInstant } from "../core/temporal.ts";
import { microUsd } from "./gateway.ts";

const count = (value: number | undefined): number =>
  typeof value === "number" && Number.isFinite(value) && value > 0
    ? Math.round(value)
    : 0;

/**
 * What the AI Gateway reports for one generation, in the units the cost rows
 * keep: micro-USD for money and plain counts for tokens.
 */
export interface GatewayCost {
  /** The gateway's generation id (`gen_...`), for `gatewayCostBackfill`. */
  readonly generationId: string | undefined;
  /**
   * `providerMetadata.gateway.cost`: inference plus the tools the gateway ran.
   * It leaves out other charges such as zero data retention surcharges.
   */
  readonly costMicroUsd: number | undefined;
  /** `providerMetadata.gateway.marketCost`: the market rate for the inference. */
  readonly marketCostMicroUsd: number | undefined;
  readonly inputTokens: number;
  readonly outputTokens: number;
  readonly totalTokens: number;
  /** Input tokens read from the provider's prompt cache. */
  readonly cacheReadTokens: number;
  /** Input tokens written to the provider's prompt cache. */
  readonly cacheWriteTokens: number;
  readonly reasoningTokens: number;
  /**
   * Whether a tenant's own provider key served the call (`credentialType` of
   * the successful provider attempt), or `undefined` when the response has no
   * routing metadata.
   */
  readonly byok: boolean | undefined;
  /** The provider that served the call (`routing.finalProvider`). */
  readonly provider: string | undefined;
}

function gatewayMetadata(source: UsageSource): Record<string, unknown> {
  const metadata =
    source.finalStep?.providerMetadata ?? source.providerMetadata;

  return isRecord(metadata) && isRecord(metadata["gateway"])
    ? metadata["gateway"]
    : {};
}

/** The credential type of the provider attempt that succeeded, if recorded. */
function servedByByok(routing: unknown): boolean | undefined {
  if (!isRecord(routing) || !Array.isArray(routing["modelAttempts"])) {
    return undefined;
  }

  for (const model of routing["modelAttempts"]) {
    if (!isRecord(model) || !Array.isArray(model["providerAttempts"])) {
      continue;
    }

    for (const attempt of model["providerAttempts"]) {
      if (
        isRecord(attempt) &&
        attempt["success"] === true &&
        typeof attempt["credentialType"] === "string"
      ) {
        return attempt["credentialType"] === "byok";
      }
    }
  }

  return undefined;
}

/**
 * The cost and token detail of a finished generation: a `streamText` or
 * `generateText` result, awaited. Unlike `usageOf` it also reads the cache
 * write tokens, the market cost and whether the call used a tenant's own key.
 */
export function gatewayCostOf(source: UsageSource): GatewayCost {
  const usage = source.usage ?? source.totalUsage ?? {};
  const gateway = gatewayMetadata(source);
  const input = count(usage.inputTokens);
  const output = count(usage.outputTokens);
  const routing = gateway["routing"];
  const generationId = gateway["generationId"];
  const provider = isRecord(routing) ? routing["finalProvider"] : undefined;

  return {
    generationId: typeof generationId === "string" ? generationId : undefined,
    costMicroUsd: microUsd(gateway["cost"]),
    marketCostMicroUsd: microUsd(gateway["marketCost"]),
    inputTokens: input,
    outputTokens: output,
    totalTokens: count(usage.totalTokens) || input + output,
    cacheReadTokens: count(usage.inputTokenDetails?.cacheReadTokens),
    cacheWriteTokens: count(usage.inputTokenDetails?.cacheWriteTokens),
    reasoningTokens: count(usage.outputTokenDetails?.reasoningTokens),
    byok: servedByByok(routing),
    provider: typeof provider === "string" ? provider : undefined,
  };
}

/**
 * The `usage` object a run row keeps for a generation (`runs.release` and
 * `runs.setCost` merge it into `ai_runs.usage`). The first four keys match what
 * `runRelease` writes.
 */
export function costUsage(
  cost: GatewayCost,
): Readonly<Record<string, number | string | boolean>> {
  return {
    inputTokens: cost.inputTokens,
    outputTokens: cost.outputTokens,
    totalTokens: cost.totalTokens,
    cachedInputTokens: cost.cacheReadTokens,
    reasoningTokens: cost.reasoningTokens,
    cacheWriteTokens: cost.cacheWriteTokens,
    ...(cost.marketCostMicroUsd === undefined
      ? {}
      : { marketCostMicroUsd: cost.marketCostMicroUsd }),
    ...(cost.byok === undefined ? {} : { byok: cost.byok }),
    ...(cost.provider === undefined ? {} : { provider: cost.provider }),
  };
}

/** What `runs.release` stores for a generation that ended, with the cost detail. */
export function gatewayRunRelease(
  status: AiRunStatus,
  cost?: GatewayCost,
  error?: string,
): AiRunRelease {
  return {
    status,
    ...(cost === undefined ? {} : { usage: costUsage(cost) }),
    ...(cost?.generationId === undefined
      ? {}
      : { generationId: cost.generationId }),
    ...(cost?.costMicroUsd === undefined
      ? {}
      : { costMicroUsd: cost.costMicroUsd }),
    ...(error === undefined ? {} : { error }),
  };
}

/** The usage meters `gatewayCostEntries` writes. */
export interface GatewayCostMeters {
  /** Micro-USD of the gateway's cost. Default `ai.cost`. */
  readonly cost?: string;
  /** Micro-USD at the market rate. Default `ai.market_cost`. */
  readonly marketCost?: string;
  readonly input?: string;
  readonly output?: string;
  readonly cacheRead?: string;
  readonly cacheWrite?: string;
  readonly reasoning?: string;
}

/**
 * The entries to pass to `usage.recordMany` for a generation. Meters with a
 * zero quantity are left out. Pass `countByok: false` to leave a tenant's own
 * key out of the money meters (the tenant pays that provider, not the app);
 * tokens are always recorded.
 */
export function gatewayCostEntries(
  cost: GatewayCost,
  meters: GatewayCostMeters = {},
  options: { readonly countByok?: boolean } = {},
): UsageEntry[] {
  const money = cost.byok !== true || options.countByok === true;

  const entries: UsageEntry[] = [
    { meter: meters.input ?? "ai.input_tokens", quantity: cost.inputTokens },
    { meter: meters.output ?? "ai.output_tokens", quantity: cost.outputTokens },
    {
      meter: meters.cacheRead ?? "ai.cache_read_tokens",
      quantity: cost.cacheReadTokens,
    },
    {
      meter: meters.cacheWrite ?? "ai.cache_write_tokens",
      quantity: cost.cacheWriteTokens,
    },
    {
      meter: meters.reasoning ?? "ai.reasoning_tokens",
      quantity: cost.reasoningTokens,
    },
  ];

  if (money && cost.costMicroUsd !== undefined) {
    entries.push({
      meter: meters.cost ?? "ai.cost",
      quantity: cost.costMicroUsd,
    });
  }

  if (money && cost.marketCostMicroUsd !== undefined) {
    entries.push({
      meter: meters.marketCost ?? "ai.market_cost",
      quantity: cost.marketCostMicroUsd,
    });
  }

  return entries.filter((entry) => (entry.quantity ?? 0) > 0);
}

/** `GatewayGenerationInfo` as far as the backfill reads it. */
export interface GenerationInfo {
  readonly totalCost: number;
  readonly marketCost?: number;
  readonly surchargeCost?: number;
  readonly gatewayCost?: number;
  readonly isByok?: boolean;
  readonly providerName?: string;
  readonly promptTokens?: number;
  readonly completionTokens?: number;
  readonly reasoningTokens?: number;
  readonly cachedTokens?: number;
  readonly cacheCreationTokens?: number;
}

/** The AI Gateway call `gatewayCostBackfill` makes (`gateway` from `ai`). */
export interface GenerationInfoClient {
  getGenerationInfo(params: { id: string }): PromiseLike<GenerationInfo>;
}

/** The payload of a gateway cost backfill job. */
export interface GatewayCostBackfillPayload {
  readonly generationId: string;
  readonly organizationId?: string;
}

/** What `gatewayCostBackfill` returns once it wrote the cost. */
export interface GatewayCostBackfilled {
  readonly generationId: string;
  readonly costMicroUsd: number;
  readonly marketCostMicroUsd: number | undefined;
  /** `true` when the cost was left unknown because the job ran out of time. */
  readonly gaveUp: boolean;
}

export interface GatewayCostBackfillOptions {
  /** The chat block with a service transport. */
  readonly chats: Pick<AiChat, "runs">;
  readonly gateway: GenerationInfoClient;
  /**
   * The usage block with a service transport; with it the tenant's meters are
   * written.
   */
  readonly usage?: Pick<Usage, "recordMany">;
  readonly meters?: GatewayCostMeters;
  /** Count a tenant's own key toward the money meters. Default `false`. */
  readonly countByok?: boolean;
  /**
   * How long after the job was enqueued a generation the gateway still doesn't
   * know is given up on (the job then returns instead of throwing). Default 24
   * hours.
   */
  readonly giveUpAfterSeconds?: number;
  /** Called when the job gives up, with the generation id. */
  readonly onGiveUp?: (generationId: string) => void;
}

/** A generation the gateway can't answer for yet; the queue retries the job. */
export class GatewayCostPendingError extends Error {
  readonly generationId: string;

  constructor(generationId: string, cause?: unknown) {
    super(`The gateway has no cost for ${generationId} yet.`, { cause });
    this.name = "GatewayCostPendingError";
    this.generationId = generationId;
  }
}

const statusOf = (error: unknown): number | undefined =>
  isRecord(error) && typeof error["statusCode"] === "number"
    ? error["statusCode"]
    : undefined;

/**
 * A job handler that looks up a generation in the AI Gateway after a call that
 * had no cost in its response, and writes the cost, the market cost and the
 * cache and reasoning tokens to the run and, with `usage`, to the tenant's
 * meters (once per generation, so a retry or an earlier write counts once).
 *
 * The gateway ingests usage after the response, so a lookup can answer 404 for
 * a short while: the handler throws `GatewayCostPendingError` and the queue
 * retries it. After `giveUpAfterSeconds` it returns with `gaveUp: true` and
 * writes nothing, so a generation the gateway never recorded doesn't retry
 * forever.
 */
export function gatewayCostBackfill(
  options: GatewayCostBackfillOptions,
): JobHandler<GatewayCostBackfillPayload> {
  const giveUpAfter = options.giveUpAfterSeconds ?? 24 * 60 * 60;

  return async (payload, job) => {
    let info: GenerationInfo;

    try {
      info = await options.gateway.getGenerationInfo({
        id: payload.generationId,
      });
    } catch (error) {
      if (statusOf(error) !== 404) {
        throw error;
      }

      const age =
        nowInstant().epochMilliseconds - job.enqueuedAt.epochMilliseconds;

      if (age < giveUpAfter * 1000) {
        throw new GatewayCostPendingError(payload.generationId, error);
      }

      options.onGiveUp?.(payload.generationId);

      return {
        generationId: payload.generationId,
        costMicroUsd: 0,
        marketCostMicroUsd: undefined,
        gaveUp: true,
      } satisfies GatewayCostBackfilled;
    }

    const cost: GatewayCost = {
      generationId: payload.generationId,
      costMicroUsd: microUsd(info.totalCost) ?? 0,
      marketCostMicroUsd: microUsd(info.marketCost),
      inputTokens: count(info.promptTokens),
      outputTokens: count(info.completionTokens),
      totalTokens: count(info.promptTokens) + count(info.completionTokens),
      cacheReadTokens: count(info.cachedTokens),
      cacheWriteTokens: count(info.cacheCreationTokens),
      reasoningTokens: count(info.reasoningTokens),
      byok: info.isByok,
      provider: info.providerName,
    };

    await options.chats.runs
      .setCost({
        generationId: payload.generationId,
        costMicroUsd: cost.costMicroUsd ?? 0,
        usage: {
          ...costUsage(cost),
          ...(info.surchargeCost === undefined
            ? {}
            : { surchargeMicroUsd: microUsd(info.surchargeCost) ?? 0 }),
          ...(info.gatewayCost === undefined
            ? {}
            : { gatewayCostMicroUsd: microUsd(info.gatewayCost) ?? 0 }),
        },
      })
      .orThrow();

    if (options.usage !== undefined && payload.organizationId !== undefined) {
      const entries = gatewayCostEntries(cost, options.meters, {
        ...(options.countByok === undefined
          ? {}
          : { countByok: options.countByok }),
      }).filter(
        (entry) =>
          entry.meter === (options.meters?.cost ?? "ai.cost") ||
          entry.meter === (options.meters?.marketCost ?? "ai.market_cost"),
      );

      if (entries.length > 0) {
        await options.usage
          .recordMany({
            organizationId: payload.organizationId,
            entries,
            idempotencyKey: `ai-cost:${payload.generationId}`,
            source: "ai:gateway",
          })
          .orThrow();
      }
    }

    return {
      generationId: payload.generationId,
      costMicroUsd: cost.costMicroUsd ?? 0,
      marketCostMicroUsd: cost.marketCostMicroUsd,
      gaveUp: false,
    } satisfies GatewayCostBackfilled;
  };
}

/** The credit balance of the gateway team, in micro-USD. */
export interface GatewayCredits {
  readonly balanceMicroUsd: number;
  readonly totalUsedMicroUsd: number;
}

/** The AI Gateway call the credits check makes (`gateway` from `ai`). */
export interface GatewayCreditsClient {
  getCredits(): PromiseLike<{
    readonly balance: string;
    readonly totalUsed: string;
  }>;
}

/**
 * The gateway team's credit balance. The balance belongs to the whole team, so
 * one organization's calls can't tell whose credits ran out: check it before a
 * call to fail early, and from a schedule to alert someone.
 */
export function gatewayCredits(
  gateway: GatewayCreditsClient,
): AsyncResult<GatewayCredits> {
  return new AsyncResult(
    (async () => {
      try {
        const credits = await gateway.getCredits();
        const balance = microUsd(credits.balance);
        const used = microUsd(credits.totalUsed);

        if (balance === undefined || used === undefined) {
          return err(
            dbError(
              "unexpected",
              "The gateway returned a credit balance that is not a number.",
            ),
          );
        }

        return ok({ balanceMicroUsd: balance, totalUsedMicroUsd: used });
      } catch (error) {
        return err(
          dbError(
            "network",
            error instanceof Error
              ? error.message
              : "The gateway credits lookup failed.",
          ),
        );
      }
    })(),
  );
}

export interface GatewayCreditsCheckOptions {
  readonly gateway: GatewayCreditsClient;
  /** Fail below this balance, in micro-USD. Default 0 (an empty balance). */
  readonly minimumMicroUsd?: number;
}

/**
 * Whether the gateway team has credits left: `ok` with the balance, or
 * `quota_exceeded` for the meter `gateway_credits` when the balance is at or
 * below `minimumMicroUsd`. Call it before a call that must not start without
 * credits; the lookup is one request, so cache it for a few seconds.
 */
export function checkGatewayCredits(
  options: GatewayCreditsCheckOptions,
): AsyncResult<GatewayCredits> {
  const minimum = options.minimumMicroUsd ?? 0;

  return gatewayCredits(options.gateway).andThen((credits) =>
    Promise.resolve(
      credits.balanceMicroUsd > minimum
        ? ok(credits)
        : err(
            dbError("quota_exceeded", "The AI Gateway credits are used up.", {
              meter: "gateway_credits",
              limit: minimum,
            }),
          ),
    ),
  );
}

/**
 * A job handler for a schedule: reads the balance and calls `onLow` when it is
 * at or below `minimumMicroUsd`. It returns the credits so the run shows them.
 */
export function creditsMonitor(
  options: GatewayCreditsCheckOptions & {
    readonly onLow: (credits: GatewayCredits) => unknown;
  },
): JobHandler<unknown> {
  return async () => {
    const credits = await gatewayCredits(options.gateway).orThrow();

    if (credits.balanceMicroUsd <= (options.minimumMicroUsd ?? 0)) {
      await options.onLow(credits);
    }

    return credits;
  };
}
