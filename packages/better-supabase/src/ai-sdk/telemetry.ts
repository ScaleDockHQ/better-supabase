import type { Telemetry } from "ai";

import type { JobHandler } from "../blocks/jobs/queue.ts";
import type { Usage, UsageEntry } from "../blocks/usage/usage.ts";
import type { DbError } from "../core/errors.ts";

import { isRecord } from "../core/block-helpers.ts";
import { nowInstant } from "../core/temporal.ts";

/** The usage meters `meterTelemetry` writes. */
export interface TelemetryMeters {
  /** Default `ai.input_tokens`. */
  readonly input?: string;
  /** Default `ai.output_tokens`. */
  readonly output?: string;
  /** Default `ai.embedding_tokens`. */
  readonly embedding?: string;
  /** Default `ai.rerank_calls`. */
  readonly rerank?: string;
}

/** What `meterTelemetry` reads from the event that starts an operation. */
export interface TelemetryStart {
  readonly callId: string;
  readonly operationId: string;
  readonly provider?: string;
  readonly modelId?: string;
  readonly functionId?: string;
  readonly runtimeContext?: unknown;
  readonly providerOptions?: unknown;
}

export interface MeterTelemetryOptions {
  /** The usage block with a service transport. */
  readonly usage: Pick<Usage, "recordMany">;
  /**
   * The tenant an operation is for. Defaults to the `org:` tag `gatewayOptions`
   * puts in `providerOptions.gateway.tags`, then `runtimeContext.organizationId`.
   * Operations without a tenant are not metered.
   */
  readonly tenant?: (event: TelemetryStart) => string | undefined;
  readonly meters?: TelemetryMeters;
  /** The `source` of each usage row. Default `ai:telemetry`. */
  readonly source?: string;
  readonly onError?: (error: DbError) => void;
}

/** The `org:` tag of `providerOptions.gateway.tags`, then `runtimeContext.organizationId`. */
export function tenantOfEvent(event: TelemetryStart): string | undefined {
  const options = event.providerOptions;
  const gateway =
    isRecord(options) && isRecord(options["gateway"])
      ? options["gateway"]
      : undefined;
  const tags = gateway?.["tags"];
  if (Array.isArray(tags))
    for (const tag of tags)
      if (typeof tag === "string" && tag.startsWith("org:") && tag.length > 4)
        return tag.slice(4);
  const context = event.runtimeContext;
  const id = isRecord(context) ? context["organizationId"] : undefined;
  return typeof id === "string" && id.length > 0 ? id : undefined;
}

const count = (value: unknown): number =>
  typeof value === "number" && Number.isFinite(value) && value > 0
    ? Math.round(value)
    : 0;

/**
 * A telemetry integration that meters every model call on the tenant's usage
 * meters: input and output tokens of each language model call (agent steps
 * included), embedding tokens, and rerank calls. Register it once with
 * `registerTelemetry(meterTelemetry({ usage }))`; each call's rows carry an
 * idempotency key, so a retried event is counted once. Don't also record the
 * same tokens with `usageEntries`.
 */
export function meterTelemetry(options: MeterTelemetryOptions): Telemetry {
  const tenants = new Map<string, string>();
  const calls = new Map<string, number>();
  const tenantOf = options.tenant ?? tenantOfEvent;
  const meters = options.meters ?? {};
  const source = options.source ?? "ai:telemetry";

  const record = async (
    callId: string,
    key: string,
    entries: readonly UsageEntry[],
  ): Promise<void> => {
    const tenant = tenants.get(callId);
    const kept = entries.filter((entry) => (entry.quantity ?? 0) > 0);
    if (tenant === undefined || kept.length === 0) return;
    const saved = await options.usage.recordMany(tenant, kept, {
      idempotencyKey: `ai-call:${key}`,
      source,
    });
    if (!saved.ok) options.onError?.(saved.error);
  };

  return {
    onStart: (event) => {
      const tenant = tenantOf(event);
      if (tenant !== undefined) tenants.set(event.callId, tenant);
    },
    onLanguageModelCallEnd: (event) => {
      const step = calls.get(event.callId) ?? 0;
      calls.set(event.callId, step + 1);
      return record(event.callId, `${event.callId}:${step}`, [
        {
          meter: meters.input ?? "ai.input_tokens",
          quantity: count(event.usage.inputTokens),
        },
        {
          meter: meters.output ?? "ai.output_tokens",
          quantity: count(event.usage.outputTokens),
        },
      ]);
    },
    onEmbedEnd: (event) =>
      record(event.callId, `${event.callId}:${event.embedCallId}`, [
        {
          meter: meters.embedding ?? "ai.embedding_tokens",
          quantity: count(event.usage.tokens),
        },
      ]),
    onRerankEnd: (event) =>
      record(event.callId, `${event.callId}:rerank`, [
        { meter: meters.rerank ?? "ai.rerank_calls", quantity: 1 },
      ]),
    onEnd: (event) => {
      tenants.delete(event.callId);
      calls.delete(event.callId);
    },
  };
}

/** One row of `gateway.getSpendReport()` grouped by tag. */
export interface SpendReportRow {
  readonly tag?: string;
  readonly totalCost: number;
  readonly requestCount?: number;
}

/** The AI Gateway call `spendReconciliation` makes (`gateway` from `ai`). */
export interface SpendReportClient {
  getSpendReport(params: {
    startDate: string;
    endDate: string;
    groupBy?: "tag";
    credentialType?: "byok" | "system";
  }): PromiseLike<{ readonly results: readonly SpendReportRow[] }>;
}

export interface SpendReconciliationOptions {
  readonly gateway: SpendReportClient;
  /** The usage block with a service transport. */
  readonly usage: Pick<Usage, "recordMany">;
  /** The micro-USD meter of the gateway's own figure. Default `ai.gateway_cost`. */
  readonly meter?: string;
  /** Only the spend the app pays (`system`) or tenants' own keys pay (`byok`). */
  readonly credentialType?: "byok" | "system";
  /** The clock, for tests. */
  readonly now?: () => Temporal.Instant;
}

export interface SpendReconciliation {
  /** The UTC day reconciled, `YYYY-MM-DD`. */
  readonly day: string;
  readonly tenants: readonly {
    readonly organizationId: string;
    readonly costMicroUsd: number;
    readonly requests: number;
  }[];
}

/**
 * A nightly job handler that reads the AI Gateway's spend for a UTC day
 * (yesterday unless the payload names `day`), grouped by the `org:` tags
 * `gatewayOptions` sets, and records each tenant's cost on `meter` once per
 * day. Compare that meter with the per-call cost meter to find drift.
 */
export function spendReconciliation(
  options: SpendReconciliationOptions,
): JobHandler<{ readonly day?: string } | undefined> {
  const meter = options.meter ?? "ai.gateway_cost";
  return async (payload) => {
    const day =
      payload?.day ??
      (options.now ?? nowInstant)()
        .toZonedDateTimeISO("UTC")
        .subtract({ days: 1 })
        .toPlainDate()
        .toString();
    const report = await options.gateway.getSpendReport({
      startDate: day,
      endDate: day,
      groupBy: "tag",
      ...(options.credentialType === undefined
        ? {}
        : { credentialType: options.credentialType }),
    });
    const tenants: SpendReconciliation["tenants"][number][] = [];
    for (const row of report.results) {
      if (typeof row.tag !== "string" || !row.tag.startsWith("org:")) continue;
      const organizationId = row.tag.slice(4);
      const costMicroUsd = Math.round(Math.max(0, row.totalCost) * 1_000_000);
      tenants.push({
        organizationId,
        costMicroUsd,
        requests: count(row.requestCount),
      });
      if (costMicroUsd === 0) continue;
      await options.usage
        .recordMany(organizationId, [{ meter, quantity: costMicroUsd }], {
          idempotencyKey: `ai-spend:${day}:${organizationId}`,
          source: "ai:gateway-spend",
        })
        .orThrow();
    }
    return { day, tenants } satisfies SpendReconciliation;
  };
}
