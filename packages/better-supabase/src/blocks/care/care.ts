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
import type { ValueOf } from "../read-all.ts";
import type { CareParts } from "./manifest.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult as Async, err, ok } from "../../core/result.ts";

type Parts = CompositeOptions<CareParts>["parts"];

/** One client's record, read from the care parts together: `care.dossier`. */
export interface CareDossier {
  /** The client's plans, newest version first; archived ones are left out. */
  readonly plans: ValueOf<ReturnType<Parts["care-plans"]["list"]>>;
  /** The latest final observation per definition key. */
  readonly latestObservations: ValueOf<
    ReturnType<Parts["observations"]["latest"]>
  >;
  /** Active medication orders, newest first. */
  readonly orders: ValueOf<ReturnType<Parts["medications"]["ordersOf"]>>;
  /** The latest consent decision per purpose. */
  readonly consents: ValueOf<ReturnType<Parts["consents"]["list"]>>;
  /** The client's funding awards with their usage. */
  readonly funding: ValueOf<ReturnType<Parts["funding"]["awardsWithUsage"]>>;
}

/** The helpers `care` adds over its parts. */
export interface Care {
  /**
   * Prescribes a medication for the client only while a consent for
   * `purposeKey` is active: `consents.require`, then `medications.prescribe`. A
   * missing consent returns its error and prescribes nothing.
   */
  /**
   * The care plans, latest observations, active medication orders, consents and
   * funding of one client, read together. The first read that fails returns its
   * error.
   */
  dossier(input: {
    organizationId: string;
    subject: RecordRef;
  }): AsyncResult<CareDossier>;
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
  const parts = options.parts;

  const client: Care = {
    dossier: ({ organizationId, subject }) =>
      Async.from<CareDossier>(async () => {
        const [plans, observations, orders, decisions, funding] =
          await Promise.all([
            parts["care-plans"].list({
              subjectType: subject.type,
              subjectId: subject.id,
            }),
            parts.observations.latest({
              subjectType: subject.type,
              subjectId: subject.id,
            }),
            medications.ordersOf({ subject }),
            consents.list({ subject }),
            parts.funding.awardsWithUsage({ organizationId, subject }),
          ]);

        if (!plans.ok) {
          return err(plans.error);
        }

        if (!observations.ok) {
          return err(observations.error);
        }

        if (!orders.ok) {
          return err(orders.error);
        }

        if (!decisions.ok) {
          return err(decisions.error);
        }

        if (!funding.ok) {
          return err(funding.error);
        }

        return ok({
          plans: plans.data,
          latestObservations: observations.data,
          orders: orders.data,
          consents: decisions.data,
          funding: funding.data,
        });
      }),
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
