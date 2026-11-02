import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { AccountingPeriod } from "../accounting/index.ts";
import type { BlockContext } from "../create-blocks.ts";
import type { CompositeOptions } from "../define-block.ts";
import type { FinanceParts } from "./manifest.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult as Async } from "../../core/result.ts";

/** What `finance.closePeriod` returns. */
export type PeriodClose =
  | { readonly closed: true; readonly period: AccountingPeriod }
  | { readonly closed: false; readonly blockers: readonly string[] };

/** The helpers `finance` adds over its parts. */
export interface Finance {
  /**
   * Closes the period when nothing blocks it. A blocked period is not an error:
   * the result lists the blockers (unreconciled bank lines, drafts) and changes
   * nothing.
   */
  closePeriod(periodId: string): AsyncResult<PeriodClose>;
}

/** What the `finance` creator receives. */
export type FinanceOptions = BlockContext &
  CompositeOptions<FinanceParts> & {
    /** \`before\` and \`after\` hooks per method (ADR 0015). */
    readonly hooks?: NoInfer<BlockHooks<Finance>>;
    /** Receives the errors \`after\` hooks throw. Default: \`console\`. */
    readonly logger?: Logger;
  };

/** Creates the `finance` helpers over the clients of its parts. */
export function createFinance(options: FinanceOptions): Finance {
  const { accounting } = options.parts;

  const client: Finance = {
    closePeriod: (periodId) =>
      accounting
        .closeBlockers(periodId)
        .andThen<PeriodClose>((blockers) =>
          blockers.length > 0
            ? Async.ok({ closed: false, blockers })
            : accounting
                .closePeriod(periodId)
                .map((period) => ({ closed: true, period })),
        ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "finance",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
