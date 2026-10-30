/**
 * A `ctx.read` statement that runs when the jsonb array `rows` has items and
 * the optional `when` holds, or nothing when the read isn't logged.
 */
export const readIfAny = (
  statement: string,
  rows: string,
  when?: string,
): string =>
  statement === ""
    ? ""
    : `\n  if jsonb_array_length(${rows}) > 0${when === undefined ? "" : ` and ${when}`} then\n    ${statement}\n  end if;`;
