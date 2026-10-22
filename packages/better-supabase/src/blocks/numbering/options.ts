import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** One numbered entity of `blocks.numbering.options.entities`. */
export type NumberSequenceEntityOptions = {
  readonly period:
    | "none"
    | "year"
    | "month"
    | "format"
    | { readonly fiscalYearStartMonth: number };
  readonly format: string;
  /**
   * A tenant's own format: `column` is `schema.table.column`, `key` holds the
   * tenant id (default `id`).
   */
  readonly formatFrom?: { readonly column: string; readonly key?: string };
  readonly periodFrom?: { readonly column: string; readonly key?: string };
  readonly table?: string;
  readonly column?: string;
  readonly sequenceColumn?: string;
  readonly tenantColumn?: string;
  readonly periodColumn?: string;
  readonly assignOn?: string;
  readonly permission?: string;
};

/** `blocks.numbering.options`. */
export type NumberingSqlOptions = {
  readonly entities?: Readonly<Record<string, NumberSequenceEntityOptions>>;
};

export const numberingSqlOptions: BlockOptionsSchema<NumberingSqlOptions> =
  blockOptions<NumberingSqlOptions>({
    entities:
      option.unknown<Readonly<Record<string, NumberSequenceEntityOptions>>>(),
  });
