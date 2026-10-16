import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { blockCall, recordOf, textOf } from "../shared.ts";

export interface ImportsOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /** `withBlockHooks` hooks around the methods (ADR 0015). */
  readonly hooks?: NoInfer<BlockHooks<Imports>>;
  /** Receives the errors `after` hooks throw. */
  readonly logger?: Logger;
}

export interface Imports {
  start(
    organizationId: string,
    kind: string,
    mapping?: Readonly<Record<string, string>>,
  ): AsyncResult<{ readonly id: string }>;
}

export function createImports(options: ImportsOptions): Imports {
  const call = blockCall(options.transport, options.schema, options.mappers);
  const client: Imports = {
    start: (organizationId, kind, mapping) =>
      call(
        "start_import",
        { tenant: organizationId, kind, mapping: mapping ?? {} },
        (value) => ({ id: textOf(recordOf(value, "start_import")["id"]) }),
      ),
  };
  return withBlockHooks(client, options.hooks, {
    block: "imports",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
