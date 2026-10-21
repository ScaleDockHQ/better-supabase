"use server";

import type { Result } from "better-supabase";

import { dbError, err, ok } from "better-supabase";
import * as v from "valibot";

import { requireCaller, sqlResult } from "@/features/developer/postgres";
import { can } from "@/features/user/user-permissions";
import { blocks } from "@/lib/blocks";
import { refreshCaller } from "@/lib/refresh-caller";
import { bs } from "@/lib/supabase/server";

import { EVENT_PATTERN } from "./webhook-types";

const Id = v.pipe(v.string(), v.uuid());

const CreateEndpoint = v.object({
  name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(100)),
  url: v.pipe(
    v.string(),
    v.trim(),
    v.url(),
    v.startsWith("https://"),
    v.maxLength(2000),
  ),
  eventTypes: v.pipe(
    v.string(),
    v.transform((value) =>
      value
        .split(",")
        .map((each) => each.trim())
        .filter((each) => each !== ""),
    ),
    v.minLength(1),
    v.maxLength(50),
    v.everyItem((each) => EVENT_PATTERN.test(each)),
  ),
});

const manage = { requireTenant: true, authorize: canManage } as const;

function canManage(session: Parameters<typeof can>[0]): boolean {
  return can(session, "webhooks.manage");
}

/**
 * Adds an endpoint and its first signing secret in one transaction, as the
 * caller (RLS checks `webhooks.manage`). The secret is returned once; the
 * module keeps it in Vault.
 */
export const createWebhookEndpoint = bs.action(
  { ...manage, input: CreateEndpoint },
  async (
    { name, url, eventTypes },
    { tenant, session, auth },
  ): Promise<Result<{ id: string; secret: string }>> => {
    const caller = requireCaller(session);

    if (!caller.ok) {
      return caller;
    }

    const { connection, claims } = caller.data;

    const created = await sqlResult(() =>
      connection.transaction(
        async (sql) => {
          const [endpoint] = await sql.queryRaw<{ id: string }>(
            `insert into better_supabase.webhook_endpoints (organization_id, name, url, event_types)
             values ($1, $2, $3, $4) returning id`,
            [tenant, name, url, eventTypes],
          );

          if (!endpoint) {
            throw new Error("The endpoint was not created");
          }

          const [rotated] = await sql.queryRaw<{ secret: string }>(
            "select better_supabase.rotate_webhook_secret($1) as secret",
            [endpoint.id],
          );

          if (!rotated) {
            throw new Error("The endpoint has no signing secret");
          }

          return { id: endpoint.id, secret: rotated.secret };
        },
        { claims },
      ),
    );

    if (created.ok) {
      refreshCaller(auth);
    }

    return created;
  },
);

/** Turns an endpoint on or off. Turning it on clears an automatic disable. */
export const setWebhookEndpointEnabled = bs.action(
  { ...manage, input: v.object({ id: Id, enabled: v.boolean() }) },
  async ({ id, enabled }, { session, auth }): Promise<Result<boolean>> => {
    const caller = requireCaller(session);

    if (!caller.ok) {
      return caller;
    }

    const { connection, claims } = caller.data;

    const updated = await sqlResult(() =>
      connection.asUser(claims).queryRaw(
        `update better_supabase.webhook_endpoints
         set enabled = $2,
             disabled_at = case when $2 then null else now() end,
             disabled_reason = case when $2 then null else 'Turned off in settings' end,
             failing_since = case when $2 then null else failing_since end
         where id = $1
         returning id`,
        [id, enabled],
      ),
    );

    if (!updated.ok) {
      return updated;
    }

    if (updated.data.length === 0) {
      return err(dbError("not_found", "Webhook endpoint not found"));
    }

    refreshCaller(auth);

    return ok(enabled);
  },
);

/** Deletes an endpoint with its deliveries and secrets. */
export const deleteWebhookEndpoint = bs.action(
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
        .queryRaw(
          "delete from better_supabase.webhook_endpoints where id = $1 returning id",
          [id],
        ),
    );

    if (!deleted.ok) {
      return deleted;
    }

    if (deleted.data.length === 0) {
      return err(dbError("not_found", "Webhook endpoint not found"));
    }

    refreshCaller(auth);

    return ok(true);
  },
);

/** Queues a `webhook.test` event for one endpoint, outside its filters. */
export const sendTestWebhook = bs.action(
  { ...manage, input: v.object({ id: Id }) },
  async ({ id }, { supabase, auth }) => {
    const sent = await blocks(supabase).webhooks.dispatch({
      endpointId: id,
      type: "webhook.test",
      data: { message: "A test event from the webhooks settings page" },
    });

    if (sent.ok) {
      refreshCaller(auth);
    }

    return sent;
  },
);

/** Queues a finished delivery again (`redeliver_webhook`). */
export const redeliverWebhook = bs.action(
  { ...manage, input: v.object({ id: Id }) },
  async ({ id }, { supabase, auth }) => {
    const queued = await blocks(supabase).webhooks.redeliver(id);

    if (queued.ok) {
      refreshCaller(auth);
    }

    return queued;
  },
);
