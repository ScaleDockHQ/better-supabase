import type { BlockSqlContext } from "../context.ts";

import { sqlIdent } from "../../core/template.ts";

const FUNCTION_NAME = /^[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*$/;

/**
 * `options.resolveAddress`: the app function `schema.name(user uuid, channel
 * text) returns text` that says where a member is reached on a channel. Returns
 * the SQL for that address of `user` on `channel`, falling back to `fallback`
 * (the member's sign-in email) when the function returns null; the fallback
 * alone when the option is not set.
 */
export function addressSql(
  ctx: BlockSqlContext,
  user: string,
  channel: string,
  fallback: string,
): string {
  const name = ctx.option("resolveAddress");

  if (name === undefined) {
    return fallback;
  }

  if (typeof name !== "string" || !FUNCTION_NAME.test(name)) {
    throw new TypeError(
      'blocks.notifications.options.resolveAddress must be a function name like "better_supabase.member_address"',
    );
  }

  const [schema = "", fn = ""] = name.split(".");

  return `coalesce(${sqlIdent(schema)}.${sqlIdent(fn)}(${user}, ${channel}), ${fallback})`;
}
