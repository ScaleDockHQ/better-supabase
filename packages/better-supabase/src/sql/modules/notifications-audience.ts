import type { ModuleContext } from "../context.ts";
import type { ModuleLayout } from "../module-types.ts";

import { fillTemplate } from "../../core/access-sql.ts";
import { sqlString } from "../../core/template.ts";
import { fail } from "../shared.ts";
import { accessModel } from "./access-model.ts";

/**
 * Users who hold `notification.permission` in the tenant, added before
 * `exclude`. A provider without `holdersOf` refuses the audience. The roles
 * and catalog models ask `can_user` of each member, and the catalog model
 * also includes a platform-role holder. Never every member.
 */
export function permissionAudience(
  ctx: ModuleContext,
  layout: ModuleLayout,
): string {
  const named = "nullif(notification ->> 'permission', '')";
  const unavailable = `
  if ${named} is not null then
    ${fail("NOTIFICATION_PERMISSION_AUDIENCE_UNAVAILABLE", "This project has no permission audience", "0A000")}
  end if;`;
  const needsTenant = `
  if ${named} is not null and v_tenant is null then
    ${fail("NOTIFICATION_PERMISSION_NEEDS_TENANT", "A permission audience needs a tenant", "22023")}
  end if;`;
  const model = accessModel(ctx);
  if (model === "provider")
    return providerAudience(layout, needsTenant, unavailable, named);
  if (model === "custom")
    return customAudience(ctx, needsTenant, unavailable, named);
  if (!ctx.installed("tenant")) return unavailable;
  return membershipAudience(ctx, model, needsTenant, named);
}

function providerAudience(
  layout: ModuleLayout,
  needsTenant: string,
  unavailable: string,
  named: string,
): string {
  const provider = layout.accessProvider;
  if (provider === undefined) return unavailable;
  const template = provider.functions.holdersOf;
  if (template === undefined) return unavailable;
  const call = fillTemplate("authorization.functions.holdersOf", template, {
    permission: "(notification ->> 'permission')",
    tenant: "v_tenant",
    scope: provider.scope,
  });
  return audienceAppend(needsTenant, named, call);
}

function customAudience(
  ctx: ModuleContext,
  needsTenant: string,
  unavailable: string,
  named: string,
): string {
  const template = ctx.modules.access?.functions?.holdersOf;
  if (template === undefined) return unavailable;
  const call = fillTemplate("blocks.access.functions.holdersOf", template, {
    permission: "(notification ->> 'permission')",
    tenant: "v_tenant",
  });
  return audienceAppend(needsTenant, named, call);
}

function membershipAudience(
  ctx: ModuleContext,
  model: ReturnType<typeof accessModel>,
  needsTenant: string,
  named: string,
): string {
  const members = ctx.of("tenant");
  const user = members.col("memberships", "user");
  const tenant = members.col("memberships", "tenant");
  let platform = "";
  if (
    model === "catalog" &&
    ctx.installed("access") &&
    ctx.of("access").hasTable("platformAssignments")
  ) {
    const access = ctx.of("access");
    const holder = access.col("platformAssignments", "user");
    platform = `
      union
      select a.${holder}
      from ${access.table("platformAssignments")} a
      where coalesce(better_supabase.platform_can(a.${holder}, notification ->> 'permission'), false)`;
  }
  return `${needsTenant}
  if ${named} is not null then
    v_recipients := v_recipients || coalesce(array(
      select m.${user}
      from ${members.table("memberships")} m
      where m.${tenant} = v_tenant
        and coalesce(better_supabase.can_user(m.${user}, 'tenant', v_tenant, notification ->> 'permission'), false)
      ${platform}
    ), '{}');
  end if;`;
}

function audienceAppend(
  needsTenant: string,
  named: string,
  call: string,
): string {
  return `${needsTenant}
  if ${named} is not null then
    v_recipients := v_recipients || coalesce(array(select u from ${call} as t(u)), '{}');
  end if;`;
}

const NAME = /^[a-z][a-z0-9_]*$/;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** A channel nobody chose is on for `in_app` and off for the rest, unless `channelDefaults` says otherwise. */
export function channelDefaults(ctx: ModuleContext, channel: string): string {
  const value = ctx.option("channelDefaults") ?? {};
  if (!isRecord(value)) {
    throw new TypeError(
      "blocks.notifications.options.channelDefaults must map channel names to booleans",
    );
  }
  const cases = Object.entries(value).map(([channel, enabled]) => {
    if (!NAME.test(channel) || typeof enabled !== "boolean") {
      throw new TypeError(
        `blocks.notifications.options.channelDefaults.${channel} must be a boolean`,
      );
    }
    return `when ${sqlString(channel)} then ${String(enabled)}`;
  });
  return `case ${channel} ${[...cases, "when 'in_app' then true"].join(" ")} else false end`;
}
