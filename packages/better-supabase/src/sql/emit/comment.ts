/** `comment on <kind> <target> is '<text>'`, with the quotes escaped. */
export function commentOn(
  kind: "table" | "column" | "function" | "constraint" | "schema",
  target: string,
  text: string,
): string {
  return `comment on ${kind} ${target} is '${text.replaceAll("'", "''")}';`;
}
