/**
 * One `@bsb` feature: `subject title=number` is `{ name: "subject", args: {
 * title: "number" } }`.
 */
export interface BsbTag {
  readonly name: string;
  /** `key=value` pairs; a bare word is `true`. */
  readonly args: Readonly<Record<string, string | true>>;
}

export interface BsbComment {
  /** The comment's free text, without the tag block. */
  readonly text: string;
  readonly tags: readonly BsbTag[];
}

const MARKER = /(^|\s)@bsb(?:\s|$)/u;

function split(block: string): string[] {
  const items: string[] = [];
  let current = "";
  let quoted = false;

  for (const char of block) {
    if (char === '"') {
      quoted = !quoted;
    }

    if (char === ";" && !quoted) {
      items.push(current);
      current = "";
    } else {
      current += char;
    }
  }

  items.push(current);

  return items.map((item) => item.trim()).filter((item) => item !== "");
}

function words(item: string): string[] {
  const out: string[] = [];
  let current = "";
  let quoted = false;

  for (const char of item) {
    if (char === '"') {
      quoted = !quoted;
    }

    if (/\s/u.test(char) && !quoted) {
      if (current !== "") {
        out.push(current);
      }

      current = "";
    } else {
      current += char;
    }
  }

  if (current !== "") {
    out.push(current);
  }

  return out;
}

function unquote(value: string): string {
  return value.length >= 2 && value.startsWith('"') && value.endsWith('"')
    ? value.slice(1, -1)
    : value;
}

function parseTag(item: string): BsbTag | undefined {
  const [name, ...rest] = words(item);

  if (name === undefined) {
    return undefined;
  }

  const args: Record<string, string | true> = {};

  for (const word of rest) {
    const at = word.indexOf("=");

    if (at === -1) {
      args[word] = true;
    } else {
      args[word.slice(0, at)] = unquote(word.slice(at + 1));
    }
  }

  return { name, args };
}

/**
 * Splits a table comment into its free text and its `@bsb` tags (ADR 0102). The
 * tag block starts at `@bsb` and runs to the end of the comment; tags are
 * separated by `;`. A comment without `@bsb` is all text.
 */
export function parseBsbComment(comment: string | null): BsbComment {
  if (comment === null) {
    return { text: "", tags: [] };
  }

  const match = MARKER.exec(comment);

  if (match === null) {
    return { text: comment.trim(), tags: [] };
  }

  const start = match.index + (match[1] ?? "").length;
  const block = comment.slice(start + "@bsb".length);

  return {
    text: comment.slice(0, start).trim(),
    tags: split(block).flatMap((item) => parseTag(item) ?? []),
  };
}

function formatValue(value: string): string {
  return /[\s;"]/u.test(value) ? `"${value.replaceAll('"', "")}"` : value;
}

function formatTag(tag: BsbTag): string {
  const args = Object.entries(tag.args).map(([key, value]) =>
    value === true ? key : `${key}=${formatValue(value)}`,
  );

  return [tag.name, ...args].join(" ");
}

/** The comment `parseBsbComment` reads back: the text, then `@bsb` and the tags. */
export function formatBsbComment(comment: BsbComment): string {
  if (comment.tags.length === 0) {
    return comment.text;
  }

  const block = `@bsb ${comment.tags.map((tag) => formatTag(tag)).join("; ")}`;

  return comment.text === "" ? block : `${comment.text} ${block}`;
}

/**
 * `comment` with the tag `name` set to `tag` (replacing a tag of that name), or
 * removed when `tag` is undefined. The free text stays as it is.
 */
export function setBsbTag(
  comment: string | null,
  name: string,
  tag: BsbTag | undefined,
): string {
  const parsed = parseBsbComment(comment);
  const others = parsed.tags.filter((each) => each.name !== name);

  return formatBsbComment({
    text: parsed.text,
    tags: tag === undefined ? others : [...others, tag],
  });
}

/** The `comment on table` statement for `table` (already quoted) and `comment`. */
export function commentOnTableSql(table: string, comment: string): string {
  return `comment on table ${table} is '${comment.replaceAll("'", "''")}';`;
}
