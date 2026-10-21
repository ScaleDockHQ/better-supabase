import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** One numbered entity of `blocks.number-sequences.options.entities`. */
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

/** `blocks.number-sequences.options`. */
export type NumberSequencesSqlOptions = {
  readonly entities?: Readonly<Record<string, NumberSequenceEntityOptions>>;
};

export const numberSequencesSqlOptions: BlockOptionsSchema<NumberSequencesSqlOptions> =
  blockOptions<NumberSequencesSqlOptions>({
    entities:
      option.unknown<Readonly<Record<string, NumberSequenceEntityOptions>>>(),
  });
