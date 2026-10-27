"use server";

import type { SsoAdmin } from "better-supabase/blocks/sso";

import { dbError, err, ok } from "better-supabase";
import { rpcTransport } from "better-supabase/blocks";
import { createSsoAdmin } from "better-supabase/blocks/sso";
import { refresh } from "next/cache";
import * as v from "valibot";

import { env } from "@/env";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { refreshCaller } from "@/lib/refresh-caller";
import { blockConfig } from "@/lib/supabase/blocks.generated";
import { bsb } from "@/lib/supabase/server";

const DOMAIN = v.pipe(
  v.string(),
  v.trim(),
  v.toLowerCase(),
  v.regex(/^(?=.{3,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/u),
);

/**
 * Domain verification and SAML providers run with the service role, so the
 * actions pass the caller as `actorId` and the database checks `sso.manage`.
 */
function ssoAdmin(): SsoAdmin | null {
  const url = env.NEXT_PUBLIC_SUPABASE_URL;
  const secretKey = env.SUPABASE_SECRET_KEY;

  if (!url || !secretKey) {
    return null;
  }

  return createSsoAdmin({
    transport: rpcTransport(bsb.admin().$client, {
      schema: blockConfig.sso.api,
    }),
    schema: blockConfig.sso.api,
    auth: { url, secretKey },
  });
}

const NO_ADMIN = dbError(
  "invalid_request",
  "Set SUPABASE_SECRET_KEY to verify domains and manage SAML",
  { hint: "SSO_ADMIN_MISSING" },
);

export const addSsoDomain = bsb.action(
  {
    input: v.object({ domain: DOMAIN }),
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "sso.manage"),
  },
  async ({ domain }, { tenant, db, auth }) => {
    const added = await db.sso.addDomain(tenant, domain);

    if (!added.ok) {
      return added;
    }

    await refreshCaller(auth);

    return ok(added.data.id);
  },
);

export const removeSsoDomain = bsb.action(
  {
    input: v.object({ id: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "sso.manage"),
  },
  async ({ id }, { db, auth }) => {
    const removed = await db.sso.removeDomain(id);

    if (!removed.ok) {
      return removed;
    }

    await refreshCaller(auth);

    return ok(removed.data);
  },
);

export const verifySsoDomain = bsb.action(
  {
    input: v.object({ id: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "sso.manage"),
  },
  async ({ id }, { auth }) => {
    const admin = ssoAdmin();

    if (!admin) {
      return err(NO_ADMIN);
    }

    if (auth.kind !== "user") {
      return err(dbError("unauthorized", "Sign in to verify a domain"));
    }

    const verified = await admin.verifyDomain(id, { actorId: auth.user.id });

    if (!verified.ok) {
      return verified;
    }

    await refreshCaller(auth);

    return ok(verified.data.verifiedAt !== undefined);
  },
);

interface DomainSettingsDraft {
  autoJoinRole?: string | null;
  enforceSso?: boolean;
}

export const updateSsoDomain = bsb.action(
  {
    input: v.object({
      id: v.pipe(v.string(), v.uuid()),
      autoJoinRole: v.optional(v.nullable(v.picklist(["member", "admin"]))),
      enforceSso: v.optional(v.boolean()),
    }),
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "sso.manage"),
  },
  async ({ id, autoJoinRole, enforceSso }, { db, auth }) => {
    const settings: DomainSettingsDraft = {};

    if (autoJoinRole !== undefined) {
      settings.autoJoinRole = autoJoinRole;
    }

    if (enforceSso !== undefined) {
      settings.enforceSso = enforceSso;
    }

    const updated = await db.sso.updateDomain(id, settings);

    if (!updated.ok) {
      return updated;
    }

    await refreshCaller(auth);

    return ok(updated.data.id);
  },
);

export const addSamlConnection = bsb.action(
  {
    input: v.object({
      metadataUrl: v.pipe(
        v.string(),
        v.trim(),
        v.url(),
        v.startsWith("https://"),
      ),
      domains: v.pipe(v.array(DOMAIN), v.minLength(1)),
    }),
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "sso.manage"),
  },
  async ({ metadataUrl, domains }, { tenant, auth }) => {
    const admin = ssoAdmin();

    if (!admin) {
      return err(NO_ADMIN);
    }

    if (auth.kind !== "user") {
      return err(dbError("unauthorized", "Sign in to add a connection"));
    }

    const added = await admin.addSamlProvider(
      tenant,
      { metadataUrl, domains },
      { actorId: auth.user.id },
    );

    if (!added.ok) {
      return added;
    }

    await refreshCaller(auth);

    return ok(added.data.id);
  },
);

export const removeSamlConnection = bsb.action(
  {
    input: v.object({ id: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "sso.manage"),
  },
  async ({ id }, { auth }) => {
    const admin = ssoAdmin();

    if (!admin) {
      return err(NO_ADMIN);
    }

    if (auth.kind !== "user") {
      return err(dbError("unauthorized", "Sign in to remove a connection"));
    }

    const removed = await admin.removeSamlProvider(id, {
      actorId: auth.user.id,
    });

    if (!removed.ok) {
      return removed;
    }

    await refreshCaller(auth);

    return ok(removed.data !== undefined);
  },
);

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
export async function refreshSso() {
  refresh();
}
