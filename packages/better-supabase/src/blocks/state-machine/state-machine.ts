import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { AsyncResult } from "../../core/result.ts";

import { blockCall } from "../shared.ts";

export interface StateMachineOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface StateMachine {
  /** Sets the status. The trigger rejects a change the machine does not allow. */
  transition(
    subjectType: string,
    subjectId: string,
    to: string,
    reason?: string,
  ): AsyncResult<boolean>;
}

export function createStateMachine(options: StateMachineOptions): StateMachine {
  const call = blockCall(options.transport, options.schema, options.mappers);
  return {
    transition: (subjectType, subjectId, to, reason) =>
      call(
        "transition",
        {
          subject_type: subjectType,
          subject_id: subjectId,
          to_status: to,
          reason: reason ?? null,
        },
        (value) => value === true,
      ),
  };
}
