import type { ModuleContext } from "../context.ts";
import type { ModuleLayout } from "../module-types.ts";

import { fillTemplate } from "../../core/access-sql.ts";
import { accessModel } from "./access-model.ts";

/**
 * `authorization.functions.teamIdsOf` for `user`, when the provider model is on
 * and sets it.
 */
export function providerTeamIds(
  ctx: ModuleContext,
  layout: ModuleLayout,
  user: string,
): string | undefined {
  const template =
    accessModel(ctx) === "provider"
      ? layout.accessProvider?.functions.teamIdsOf
      : undefined;

  return template === undefined
    ? undefined
    : fillTemplate("authorization.functions.teamIdsOf", template, { user });
}

/**
 * The caller's team ids as text, for `value in (<this>)`: the provider's
 * `teamIdsOf` when set, else the teams module's `team_ids_of()`, else `""` (no
 * teams).
 */
export function callerTeamIdsSql(
  ctx: ModuleContext,
  layout: ModuleLayout,
): string {
  const caller = "(select auth.uid())";
  const provider = providerTeamIds(ctx, layout, caller);

  if (provider !== undefined) {
    return `select t.id::text from ${provider} as t(id)`;
  }

  return ctx.installed("teams")
    ? `select t::text from ${ctx.of("teams").fn("team_ids_of")}(${caller}) t`
    : "";
}
