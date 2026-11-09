/** The part of an offset page's `page` that `formatPageTotal` reads. */
export interface PageTotal {
  readonly total: number | null;
  readonly capped?: boolean | undefined;
}

export interface FormatPageTotalOptions {
  /** A BCP 47 tag for the digits' grouping. Defaults to the runtime's locale. */
  readonly locale?: string | undefined;
  /**
   * Renders a capped (estimated) total from its formatted number. Defaults to a
   * tilde in front, such as `~12,300`; pass your own wording per language.
   */
  readonly capped?: ((formatted: string) => string) | undefined;
}

const approximately = (formatted: string): string => `~${formatted}`;

/**
 * A page's total as text: the number as is when it is exact, marked as an
 * estimate when `page.capped` is true, and an empty string without a total.
 */
export function formatPageTotal(
  page: PageTotal,
  options: FormatPageTotalOptions = {},
): string {
  if (page.total === null) {
    return "";
  }

  const formatted = new Intl.NumberFormat(options.locale).format(page.total);

  return page.capped === true
    ? (options.capped ?? approximately)(formatted)
    : formatted;
}
