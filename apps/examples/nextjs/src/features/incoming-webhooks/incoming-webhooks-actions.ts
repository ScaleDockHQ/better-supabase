"use server";

import type { Result } from "better-supabase";

import { dbError, err, ok } from "better-supabase";
import * as v from "valibot";

import { requireCaller, sqlResult } from "@/features/developer/postgres";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { INCOMING_WEBHOOKS_TAG } from "./incoming-webhooks-cache";

const Id = v.pipe(v.string(), v.uuid());

const manage = { requireTenant: true, permission: "webhooks.manage" } as const;

/** What the create call returns; the token and secret are shown once. */
export interface CreatedIncomingWebhook {
  readonly token: string;
  readonly secret: string | null;
}

/** Creates an incoming endpoint as the caller and returns its token once. */
export const createIncomingWebhook = bsb.action(
  {
    ...manage,
    input: v.object({
      name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(100)),
      verify: v.picklist([
        "none",
        "standard-webhooks",
        "hmac-sha256",
        "shared-secret",
      ]),
    }),
  },
  async (
    { name, verify },
    { tenant, session, auth },
  ): Promise<Result<CreatedIncomingWebhook>> => {
    const caller = requireCaller(session);

    if (!caller.ok) {
      return caller;
    }

    const { connection, claims } = caller.data;

    const created = await sqlResult(() =>
      connection
        .asUser(claims)
        .queryRaw<{ row: { token: string; secret: string | null } }>(
          "select better_supabase.create_incoming_webhook($1, $2, $3) as row",
          [tenant, name, verify],
        ),
    );

    if (!created.ok) {
      return created;
    }

    const [first] = created.data;

    if (!first) {
      return err(dbError("not_found", "The endpoint was not created"));
    }

    await refreshCaller(auth, [INCOMING_WEBHOOKS_TAG]);

    return ok({ token: first.row.token, secret: first.row.secret });
  },
);

/** Turns an endpoint on or off. */
export const setIncomingWebhookEnabled = bsb.action(
  { ...manage, input: v.object({ id: Id, enabled: v.boolean() }) },
  async ({ id, enabled }, { session, auth }): Promise<Result<boolean>> => {
    const caller = requireCaller(session);

    if (!caller.ok) {
      return caller;
    }

    const { connection, claims } = caller.data;

    const set = await sqlResult(() =>
      connection
        .asUser(claims)
        .queryRaw(
          "select better_supabase.set_incoming_webhook_enabled($1, $2)",
          [id, enabled],
        ),
    );

    if (!set.ok) {
      return set;
    }

    await refreshCaller(auth, [INCOMING_WEBHOOKS_TAG]);

    return ok(enabled);
  },
);

/** Deletes an endpoint with its secrets. */
export const deleteIncomingWebhook = bsb.action(
  { ...manage, input: v.object({ id: Id }) },
  async ({ id }, { session, auth }): Promise<Result<boolean>> => {
    const caller = requireCaller(session);

    if (!caller.ok) {
      return caller;
    }

    const { connection, claims } = caller.data;

    const deleted = await sqlResult(() =>
      connection
        .asUser(claims)
        .queryRaw<{ deleted: boolean }>(
          "select better_supabase.delete_incoming_webhook($1) as deleted",
          [id],
        ),
    );

    if (!deleted.ok) {
      return deleted;
    }

    if (deleted.data[0]?.deleted !== true) {
      return err(dbError("not_found", "Endpoint not found"));
    }

    await refreshCaller(auth, [INCOMING_WEBHOOKS_TAG]);

    return ok(true);
  },
);
