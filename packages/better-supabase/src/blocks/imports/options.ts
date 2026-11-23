import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** What an import run does with one outbox event type (ADR 0141). */
export type ImportEventMode = "skip" | "tag" | "emit";

/** `blocks['imports'].options`. */
export type ImportsSqlOptions = {
  readonly targets?: unknown;
  /**
   * How a bare target (`targets: ["invoice"]` or `invoice: true`) finds its
   * functions: `write` and `updatedAt` are templates with `{entity}` in
   * `schema` (default `public`, `import_{entity}`,
   * `import_{entity}_updated_at`).
   */
  readonly targetConvention?: {
    readonly schema?: string;
    readonly write?: string;
    readonly updatedAt?: string;
  };
  /**
   * Event type (or `default`) to `skip`, `tag` (emit with `importRunId` in the
   * payload) or `emit`. An unlisted type is skipped.
   */
  readonly events?: Readonly<Record<string, ImportEventMode>>;
  /** `rows` audits every row change; `summary` one entry per entity and run. */
  readonly audit?: "rows" | "summary";
  /**
   * How long stored chunks keep their items, as intervals such as `"7 days"`. A
   * done chunk drops them at once; a failed one after `keepFailedItems`
   * (default 7 days). With `staleAfter` set, `maintenance()` cancels a run
   * whose heartbeat is older and drops its chunks' items (ADR 1223).
   */
  readonly chunks?: {
    readonly keepFailedItems?: string;
    readonly staleAfter?: string;
  };
};

export const importsSqlOptions: BlockOptionsSchema<ImportsSqlOptions> =
  blockOptions<ImportsSqlOptions>({
    targets: option.unknown(),
    targetConvention: option.unknown<{
      readonly schema?: string;
      readonly write?: string;
      readonly updatedAt?: string;
    }>(),
    events: option.unknown<Readonly<Record<string, ImportEventMode>>>(),
    audit: option.string<"rows" | "summary">(),
    chunks: option.unknown<{
      readonly keepFailedItems?: string;
      readonly staleAfter?: string;
    }>(),
  });
