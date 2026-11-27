import type { BlockSqlContext } from "../context.ts";
import type { BlockSqlTestFile } from "../module-types.ts";

/**
 * Checks that `approval_eligible_ids_in()` and `approval_eligible_ids()` return
 * the pending requests `approval_eligible` accepts, for each user of the
 * database in turn, in one transaction, so a memo kept for one user never
 * answers for the next.
 */
export function approvalTests(ctx: BlockSqlContext): BlockSqlTestFile[] {
  const requests = ctx.table("requests");
  const id = ctx.col("requests", "id");
  const status = ctx.col("requests", "status");
  const eligible = ctx.fn("approval_eligible");
  const ids = ctx.fn("approval_eligible_ids");
  const idsIn = ctx.fn("approval_eligible_ids_in");

  return [
    {
      name: "eligible_ids",
      sql: `begin;
create extension if not exists pgtap with schema extensions;

-- Before plan(), which writes: the reads run without a transaction id, as
-- PostgREST reads do, so the transaction memo is in play.
do $$
declare
  u record;
  bad bigint := 0;
  v_expected uuid[];
begin
  for u in select a.id from auth.users a order by a.id limit 25 loop
    perform set_config('request.jwt.claims', jsonb_build_object('sub', u.id, 'role', 'authenticated')::text, true);
    v_expected := (
      select coalesce(array_agg(r.${id} order by r.${id}), '{}') from ${requests} r
      where r.${status} = 'pending' and ${eligible}(r.${id})
    );
    if v_expected is distinct from (select coalesce(array_agg(x order by x), '{}') from ${idsIn}() x)
      or v_expected is distinct from (select coalesce(array_agg(x order by x), '{}') from ${ids}() x) then
      bad := bad + 1;
    end if;
  end loop;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('better_supabase.parity', bad::text, true);
end;
$$;

select extensions.plan(1);

select extensions.is(
  current_setting('better_supabase.parity')::bigint,
  0::bigint,
  'approval_eligible_ids_in and approval_eligible_ids return the pending requests approval_eligible accepts, for every user'
);

select * from extensions.finish();
rollback;`,
    },
  ];
}
