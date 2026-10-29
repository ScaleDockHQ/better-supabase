import type { BlockSqlContext } from "../context.ts";

import {
  currentPermissionKeys,
  isOldPermissionKey,
  PERMISSION_KEY_RENAMES,
  PERMISSION_KEY_SPLITS,
} from "../../core/renames.ts";
import { sqlString } from "../../core/template.ts";
import { accessModel } from "./permissions-model.ts";

interface KeyMove {
  readonly old: string;
  readonly next: readonly string[];
  readonly retire: boolean;
}

/**
 * Each old key as the catalog stores it (after the app's entity renames) and
 * the keys it grants now. A split key that still exists keeps its row.
 */
function keyMoves(ctx: BlockSqlContext): readonly KeyMove[] {
  const naming = ctx.blockNaming();

  const olds = [
    ...new Set([
      ...Object.keys(PERMISSION_KEY_RENAMES),
      ...Object.keys(PERMISSION_KEY_SPLITS),
    ]),
  ].toSorted();

  return olds.flatMap((key) => {
    const old = naming.rename(key);
    const next = currentPermissionKeys(key).filter((each) => each !== old);

    return next.length === 0
      ? []
      : [{ old, next, retire: isOldPermissionKey(key) }];
  });
}

/**
 * Moves the catalog's stored permission keys to the 0.46 names (ADR 0130): a
 * renamed key's row takes the new key, or its role and override links move to
 * the existing row; a split key adds the new rows with the same links. Then
 * every user's authorization version goes up, so cached keys drop. It runs once
 * per data migration and is a no-op when no old key is stored.
 */
export function catalogKeyRenames(ctx: BlockSqlContext): string {
  if (accessModel(ctx) !== "catalog") {
    return "";
  }

  const permissions = ctx.table("permissions");
  const id = ctx.col("permissions", "id");
  const key = ctx.col("permissions", "key");
  const links = ctx.table("rolePermissions");
  const linkRole = ctx.col("rolePermissions", "role");
  const linkPermission = ctx.col("rolePermissions", "permission");

  const overrides = ctx.hasTable("overrides")
    ? `
      insert into ${ctx.table("overrides")} (${ctx.col("overrides", "tenant")}, ${ctx.col("overrides", "role")}, ${ctx.col("overrides", "permission")}, ${ctx.col("overrides", "granted")})
      select o.${ctx.col("overrides", "tenant")}, o.${ctx.col("overrides", "role")}, v_new, o.${ctx.col("overrides", "granted")}
      from ${ctx.table("overrides")} o
      where o.${ctx.col("overrides", "permission")} = v_old
      on conflict do nothing;`
    : "";

  const moves = keyMoves(ctx)
    .map(
      (move) =>
        `    (${sqlString(move.old)}, array[${move.next.map(sqlString).join(", ")}]::text[], ${String(move.retire)})`,
    )
    .join(",\n");

  return `-- Permission keys renamed by the 0.46 naming convention (ADR 0130).
do $$
declare
  r record;
  v_key text;
  v_old uuid;
  v_new uuid;
  v_changed boolean := false;
begin
  for r in
    select * from (values
${moves}
    ) as m(old_key, next_keys, retire)
  loop
    select ${id} into v_old from ${permissions} where ${key} = r.old_key;
    continue when v_old is null;
    v_changed := true;

    if r.retire and cardinality(r.next_keys) = 1
      and not exists (select 1 from ${permissions} where ${key} = r.next_keys[1]) then
      update ${permissions} set ${key} = r.next_keys[1] where ${id} = v_old;
      continue;
    end if;

    foreach v_key in array r.next_keys loop
      select ${id} into v_new from ${permissions} where ${key} = v_key;
      if v_new is null then
        insert into ${permissions} (${key}) values (v_key) returning ${id} into v_new;
      end if;
      insert into ${links} (${linkRole}, ${linkPermission})
      select l.${linkRole}, v_new from ${links} l where l.${linkPermission} = v_old
      on conflict do nothing;${overrides}
    end loop;

    if r.retire then
      delete from ${permissions} where ${id} = v_old;
    end if;
  end loop;

  if v_changed and to_regprocedure('better_supabase.bump_authz_versions(uuid[])') is not null then
    execute 'select better_supabase.bump_authz_versions(array(select id from auth.users))';
  end if;
end;
$$;`;
}
