/**
 * The metadata a `COMMENT ON` adds to a table or column: its description,
 * without the `@example` lines the validator generators read, and
 * `deprecated` when a line starts with `@deprecated`. The library's
 * `parseComment` (`src/generators/shared.ts`) reads comments the same way.
 */
export function commentMeta(comment: string | null | undefined): {
  description?: string;
  deprecated?: true;
} {
  if (!comment) return {};
  const deprecated = /^\s*@deprecated\b/m.test(comment);
  const description = comment
    .replaceAll(/^\s*@example\s+(.+?)\s*$/gm, "")
    .replaceAll(/^\s*@deprecated\b.*$/gm, "")
    .trim();
  return {
    ...(description ? { description } : {}),
    ...(deprecated ? { deprecated: true } : {}),
  };
}
