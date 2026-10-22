import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { blockCall } from "../shared.ts";

export interface NumberingOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: BlockHooks<Numbering>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

export interface Numbering {
  /**
   * Allocates the next gapless number. Service role only: a client round trip
   * would commit the number before the document does. Documents take their
   * number from the column trigger instead.
   */
  next(
    organizationId: string,
    entity: string,
    at?: string,
  ): AsyncResult<string>;
  /**
   * The number the next document would get, formatted, without assigning it.
   * Needs the `assign` permission in the organization; a concurrent document
   * can still take it first.
   */
  preview(
    organizationId: string,
    entity: string,
    at?: string,
  ): AsyncResult<string>;
}

export function createNumbering(options: NumberingOptions): Numbering {
  const call = blockCall(options.transport, options.schema, options.mappers);

  const text = (value: unknown): string => {
    if (typeof value === "string") {
      return value;
    }

    throw new TypeError("preview_number did not return a number");
  };

  const client: Numbering = {
    next: (organizationId, entity, at) =>
      call(
        "next_number",
        { tenant: organizationId, p_entity: entity, at: at ?? null },
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
    preview: (organizationId, entity, at) =>
      call(
        "preview_number",
        {
          p_tenant: organizationId,
          p_entity: entity,
          ...(at === undefined ? {} : { p_at: at }),
        },
        text,
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "numbering",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
