import type { Usage, UsageStatus } from "../blocks/usage/usage.ts";
import type { GatewayCost, GatewayCostMeters } from "./gateway-cost.ts";

import { dbError } from "../core/errors.ts";
import { AsyncResult, err, ok } from "../core/result.ts";
import { nowInstant } from "../core/temporal.ts";
import { gatewayCostEntries } from "./gateway-cost.ts";

/** Where an organization stands against its AI budget. */
export interface GatewayBudgetStatus {
  readonly organizationId: string;
  /** Micro-USD spent in the current period. */
  readonly usedMicroUsd: number;
  /** `undefined` when the organization has no budget (quota) for the meter. */
  readonly limitMicroUsd: number | undefined;
  readonly remainingMicroUsd: number | undefined;
  /** When the period resets. */
  readonly resetsAt: UsageStatus["resetsAt"];
}

export interface GatewayBudgetOptions {
  /** The usage block with a service transport; its quotas are the budgets. */
  readonly usage: Pick<Usage, "current" | "recordMany">;
  /** The meter that holds micro-USD. Default `ai.cost`. */
  readonly meter?: string;
  /** The meters `settle` writes besides the money meter. */
  readonly meters?: GatewayCostMeters;
  /**
   * Count a call a tenant's own provider key served. Default `false`: the
   * tenant pays that provider, so it doesn't use up the organization's budget.
   */
  readonly countByok?: boolean;
}

export interface GatewayBudgetCheck {
  readonly organizationId: string;
  /**
   * What the call is expected to cost, in micro-USD. The call is refused when
   * less than this is left. Default 0: refused only when nothing is left.
   */
  readonly estimateMicroUsd?: number;
}

export interface GatewayBudgetSettle {
  readonly organizationId: string;
  readonly cost: GatewayCost;
}

/** What `settle` did. */
export interface GatewayBudgetSettled {
  /** `false` when the generation was already settled (a retry). */
  readonly recorded: boolean;
  /**
   * `true` when the response had no cost yet, so nothing money-related was
   * written: enqueue `gatewayCostBackfill` for the generation.
   */
  readonly pending: boolean;
}

/**
 * A budget per organization in Postgres: `check` before a call and `settle`
 * after it. It reads the quota of the usage block's `ai.cost` meter, so the
 * budget is the quota you set per organization or plan, in micro-USD, and it
 * resets with the quota's period.
 *
 * The budget is soft: concurrent calls can each pass `check` and together pass
 * the limit by what they cost, because the cost is only known after the call.
 * Use `estimateMicroUsd` to leave headroom. The AI Gateway's own budgets can't
 * replace this: they scope to the team, a project, an API key or a user, not to
 * an organization, and they don't count calls that use a bring-your-own key.
 */
export interface GatewayBudget {
  /** The organization's standing, without refusing anything. */
  status(organizationId: string): AsyncResult<GatewayBudgetStatus>;
  /**
   * `quota_exceeded` (meter, limit, `retryAfter` seconds) when the budget is
   * used up.
   */
  check(input: GatewayBudgetCheck): AsyncResult<GatewayBudgetStatus>;
  /** Writes the cost of a finished call once, keyed by its generation id. */
  settle(input: GatewayBudgetSettle): AsyncResult<GatewayBudgetSettled>;
}

export function createGatewayBudget(
  options: GatewayBudgetOptions,
): GatewayBudget {
  const meter = options.meter ?? "ai.cost";
  const meters = { ...options.meters, cost: meter };

  const status = (organizationId: string): AsyncResult<GatewayBudgetStatus> =>
    options.usage
      .current({ organizationId, meter })
      .map((current) => ({
        organizationId,
        usedMicroUsd: current.used,
        limitMicroUsd: current.unlimited ? undefined : current.limit,
        remainingMicroUsd: current.unlimited ? undefined : current.remaining,
        resetsAt: current.resetsAt,
      }));

  return {
    status,
    check: ({ organizationId, estimateMicroUsd = 0 }) =>
      status(organizationId).andThen((standing) => {
        const { remainingMicroUsd, limitMicroUsd } = standing;

        const fits =
          remainingMicroUsd === undefined ||
          (estimateMicroUsd > 0
            ? remainingMicroUsd >= estimateMicroUsd
            : remainingMicroUsd > 0);

        if (fits) {
          return Promise.resolve(ok(standing));
        }

        const retryAfter = Math.max(
          0,
          Math.ceil(
            (standing.resetsAt.epochMilliseconds -
              nowInstant().epochMilliseconds) /
              1000,
          ),
        );

        return Promise.resolve(
          err(
            dbError(
              "quota_exceeded",
              "The organization's AI budget is used up.",
              {
                meter,
                ...(limitMicroUsd === undefined
                  ? {}
                  : { limit: limitMicroUsd }),
                retryAfter,
              },
            ),
          ),
        );
      }),
    settle: ({ organizationId, cost }) => {
      const pending = cost.costMicroUsd === undefined;

      const entries = gatewayCostEntries(cost, meters, {
        ...(options.countByok === undefined
          ? {}
          : { countByok: options.countByok }),
      }).filter((entry) => entry.meter === meter);

      if (entries.length === 0) {
        return new AsyncResult(
          Promise.resolve(ok({ recorded: false, pending })),
        );
      }

      return options.usage
        .recordMany({
          organizationId,
          entries,
          // The same key the cost backfill uses, so a call settled here and
          // again by the backfill counts once.
          ...(cost.generationId === undefined
            ? {}
            : { idempotencyKey: `ai-cost:${cost.generationId}` }),
          source: "ai:gateway",
        })
        .map((recorded) => ({ recorded: recorded.recorded, pending }));
    },
  };
}
