import type { BlockSqlContext } from "../context.ts";

import { userGrant } from "../shared.ts";
import { asText } from "./over-app.ts";

interface ApplicationList {
  readonly name: string;
  /** The first parameter, such as `job uuid`. */
  readonly param: string;
  readonly type: string;
  /** The job filter, with `x.job` standing for the job column. */
  readonly match: string;
  /** A sort key that goes before the board order, ending in a comma. */
  readonly first?: string;
}

/**
 * `list_applications` and its batch form, which differ in the job filter and in
 * the first sort key.
 */
export function applicationList(
  ctx: BlockSqlContext,
  applicationJson: (alias: string) => string,
  list: ApplicationList,
): string {
  const a = (logical: string): string => ctx.col("applications", logical);

  const column = (sql: string): string =>
    sql.replaceAll("x.job", `x.${a("job")}`);

  const { name } = list;

  return `create or replace function ${ctx.fn(name)}(${list.param}, state text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${applicationJson("x")} order by ${column(list.first ?? "")}x.${a("stage")}, x.${a("rank")} collate "C", x.${a("id")}), '[]'::jsonb)
  from ${ctx.table("applications")} x
  where ${column(list.match)}
    and (${name}.state is null or ${asText(ctx, "applications", `x.${a("state")}`)} = ${name}.state)
$$;
${userGrant(`${ctx.fn(name)}(${list.type}, text)`)}`;
}
