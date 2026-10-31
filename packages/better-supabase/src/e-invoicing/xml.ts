const ENTITIES: Readonly<Record<string, string>> = {
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&apos;",
};

const SPECIAL = /[&<>"']/g;

/**
 * XML 1.0 forbids C0 controls other than tab, line feed and carriage return,
 * even as character references.
 */
const allowed = (character: string): boolean => {
  const code = character.codePointAt(0) ?? 0;

  return code >= 0x20 || code === 0x09 || code === 0x0a || code === 0x0d;
};

export function escapeXml(value: string): string {
  let kept = "";

  for (const character of value) {
    if (allowed(character)) {
      kept += character;
    }
  }

  return kept.replaceAll(
    SPECIAL,
    (character) => ENTITIES[character] ?? character,
  );
}

export type Child = string | undefined;

/**
 * An element. Text content is escaped; an array holds rendered children, and an
 * element whose content is `undefined` or has no children renders nothing.
 */
export function el(
  name: string,
  content: string | readonly Child[] | undefined,
  attributes: Readonly<Record<string, string | undefined>> = {},
): string {
  if (content === undefined) {
    return "";
  }

  const body =
    typeof content === "string"
      ? escapeXml(content)
      : content.filter((child) => child !== undefined && child !== "").join("");

  if (typeof content !== "string" && body === "") {
    return "";
  }

  const attrs = Object.entries(attributes)
    .filter((entry): entry is [string, string] => entry[1] !== undefined)
    .map(([key, value]) => ` ${key}="${escapeXml(value)}"`)
    .join("");

  return `<${name}${attrs}>${body}</${name}>`;
}
