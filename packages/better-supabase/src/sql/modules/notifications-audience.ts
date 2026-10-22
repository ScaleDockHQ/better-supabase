import type { BlockSqlContext } from "../context.ts";
import type { BlockSqlLayout } from "../module-types.ts";

import { fillTemplate } from "../../core/access-sql.ts";
import { isRecord } from "../../core/guards.ts";
import { sqlString } from "../../core/template.ts";
import { fail } from "../shared.ts";
import { accessModel } from "./permissions-model.ts";

/**
 * Users who hold `notification.permission` in the tenant, added before
 * `exclude`. A provider without `holdersOf` refuses the audience. The roles and
 * catalog models ask `can_user` of each member, and the catalog model also
 * includes a platform-role holder. Never every member.
 */
export function permissionAudience(
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
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

  if (model === "provider") {
    return providerAudience(layout, needsTenant, unavailable, named);
  }

  if (model === "custom") {
    return customAudience(ctx, needsTenant, unavailable, named);
  }

  if (!ctx.installed("memberships")) {
    return unavailable;
  }

  return membershipAudience(ctx, model, needsTenant, named);
}

function providerAudience(
  layout: BlockSqlLayout,
  needsTenant: string,
  unavailable: string,
  named: string,
): string {
  const provider = layout.accessProvider;

  if (provider === undefined) {
    return unavailable;
  }

  const template = provider.functions.holdersOf;

  if (template === undefined) {
    return unavailable;
  }

  const call = fillTemplate("authorization.functions.holdersOf", template, {
    permission: "(notification ->> 'permission')",
    tenant: "v_tenant",
    scope: provider.scope,
  });

  return audienceAppend(needsTenant, named, call);
}

function customAudience(
  ctx: BlockSqlContext,
  needsTenant: string,
  unavailable: string,
  named: string,
): string {
  const template = ctx.modules.permissions?.functions?.holdersOf;

  if (template === undefined) {
    return unavailable;
  }

  const call = fillTemplate(
    "blocks.permissions.functions.holdersOf",
    template,
    { permission: "(notification ->> 'permission')", tenant: "v_tenant" },
  );

  return audienceAppend(needsTenant, named, call);
}

function membershipAudience(
  ctx: BlockSqlContext,
  model: ReturnType<typeof accessModel>,
  needsTenant: string,
  named: string,
): string {
  const members = ctx.of("memberships");
  const user = members.col("memberships", "user");
  const tenant = members.col("memberships", "tenant");
  let platform = "";

  if (
    model === "catalog" &&
    ctx.installed("permissions") &&
    ctx.of("permissions").hasTable("platformAssignments")
  ) {
    const access = ctx.of("permissions");
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
        and ${ctx.scope.canUser(`m.${user}`, "v_tenant", "notification ->> 'permission'")}
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

/**
 * A channel nobody chose is on for `in_app` and off for the rest, unless
 * `channelDefaults` says otherwise.
 */
export function channelDefaults(ctx: BlockSqlContext, channel: string): string {
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
