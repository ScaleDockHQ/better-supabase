import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockContext } from "../create-blocks.ts";
import type { CompositeOptions } from "../define-block.ts";
import type { WorkOrder, WorkOrderPartInput } from "../dispatch/index.ts";
import type { ServiceParts } from "./manifest.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult as Async, ok } from "../../core/result.ts";

/** What `service.completeVisit` returns. */
export interface CompletedVisit {
  readonly workOrder: WorkOrder;
  readonly parts: number;
  readonly readings: number;
}

/** The helpers `service` adds over its parts. */
export interface Service {
  /**
   * Closes a visit: records each part used (`dispatch.recordPart`), each meter
   * reading taken (`maintenance.recordReading`), then marks the work order
   * `done` with `note`. The status moves last, so a failed part or reading
   * leaves the work order open. A retry records the parts and readings that
   * already went in again, so retry only the steps after the failed one.
   */
  completeVisit(input: {
    workOrderId: string;
    parts?: readonly WorkOrderPartInput[] | undefined;
    readings?:
      | readonly { meterId: string; value: string | number }[]
      | undefined;
    note?: string | undefined;
  }): AsyncResult<CompletedVisit>;
}

/** What the `service` creator receives. */
export type ServiceOptions = BlockContext &
  CompositeOptions<ServiceParts> & {
    /** `before` and `after` hooks per method (ADR 0015). */
    readonly hooks?: NoInfer<BlockHooks<Service>>;
    /** Receives the errors `after` hooks throw. Default: `console`. */
    readonly logger?: Logger;
  };

/** Creates the `service` helpers over the clients of its parts. */
export function createService(options: ServiceOptions): Service {
  const { dispatch, maintenance } = options.parts;

  const client: Service = {
    completeVisit: ({ workOrderId, parts = [], readings = [], note }) =>
      Async.from(async () => {
        for (const input of parts) {
          const recorded = await dispatch.recordPart({ workOrderId, input });

          if (!recorded.ok) {
            return recorded;
          }
        }

        for (const { meterId, value } of readings) {
          const recorded = await maintenance.recordReading({ meterId, value });

          if (!recorded.ok) {
            return recorded;
          }
        }

        const done = await dispatch.setStatus({
          id: workOrderId,
          status: "done",
          ...(note === undefined ? {} : { note }),
        });

        return done.ok
          ? ok({
              workOrder: done.data,
              parts: parts.length,
              readings: readings.length,
            })
          : done;
      }),
  };

  return withBlockHooks(client, options.hooks, {
    block: "service",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
