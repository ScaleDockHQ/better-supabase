/** A location in a JSON document: member names and array indexes from the root. */
export type PathSegment = string | number;

const ESCAPES: Readonly<Record<string, string>> = {
  b: "\b",
  f: "\f",
  n: "\n",
  r: "\r",
  t: "\t",
  "'": "'",
  "\\": "\\",
  "/": "/",
};

/**
 * Parses an RFC 9535 normalized path (§ 2.7), such as `$['paths'][0]`, into
 * its segments. Throws for anything else, because the engine promised one.
 */
export function parseNormalizedPath(path: string): PathSegment[] {
  if (!path.startsWith("$")) {
    throw new TypeError(`Not a normalized path: ${path}`);
  }

  const segments: PathSegment[] = [];
  let i = 1;

  while (i < path.length) {
    if (path[i] !== "[") {
      throw new TypeError(`Not a normalized path: ${path}`);
    }

    i++;

    if (path[i] === "'") {
      i++;
      let name = "";

      while (i < path.length && path[i] !== "'") {
        const char = path[i] ?? "";

        if (char !== "\\") {
          name += char;
          i++;
          continue;
        }

        const next = path[i + 1] ?? "";

        if (next === "u") {
          name += String.fromCodePoint(
            Number.parseInt(path.slice(i + 2, i + 6), 16),
          );
          i += 6;
          continue;
        }

        const escaped = ESCAPES[next];

        if (escaped === undefined) {
          throw new TypeError(`Not a normalized path: ${path}`);
        }

        name += escaped;
        i += 2;
      }

      if (path[i] !== "'" || path[i + 1] !== "]") {
        throw new TypeError(`Not a normalized path: ${path}`);
      }

      segments.push(name);
      i += 2;
      continue;
    }

    const end = path.indexOf("]", i);
    const digits = end === -1 ? "" : path.slice(i, end);

    if (!/^(?:0|[1-9]\d*)$/.test(digits)) {
      throw new TypeError(`Not a normalized path: ${path}`);
    }

    segments.push(Number(digits));
    i = end + 1;
  }

  return segments;
}

const SHORTHAND = /^[A-Za-z_][A-Za-z0-9_]*$/;

function quote(name: string): string {
  let out = "";

  for (const char of name) {
    const code = char.codePointAt(0) ?? 0;

    if (char === "\\") {
      out += "\\\\";
    } else if (char === "'") {
      out += "\\'";
    } else if (char === "\b") {
      out += "\\b";
    } else if (char === "\f") {
      out += "\\f";
    } else if (char === "\n") {
      out += "\\n";
    } else if (char === "\r") {
      out += "\\r";
    } else if (char === "\t") {
      out += "\\t";
    } else if (code < 0x20) {
      out += `\\u${code.toString(16).padStart(4, "0")}`;
    } else {
      out += char;
    }
  }

  return `['${out}']`;
}

/**
 * Formats segments as a readable RFC 9535 query: member-name shorthand for
 * plain names, bracket notation otherwise (`$.paths['/customers'].get`).
 */
export function formatPath(segments: readonly PathSegment[]): string {
  let out = "$";

  for (const segment of segments) {
    if (typeof segment === "number") {
      out += `[${segment}]`;
    } else if (SHORTHAND.test(segment)) {
      out += `.${segment}`;
    } else {
      out += quote(segment);
    }
  }

  return out;
}

/** Decodes one RFC 6901 reference token. */
export function decodePointerToken(token: string): string {
  return token.replaceAll("~1", "/").replaceAll("~0", "~");
}
