import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { AsyncResult } from "../../core/result.ts";

import { blockCall, recordOf, textOf } from "../shared.ts";

export interface ImportsOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
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
  return {
    start: (organizationId, kind, mapping) =>
      call(
        "start_import",
        { tenant: organizationId, kind, mapping: mapping ?? {} },
        (value) => ({ id: textOf(recordOf(value, "start_import")["id"]) }),
      ),
  };
}
