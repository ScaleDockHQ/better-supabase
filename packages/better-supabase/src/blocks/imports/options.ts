import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** What an import run does with one outbox event type (ADR 0141). */
export type ImportEventMode = "skip" | "tag" | "emit";

/** `blocks['imports'].options`. */
export type ImportsSqlOptions = {
  readonly targets?: unknown;
  /**
   * Event type (or `default`) to `skip`, `tag` (emit with `importRunId` in the
   * payload) or `emit`. An unlisted type is skipped.
   */
  readonly events?: Readonly<Record<string, ImportEventMode>>;
  /** `rows` audits every row change; `summary` one entry per entity and run. */
  readonly audit?: "rows" | "summary";
};

export const importsSqlOptions: BlockOptionsSchema<ImportsSqlOptions> =
  blockOptions<ImportsSqlOptions>({
    targets: option.unknown(),
    events: option.unknown<Readonly<Record<string, ImportEventMode>>>(),
    audit: option.string<"rows" | "summary">(),
  });
