"use server";

import { dbError, err, ok } from "better-supabase";
import { rpcTransport } from "better-supabase/blocks";
import { createSsoAdmin, type SsoAdmin } from "better-supabase/blocks/sso";
import { refresh } from "next/cache";
import * as v from "valibot";

import { can } from "@/features/user/user-permissions";
import { blocks } from "@/lib/blocks";
import { refreshCaller } from "@/lib/refresh-caller";
import { blockConfig } from "@/lib/supabase/blocks.generated";
import { bs } from "@/lib/supabase/server";

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
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const secretKey = process.env["SUPABASE_SECRET_KEY"];

  if (!url || !secretKey) {
    return null;
  }

  return createSsoAdmin({
    transport: rpcTransport(bs.admin().$client, {
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

export const addSsoDomain = bs.action(
  {
    input: v.object({ domain: DOMAIN }),
    requireTenant: true,
    authorize: (session) => can(session, "sso.manage"),
  },
  async ({ domain }, { tenant, supabase, auth }) => {
    const added = await blocks(supabase).sso.addDomain(tenant, domain);

    if (!added.ok) {
      return added;
    }

    refreshCaller(auth);

    return ok(added.data.id);
  },
);

export const removeSsoDomain = bs.action(
  {
    input: v.object({ id: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    authorize: (session) => can(session, "sso.manage"),
  },
  async ({ id }, { supabase, auth }) => {
    const removed = await blocks(supabase).sso.removeDomain(id);

    if (!removed.ok) {
      return removed;
    }

    refreshCaller(auth);

    return ok(removed.data);
  },
);

export const verifySsoDomain = bs.action(
  {
    input: v.object({ id: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    authorize: (session) => can(session, "sso.manage"),
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

    refreshCaller(auth);

    return ok(verified.data.verifiedAt !== undefined);
  },
);

interface DomainSettingsDraft {
  autoJoinRole?: string | null;
  enforceSso?: boolean;
}

export const updateSsoDomain = bs.action(
  {
    input: v.object({
      id: v.pipe(v.string(), v.uuid()),
      autoJoinRole: v.optional(v.nullable(v.picklist(["member", "admin"]))),
      enforceSso: v.optional(v.boolean()),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "sso.manage"),
  },
  async ({ id, autoJoinRole, enforceSso }, { supabase, auth }) => {
    const settings: DomainSettingsDraft = {};

    if (autoJoinRole !== undefined) {
      settings.autoJoinRole = autoJoinRole;
    }

    if (enforceSso !== undefined) {
      settings.enforceSso = enforceSso;
    }

    const updated = await blocks(supabase).sso.updateDomain(id, settings);

    if (!updated.ok) {
      return updated;
    }

    refreshCaller(auth);

    return ok(updated.data.id);
  },
);

export const addSamlConnection = bs.action(
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
    authorize: (session) => can(session, "sso.manage"),
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

    refreshCaller(auth);

    return ok(added.data.id);
  },
);

export const removeSamlConnection = bs.action(
  {
    input: v.object({ id: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    authorize: (session) => can(session, "sso.manage"),
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

    refreshCaller(auth);

    return ok(removed.data !== undefined);
  },
);

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
export async function refreshSso() {
  refresh();
}
