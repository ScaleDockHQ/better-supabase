import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { RecordRef } from "../../schema/types.ts";
import type { BlockContext } from "../create-blocks.ts";
import type { CompositeOptions } from "../define-block.ts";
import type {
  MedicationOrder,
  MedicationOrderInput,
} from "../medications/index.ts";
import type { CareParts } from "./manifest.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult as Async } from "../../core/result.ts";

/** The helpers `care` adds over its parts. */
export interface Care {
  /**
   * Prescribes a medication for the client only while a consent for
   * `purposeKey` is active: `consents.require`, then `medications.prescribe`. A
   * missing consent returns its error and prescribes nothing.
   */
  prescribeWithConsent(input: {
    organizationId: string;
    subject: RecordRef;
    purposeKey: string;
    medicationId: string;
    order: MedicationOrderInput;
  }): AsyncResult<MedicationOrder>;
}

/** What the `care` creator receives. */
export type CareOptions = BlockContext &
  CompositeOptions<CareParts> & {
    /** `before` and `after` hooks per method (ADR 0015). */
    readonly hooks?: NoInfer<BlockHooks<Care>>;
    /** Receives the errors `after` hooks throw. Default: `console`. */
    readonly logger?: Logger;
  };

/** Creates the `care` helpers over the clients of its parts. */
export function createCare(options: CareOptions): Care {
  const { consents, medications } = options.parts;

  const client: Care = {
    prescribeWithConsent: ({
      organizationId,
      subject,
      purposeKey,
      medicationId,
      order,
    }) =>
      Async.from(async () => {
        const consent = await consents.require({ subject, purposeKey });

        if (!consent.ok) {
          return consent;
        }

        return medications.prescribe({
          organizationId,
          subject,
          medicationId,
          input: order,
        });
      }),
  };

  return withBlockHooks(client, options.hooks, {
    block: "care",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
