import type {
  AppColumnConfig,
  AppColumnFormat,
  AppTableConfig,
} from "../../config/index.ts";

import { FIELD_FORMATS } from "../../config/index.ts";
import { literal as sqlString } from "../doctor/live.ts";

/** The schema that holds the format domains. */
export const DOMAIN_SCHEMA = "bsb";

/** A domain a format column takes as its type (ADR 0102). */
export interface FormatDomain {
  /** `bsb.email`, `bsb.rating_bigint`. */
  readonly name: string;
  /** The bare name, which is also the file name. */
  readonly bare: string;
  readonly base: string;
  /** The `create domain` statement. */
  readonly sql: string;
}

/**
 * The domain for a format on a column type, or undefined when the format has no
 * pattern or bounds to check. The first type a format fits takes the plain
 * name; the others add the type (`rating_bigint`).
 */
export function formatDomain(
  format: AppColumnFormat,
  type: string,
): FormatDomain | undefined {
  const spec = FIELD_FORMATS[format];
  // oxlint-disable-next-line unicorn/prefer-array-index-of -- `type` is a plain string, `types` a narrower union
  const index = spec.types.findIndex((each) => each === type);

  if (
    index === -1 ||
    (spec.pattern === undefined && spec.bounds === undefined)
  ) {
    return undefined;
  }

  const bare = index === 0 ? format : `${format}_${type}`;

  const checks = [
    ...(spec.pattern === undefined
      ? []
      : [`value ~* ${sqlString(spec.pattern)}`]),
    ...(spec.bounds === undefined
      ? []
      : [
          `value >= ${String(spec.bounds[0])}`,
          `value <= ${String(spec.bounds[1])}`,
        ]),
  ];

  return {
    name: `${DOMAIN_SCHEMA}.${bare}`,
    bare,
    base: type,
    sql: `create domain ${DOMAIN_SCHEMA}.${bare} as ${type}\n  constraint ${bare}_check check (${checks.join(" and ")});`,
  };
}

/** The domain a column takes, or undefined when it keeps its type and check. */
function domainOf(column: AppColumnConfig): FormatDomain | undefined {
  if (
    column.format === undefined ||
    column.options !== undefined ||
    column.encrypted === true ||
    column.min !== undefined ||
    column.max !== undefined
  ) {
    return undefined;
  }

  return formatDomain(column.format, column.type);
}

/**
 * `tables` with each format column typed as its domain, and the domains they
 * use. A column with its own `min`, `max` or `options` keeps the inline check,
 * since a domain would tighten what the column allows.
 */
export function withFormatDomains(
  tables: Readonly<Record<string, AppTableConfig>>,
): {
  readonly tables: Record<string, AppTableConfig>;
  readonly domains: readonly FormatDomain[];
} {
  const used = new Map<string, FormatDomain>();

  const mapped = Object.fromEntries(
    Object.entries(tables).map(([name, table]) => [
      name,
      {
        ...table,
        columns: Object.fromEntries(
          Object.entries(table.columns ?? {}).map(([column, config]) => {
            const domain = domainOf(config);

            if (domain === undefined) {
              return [column, config];
            }

            used.set(domain.name, domain);

            return [column, { ...config, domain: domain.name }];
          }),
        ),
      },
    ]),
  );

  return {
    tables: mapped,
    domains: [...used.values()].toSorted((a, b) =>
      a.name.localeCompare(b.name),
    ),
  };
}
