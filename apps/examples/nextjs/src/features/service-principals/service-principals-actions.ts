"use server";

import { dbError, err, ok } from "better-supabase";
import {
  createServiceAccounts,
  rpcTransport,
} from "better-supabase/blocks/service-accounts";
import * as v from "valibot";

import { can } from "@/features/user/user-permissions";
import { refreshCaller } from "@/lib/refresh-caller";
import { blockConfig } from "@/lib/supabase/blocks.generated";
import { bsb } from "@/lib/supabase/server";

const API_SCHEMA = blockConfig["service-accounts"].api;

/**
 * Registering and disabling a principal are service-role functions; with
 * `createdBy` the SQL still checks that member's `service_principals.manage`
 * and that they may assign the role.
 */
function serviceClient() {
  const admin = bsb.admin().$client;

  return createServiceAccounts({
    transport: rpcTransport(admin, { schema: API_SCHEMA }),
    admin: admin.auth.admin,
    schema: API_SCHEMA,
  });
}

/** Creates a machine identity that workflows and webhooks can run as. */
export const createServicePrincipal = bsb.action(
  {
    input: v.object({
      name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(80)),
      role: v.picklist(["member", "admin"]),
      isDefault: v.boolean(),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "service_principals.manage"),
  },
  async ({ name, role, isDefault }, { tenant, auth }) => {
    if (auth.kind !== "user") {
      return err(dbError("unauthorized", "Sign in to add a service principal"));
    }

    const created = await serviceClient().create(tenant, name, role, {
      default: isDefault,
      createdBy: auth.user.id,
    });

    if (!created.ok) {
      return created;
    }

    refreshCaller(auth);

    return ok(created.data.id);
  },
);

/** Removes a principal's membership, so nothing runs as it any more. */
export const disableServicePrincipal = bsb.action(
  {
    input: v.object({ id: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    authorize: (session) => can(session, "service_principals.manage"),
  },
  async ({ id }, { auth }) => {
    if (auth.kind !== "user") {
      return err(
        dbError("unauthorized", "Sign in to disable a service principal"),
      );
    }

    const disabled = await serviceClient().disable(id, {
      createdBy: auth.user.id,
    });

    if (disabled.ok) {
      refreshCaller(auth);
    }

    return disabled;
  },
);
