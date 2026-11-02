import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type {
  PaymentBatch,
  PaymentBatchInput,
  SepaExportOptions,
} from "../banking/index.ts";
import type { BlockContext } from "../create-blocks.ts";
import type { CompositeOptions } from "../define-block.ts";
import type { ProcurementParts } from "./manifest.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult as Async } from "../../core/result.ts";

/** What `procurement.payDueBills` returns. */
export interface PaidBills {
  readonly batch: PaymentBatch;
  /** The SEPA credit transfer file, when `sepa` was given. */
  readonly sepa: string | null;
}

/** The helpers `procurement` adds over its parts. */
export interface Procurement {
  /**
   * Batches the bills due by `dueBy`, posts the batch to the books, and with
   * `sepa` exports the bank file. A bill that needs approval refuses the batch
   * before anything posts.
   */
  payDueBills(input: {
    batch: PaymentBatchInput;
    sepa?: SepaExportOptions | undefined;
  }): AsyncResult<PaidBills>;
}

/** What the `procurement` creator receives. */
export type ProcurementOptions = BlockContext &
  CompositeOptions<ProcurementParts> & {
    /** \`before\` and \`after\` hooks per method (ADR 0015). */
    readonly hooks?: NoInfer<BlockHooks<Procurement>>;
    /** Receives the errors \`after\` hooks throw. Default: \`console\`. */
    readonly logger?: Logger;
  };

/** Creates the `procurement` helpers over the clients of its parts. */
export function createProcurement(options: ProcurementOptions): Procurement {
  const { banking } = options.parts;

  const client: Procurement = {
    payDueBills: ({ batch, sepa }) =>
      banking
        .createPaymentBatch(batch)
        .andThen((created) => banking.postPaymentBatch(created.id))
        .andThen<PaidBills>((posted) =>
          sepa === undefined
            ? Async.ok({ batch: posted, sepa: null })
            : banking
                .exportSepaCreditTransfer({ batchId: posted.id, ...sepa })
                .map((file) => ({ batch: posted, sepa: file })),
        ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "procurement",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
