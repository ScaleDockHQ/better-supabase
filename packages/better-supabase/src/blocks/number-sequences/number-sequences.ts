import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { AsyncResult } from "../../core/result.ts";

import { blockCall } from "../shared.ts";

export interface NumberSequencesOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface NumberSequences {
  /**
   * Allocates the next gapless number. Service role only: a client round
   * trip would commit the number before the document does. Documents take
   * their number from the column trigger instead.
   */
  next(
    organizationId: string,
    entity: string,
    at?: string,
  ): AsyncResult<string>;
}

export function createNumberSequences(
  options: NumberSequencesOptions,
): NumberSequences {
  const call = blockCall(options.transport, options.schema, options.mappers);
  return {
    next: (organizationId, entity, at) =>
      call(
        "next_number",
        { tenant: organizationId, entity, at: at ?? null },
        (value) => {
          if (typeof value === "number" || typeof value === "bigint") {
            return String(value);
          }
          if (typeof value === "string") return value;
          throw new TypeError("next_number did not return a number");
        },
      ),
  };
}
