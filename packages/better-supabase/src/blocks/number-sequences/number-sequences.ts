import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { blockCall } from "../shared.ts";

export interface NumberSequencesOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: BlockHooks<NumberSequences>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
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

  const client: NumberSequences = {
    next: (organizationId, entity, at) =>
      call(
        "next_number",
        { tenant: organizationId, entity, at: at ?? null },
        (value) => {
          if (typeof value === "number" || typeof value === "bigint") {
            return String(value);
          }

          if (typeof value === "string") {
            return value;
          }

          throw new TypeError("next_number did not return a number");
        },
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "number-sequences",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
