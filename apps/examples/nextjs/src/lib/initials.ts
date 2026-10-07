/** The two letters an avatar falls back to, from a name or else an email. */
export function initials(name: string | null, email: string | null): string {
  const source =
    [name?.trim(), email?.split("@")[0]].find(
      (value) => value !== undefined && value !== "",
    ) ?? "?";
  const parts = source.split(/[\s._-]+/).filter(Boolean);
  const first = parts[0]?.[0];
  const last = parts.at(-1)?.[0];
  const letters =
    parts.length > 1 && first && last ? `${first}${last}` : source.slice(0, 2);
  return letters.toUpperCase();
}
