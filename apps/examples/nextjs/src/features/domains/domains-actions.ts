"use server";

import type { Result } from "better-supabase";
import type { Hostname } from "better-supabase/blocks/domains";

import { dbError, err, ok } from "better-supabase";
import { rpcTransport } from "better-supabase/blocks";
import { createDomainsAdmin } from "better-supabase/blocks/domains";
import * as v from "valibot";

import { requireCaller, sqlResult } from "@/features/developer/postgres";
import { refreshCaller } from "@/lib/refresh-caller";
import { serviceSupabase } from "@/lib/service-supabase";
import { blockConfig } from "@/lib/supabase/blocks.config";
import { bsb } from "@/lib/supabase/server";

import { DOMAINS_TAG } from "./domains-cache";

const Id = v.pipe(v.string(), v.uuid());

const manage = { requireTenant: true, permission: "domains.manage" } as const;

/** Adds a hostname as the caller (`add_hostname` checks `domains.manage`). */
export const addDomain = bsb.action(
  {
    ...manage,
    input: v.object({
      hostname: v.pipe(v.string(), v.trim(), v.minLength(3), v.maxLength(253)),
    }),
  },
  async (
    { hostname },
    { tenant, session, auth },
  ): Promise<Result<{ id: string }>> => {
    const caller = requireCaller(session);

    if (!caller.ok) {
      return caller;
    }

    const { connection, claims } = caller.data;

    const added = await sqlResult(() =>
      connection
        .asUser(claims)
        .queryRaw<{ row: { id: string } }>(
          "select better_supabase.add_hostname($1, $2) as row",
          [tenant, hostname],
        ),
    );

    if (!added.ok) {
      return added;
    }

    const [first] = added.data;

    if (!first) {
      return err(dbError("not_found", "The hostname was not added"));
    }

    await refreshCaller(auth, [DOMAINS_TAG]);

    return ok({ id: first.row.id });
  },
);

/** Makes a verified hostname the organization's primary one. */
export const setPrimaryDomain = bsb.action(
  { ...manage, input: v.object({ id: Id }) },
  async ({ id }, { session, auth }): Promise<Result<boolean>> => {
    const caller = requireCaller(session);

    if (!caller.ok) {
      return caller;
    }

    const { connection, claims } = caller.data;

    const set = await sqlResult(() =>
      connection
        .asUser(claims)
        .queryRaw("select better_supabase.set_primary_hostname($1)", [id]),
    );

    if (!set.ok) {
      return set;
    }

    await refreshCaller(auth, [DOMAINS_TAG]);

    return ok(true);
  },
);

/** Removes a hostname the caller manages. */
export const removeDomain = bsb.action(
  { ...manage, input: v.object({ id: Id }) },
  async ({ id }, { session, auth }): Promise<Result<boolean>> => {
    const caller = requireCaller(session);

    if (!caller.ok) {
      return caller;
    }

    const { connection, claims } = caller.data;

    const removed = await sqlResult(() =>
      connection
        .asUser(claims)
        .queryRaw<{ removed: boolean }>(
          "select better_supabase.remove_hostname($1) as removed",
          [id],
        ),
    );

    if (!removed.ok) {
      return removed;
    }

    if (removed.data[0]?.removed !== true) {
      return err(dbError("not_found", "Hostname not found"));
    }

    await refreshCaller(auth, [DOMAINS_TAG]);

    return ok(true);
  },
);

/**
 * Looks up the TXT record and marks the hostname verified. `verify_hostname` is
 * service-role only, so the block's admin client runs it with the caller as
 * `actorId`, and the database checks that they hold `domains.manage`.
 */
export const verifyDomain = bsb.action(
  { ...manage, input: v.object({ id: Id }) },
  async ({ id }, { auth }): Promise<Result<Hostname>> => {
    if (auth.kind !== "user") {
      return err(dbError("unauthorized", "Sign in to verify a domain"));
    }

    const domains = createDomainsAdmin({
      transport: rpcTransport(serviceSupabase(), {
        schema: blockConfig.domains.api,
      }),
    });

    const verified = await domains.verify({
      hostnameId: id,
      actorId: auth.user.id,
    });

    if (verified.ok) {
      await refreshCaller(auth, [DOMAINS_TAG]);
    }

    return verified;
  },
);
