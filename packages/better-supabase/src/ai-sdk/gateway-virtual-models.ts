import type { AiChat, AiModelInput } from "../blocks/ai-chat/ai-chat.ts";
import type { JobHandler } from "../blocks/queue/types.ts";
import type { Usage } from "../blocks/usage/usage.ts";
import type { GatewayModelEntry } from "./gateway.ts";

import { nowInstant } from "../core/temporal.ts";
import { modelInputOf } from "./gateway.ts";

/** The prefix of a virtual model id on the AI Gateway: `vmc/<slug>`. */
export const VIRTUAL_MODEL_PREFIX = "vmc/";

/** Whether a model id names a virtual model (a team-defined routing alias). */
export function isVirtualModel(id: string): boolean {
  return (
    id.startsWith(VIRTUAL_MODEL_PREFIX) &&
    id.length > VIRTUAL_MODEL_PREFIX.length
  );
}

/**
 * The catalog row for a virtual model. It keeps the gateway's pricing and marks
 * `capabilities.virtual` so a picker can group it apart from provider models.
 * The provider is `virtual`: which provider serves a call is the routing rule's
 * choice, made on the gateway.
 */
export function virtualModelInputOf(
  model: GatewayModelEntry,
  plans?: readonly string[],
): AiModelInput {
  const row = modelInputOf(model, plans);

  return {
    ...row,
    provider: "virtual",
    capabilities: {
      ...row.capabilities,
      virtual: true,
      slug: model.id.slice(VIRTUAL_MODEL_PREFIX.length),
    },
  };
}

/** The AI Gateway call `virtualModelCatalogRefresh` makes (`gateway` from `ai`). */
export interface VirtualModelListClient {
  getAvailableModels(): PromiseLike<{
    readonly models: readonly GatewayModelEntry[];
  }>;
}

export interface VirtualModelCatalogRefreshOptions {
  /** The chat block with a service transport. */
  readonly chats: Pick<AiChat, "models">;
  readonly gateway: VirtualModelListClient;
  /** The plans a virtual model is offered on. Default: every plan. */
  readonly plans?: (model: GatewayModelEntry) => readonly string[] | undefined;
}

/**
 * A job handler that adds the team's virtual models to the chat block's model
 * catalog (`models.upsert`), next to the provider models `modelCatalogRefresh`
 * writes. It never prunes: pruning would delete the provider rows too.
 */
export function virtualModelCatalogRefresh(
  options: VirtualModelCatalogRefreshOptions,
): JobHandler<unknown> {
  return async () => {
    const { models } = await options.gateway.getAvailableModels();

    const rows = models
      .filter((model) => isVirtualModel(model.id))
      .map((model) => virtualModelInputOf(model, options.plans?.(model)));

    return options.chats.models
      .upsert({ models: rows, prune: false })
      .orThrow();
  };
}

/** One row of `gateway.getSpendReport()` grouped by user. */
export interface UserSpendReportRow {
  readonly user?: string;
  readonly totalCost: number;
  readonly requestCount?: number;
}

/** The AI Gateway call `virtualModelSpendReconciliation` makes. */
export interface UserSpendReportClient {
  getSpendReport(params: {
    startDate: string;
    endDate: string;
    groupBy: "user";
    credentialType?: "byok" | "system";
  }): PromiseLike<{ readonly results: readonly UserSpendReportRow[] }>;
}

export interface VirtualModelSpendOptions {
  readonly gateway: UserSpendReportClient;
  /** The usage block with a service transport. */
  readonly usage: Pick<Usage, "recordMany">;
  /**
   * The organization a gateway `user` spent for, or `undefined` to skip the
   * user. A user in several organizations is ambiguous here: send `user:
   * "<organizationId>:<userId>"` for those calls and split it in this
   * function.
   */
  readonly organizationOf: (
    user: string,
  ) => PromiseLike<string | undefined> | string | undefined;
  /** The micro-USD meter of the gateway's own figure. Default `ai.gateway_cost`. */
  readonly meter?: string;
  readonly credentialType?: "byok" | "system";
  /** The clock, for tests. */
  readonly now?: () => ReturnType<typeof nowInstant>;
}

export interface VirtualModelSpend {
  /** The UTC day reconciled, `YYYY-MM-DD`. */
  readonly day: string;
  readonly tenants: readonly {
    readonly organizationId: string;
    readonly costMicroUsd: number;
    readonly requests: number;
  }[];
  /** Users the resolver gave no organization, and the cost they carry. */
  readonly unattributedMicroUsd: number;
}

/**
 * A nightly job handler for spend that `spendReconciliation` can't see. A
 * virtual model replaces the request's `tags` with the ones its rule sets, so
 * the `org:` tag never reaches the report; the `user` does. This reads the
 * day's spend grouped by user, maps each user to an organization and records
 * the cost once per day and organization on `meter`.
 *
 * Run it instead of `spendReconciliation` when most traffic uses virtual
 * models. Both write the same idempotency key per day and organization, so with
 * both the first to run wins.
 */
export function virtualModelSpendReconciliation(
  options: VirtualModelSpendOptions,
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
      groupBy: "user",
      ...(options.credentialType === undefined
        ? {}
        : { credentialType: options.credentialType }),
    });

    const totals = new Map<
      string,
      { costMicroUsd: number; requests: number }
    >();

    let unattributedMicroUsd = 0;

    for (const row of report.results) {
      const costMicroUsd = Math.round(Math.max(0, row.totalCost) * 1_000_000);

      const organizationId =
        typeof row.user === "string"
          ? await options.organizationOf(row.user)
          : undefined;

      if (organizationId === undefined) {
        unattributedMicroUsd += costMicroUsd;
        continue;
      }

      const total = totals.get(organizationId) ?? {
        costMicroUsd: 0,
        requests: 0,
      };

      total.costMicroUsd += costMicroUsd;
      total.requests += row.requestCount ?? 0;
      totals.set(organizationId, total);
    }

    const tenants: VirtualModelSpend["tenants"][number][] = [];

    for (const [organizationId, total] of totals) {
      tenants.push({ organizationId, ...total });

      if (total.costMicroUsd === 0) {
        continue;
      }

      await options.usage
        .recordMany({
          organizationId,
          entries: [{ meter, quantity: total.costMicroUsd }],
          idempotencyKey: `ai-spend:${day}:${organizationId}`,
          source: "ai:gateway-spend",
        })
        .orThrow();
    }

    return { day, tenants, unattributedMicroUsd } satisfies VirtualModelSpend;
  };
}
