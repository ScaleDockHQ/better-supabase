import type { ModuleContext } from "../context.ts";

/** A rows-to-authors lookup that a list function joins into its rows. */
export interface AuthorLookup {
  /** The lookup function, with its grants. */
  readonly sql: string;
  /**
   * `json` with an `author` key, read from `authors` (the lookup's result for
   * the page) by the row id at `row`.
   */
  readonly attach: (json: string, authors: string, row: string) => string;
  /** The call that returns the authors of the rows whose ids `ids` lists. */
  readonly call: (ids: string) => string;
}

/** What a module tells authorLookup about its table. */
export interface AuthorSource {
  /** The lookup function's name, before naming rules apply. */
  readonly name: string;
  /** The table, quoted. */
  readonly table: string;
  /** The row id column and the author column, quoted. */
  readonly id: string;
  readonly user: string;
  /** Whether the caller may read row `y`: the read policy's tenant check. */
  readonly visible: string;
  /** The comment above the function, without the leading dashes. */
  readonly what: string;
}

/**
 * The display name and avatar URL of the users behind each row of a table, from
 * the profiles module, or undefined without it. The lookup runs as its owner,
 * because a profile's own policy may hide it from other members, and returns
 * only the authors of rows the caller may read.
 */
export function authorLookup(
  ctx: ModuleContext,
  source: AuthorSource,
): AuthorLookup | undefined {
  if (!ctx.installed("profiles")) {
    return undefined;
  }

  const profiles = ctx.of("profiles");
  const p = (logical: string): string => profiles.col("profiles", logical);
  const has = (logical: string): boolean => profiles.has("profiles", logical);
  const names: string[] = [];

  if (has("fullName")) {
    names.push(`nullif(pr.${p("fullName")}, '')`);
  }

  if (has("firstName") || has("lastName")) {
    const parts = (["firstName", "lastName"] as const)
      .filter((logical) => has(logical))
      .map((logical) => `pr.${p(logical)}`);

    names.push(`nullif(trim(concat_ws(' ', ${parts.join(", ")})), '')`);
  }

  if (has("username")) {
    names.push(`pr.${p("username")}`);
  }

  const name =
    names.length === 0 ? "null::text" : `coalesce(${names.join(", ")})`;

  const avatar = has("avatar") ? `pr.${p("avatar")}` : "null::text";
  const fn = ctx.fn(source.name);

  return {
    sql: `

-- ${source.what}
create or replace function ${fn}(ids uuid[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(y.${source.id}::text, jsonb_build_object('id', pr.${p("key")}, 'name', ${name}, 'avatarUrl', ${avatar})), '{}'::jsonb)
  from ${source.table} y
  join ${profiles.table("profiles")} pr on pr.${p("key")} = y.${source.user}
  where y.${source.id} = any ($1)
    and ${source.visible}
$$;
revoke execute on function ${fn}(uuid[]) from public, anon;
grant execute on function ${fn}(uuid[]) to authenticated, service_role;`,
    attach: (json, authors, row) =>
      `${json} || jsonb_build_object('author', ${authors} -> ${row}.${source.id}::text)`,
    call: (ids) => `${fn}(${ids})`,
  };
}
