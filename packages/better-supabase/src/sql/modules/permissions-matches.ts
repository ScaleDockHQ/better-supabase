/**
 * `permission_matches`, by the wildcard grants the provider honours (ADR 0372):
 * `all` is the default, `prefix` drops the bare `*`, `none` is an exact match.
 */
export function permissionMatches(
  wildcards: "all" | "prefix" | "none" | undefined = "all",
): string {
  const comment = {
    all: "-- `*` grants every key and `prefix.*` every key under prefix.",
    prefix:
      "-- `prefix.*` grants every key under prefix; a bare `*` grants nothing.",
    none: "-- A granted key matches only itself; the provider honours no wildcards.",
  }[wildcards];

  const body = {
    all: `granted = '*' or granted = wanted
    or (right(granted, 2) = '.*' and starts_with(wanted, left(granted, -1)))`,
    prefix: `granted = wanted
    or (right(granted, 2) = '.*' and starts_with(wanted, left(granted, -1)))`,
    none: "granted = wanted",
  }[wildcards];

  return `${comment}
create or replace function better_supabase.permission_matches(granted text, wanted text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select ${body}
$$;`;
}
