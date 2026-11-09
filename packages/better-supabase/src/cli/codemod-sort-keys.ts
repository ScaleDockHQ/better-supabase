/** Whether `keys` are in ascending order. */
export function isSorted(keys: readonly string[]): boolean {
  return keys.every(
    (key, index) => index === 0 || keys[index - 1]!.localeCompare(key) <= 0,
  );
}

const LEADING_COMMENTS = /^(?:\s*(?:\/\/[^\n]*|\/\*[\s\S]*?\*\/))*\s*/;
const KEY = /^(?:([A-Za-z_$][\w$]*)|"([^"]*)"|'([^']*)')\s*:(?!:)/;

/**
 * The top-level segments of `body`, split at commas outside nesting, strings
 * and comments.
 */
function segments(body: string): string[] {
  const parts: string[] = [];
  let depth = 0;
  let from = 0;
  let index = 0;

  while (index < body.length) {
    const char = body.charAt(index);
    const next = body.charAt(index + 1);

    if (char === "/" && next === "/") {
      const end = body.indexOf("\n", index);
      index = end === -1 ? body.length : end;
    } else if (char === "/" && next === "*") {
      const end = body.indexOf("*/", index + 2);
      index = end === -1 ? body.length : end + 2;
    } else if (char === '"' || char === "'" || char === "`") {
      index += 1;

      while (index < body.length && body.charAt(index) !== char) {
        index += body.charAt(index) === "\\" ? 2 : 1;
      }

      index += 1;
    } else {
      if ("([{".includes(char)) {
        depth += 1;
      } else if (")]}".includes(char)) {
        depth -= 1;
      } else if (char === "," && depth === 0) {
        parts.push(body.slice(from, index));
        from = index + 1;
      }

      index += 1;
    }
  }

  parts.push(body.slice(from));

  return parts;
}

/**
 * The entries of an object literal body, in key order. Each slot keeps its
 * whitespace, so the layout stays; an entry moves with the comments in front of
 * it. A spread, a method or any entry without a plain key leaves the body as it
 * is.
 */
export function sortObjectBody(body: string): string {
  const parts = segments(body);
  const trailing = parts.at(-1)!.trim() === "" ? parts.pop()! : undefined;

  const entries = parts.map((part) => {
    const core = part.trim();
    const match = KEY.exec(core.slice(LEADING_COMMENTS.exec(core)![0].length));

    return {
      core,
      lead: /^\s*/.exec(part)![0],
      trail: /\s*$/.exec(part)![0],
      key: match === null ? undefined : (match[1] ?? match[2] ?? match[3]),
    };
  });

  if (entries.some((entry) => entry.key === undefined)) {
    return body;
  }

  const ordered = entries.toSorted((a, b) => a.key!.localeCompare(b.key!));

  const written = entries.map(
    (slot, index) => `${slot.lead}${ordered[index]!.core}${slot.trail}`,
  );

  return trailing === undefined
    ? written.join(",")
    : `${written.join(",")},${trailing}`;
}
