const OUTSIDE = /^[a-z0-9_ (),.[\]-]$/i;
const INSIDE = /^[a-z0-9_ (),.[\]{}:+@/"-]$/i;

/**
 * Whether `type` is a column type an `extraColumns` entry may render, such as
 * `text not null default 'en'` or `uuid[] default '{}'::uuid[]`. Quoted
 * defaults may hold `{`, `}` and `:`; outside them `:` only appears as a `::`
 * cast. `;`, `--`, `/*` and an unclosed quote are refused anywhere, so the type
 * can't end the statement or comment out the rest.
 */
export function isSqlType(type: string): boolean {
  if (
    !/^[a-z]/i.test(type) ||
    type.includes(";") ||
    type.includes("--") ||
    type.includes("/*")
  ) {
    return false;
  }

  let quoted = false;

  for (let index = 0; index < type.length; index += 1) {
    const char = type.charAt(index);

    if (char === "'") {
      quoted = !quoted;
      continue;
    }

    if (quoted) {
      if (!INSIDE.test(char)) {
        return false;
      }

      continue;
    }

    if (char === ":") {
      if (type.charAt(index + 1) !== ":") {
        return false;
      }

      index += 1;
      continue;
    }

    if (!OUTSIDE.test(char)) {
      return false;
    }
  }

  return !quoted;
}
