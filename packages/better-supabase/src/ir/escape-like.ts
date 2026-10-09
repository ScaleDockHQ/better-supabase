/** Escapes LIKE wildcards so user input matches literally. */
export function escapeLike(value: string): string {
  return value.replaceAll(/[\\%_]/g, (char) => `\\${char}`);
}
