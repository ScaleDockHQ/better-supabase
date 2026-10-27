import { RANK_ALPHABET } from "../core/rank-keys.ts";
import { sqlString } from "../core/template.ts";

/** The `~` pattern a rank key matches, the same as `isRankKey`. */
export const RANK_KEY_PATTERN = "'^[0-9A-Za-z]*[1-9A-Za-z]$'";

/**
 * SQL for the key after `last`, the same as `rankBetween(last, null)`. It reads
 * `last` several times, so pass a variable, not a query.
 */
export function rankAfter(last: string): string {
  const alphabet = sqlString(RANK_ALPHABET);
  const run = `length(substring(${last} from '^z*'))`;

  return `case
    when ${last} is null then 'V'
    when ${run} = length(${last}) then ${last} || 'V'
    else left(${last}, ${run}) || substr(${alphabet}, (strpos(${alphabet}, substr(${last}, ${run} + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end`;
}

/**
 * An UPDATE that gives every row of `table` a rank key in `orderBy` order, per
 * `partition`: four base-62 digits of the row number then "V", so up to 14
 * million rows per partition keep their order and room between keys.
 */
export function rankBackfill(options: {
  readonly table: string;
  readonly id: string;
  readonly rank: string;
  readonly partition: readonly string[];
  readonly orderBy: string;
}): string {
  const alphabet = sqlString(RANK_ALPHABET);

  const digit = (divisor: number): string =>
    `substr(${alphabet}, ((o.nth / ${divisor}) % 62)::integer + 1, 1)`;

  const partition =
    options.partition.length === 0
      ? ""
      : `partition by ${options.partition.join(", ")} `;

  return `with ordered as (
  select ${options.id} as row_id, row_number() over (${partition}order by ${options.orderBy}) as nth
  from ${options.table}
)
update ${options.table} t
set ${options.rank} = ${digit(238_328)} || ${digit(3844)} || ${digit(62)} || ${digit(1)} || 'V'
from ordered o
where t.${options.id} = o.row_id;`;
}

/** How a module writes and orders a rank column of one type. */
export interface RankSql {
  /** The column type, for a table the module creates. */
  readonly type: string;
  /** The column default. */
  readonly fallback: string;
  /** `value` ordered as a rank. */
  readonly order: (value: string) => string;
  /** The text rank after text `last` (null for the first). */
  readonly after: (last: string) => string;
  /** A text rank as a value of the column's type. */
  readonly write: (value: string) => string;
  /** The `~` pattern a rank argument matches. */
  readonly pattern: string;
}

/**
 * Rank keys (`text`, base-62 fractional keys) or whole-number positions
 * (`integer`, one more than the last), for an app whose rank column is an
 * integer. Ranks travel as text either way.
 */
export function rankSql(type: "text" | "integer"): RankSql {
  return type === "integer"
    ? {
        type: "integer",
        fallback: "0",
        order: (value) => value,
        after: (last) => `(coalesce((${last})::integer, 0) + 1)::text`,
        write: (value) => `(${value})::integer`,
        pattern: "'^-?[0-9]{1,9}$'",
      }
    : {
        type: 'text collate "C"',
        fallback: "'V'",
        order: (value) => `${value} collate "C"`,
        after: rankAfter,
        write: (value) => value,
        pattern: RANK_KEY_PATTERN,
      };
}
