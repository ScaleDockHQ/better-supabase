import type { StandardSchemaV1 } from "better-supabase";

import {
  createNotifications,
  sqlTransport,
} from "better-supabase/blocks/notifications";
import { createOutbox } from "better-supabase/blocks/outbox";
import {
  createWebhooks,
  hmacSigner,
  type WebhookRequest,
  type WebhookTransport,
} from "better-supabase/blocks/webhooks";
import { createHmac } from "node:crypto";
import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import {
  dbUrl,
  email,
  reachable,
  ROLES,
  USERS,
  withCentraKit,
} from "./stack.ts";

const live = await reachable();

const task: StandardSchemaV1<{ title: string }> = {
  "~standard": {
    version: 1,
    vendor: "centrakit",
    validate: (value) => ({ value: value as { title: string } }),
  },
};

describe.skipIf(!live)(
  "notifications, outbox and webhooks on CentraKit's tables",
  () => {
    const pool = new Pool({ connectionString: dbUrl, max: 2 });
    afterAll(() => pool.end());

    it("notifies in workflow_events, relays to webhook_deliveries and signs like CentraKit", async () => {
      await withCentraKit(pool, async (s) => {
        await s.as("owner");
        const organization = await s.value<string>(
          "better_supabase.create_organization($1)",
          [{ name: "Acme", slug: `acme-${USERS.owner.slice(0, 8)}` }],
        );
        await s.as("service");
        await s.rows(
          "insert into centrakit.organization_users (organization_id, user_id, role_id) values ($1, $2, $3)",
          [organization, USERS.member, ROLES.member],
        );

        const emails: { email: string | null; title: string }[] = [];
        const notifications = createNotifications({
          transport: sqlTransport(s.sql),
          types: { "task.assigned": task },
          render: (item) => ({
            title: `Assigned: ${item.subject?.label ?? ""}`,
          }),
          channels: [
            {
              apiVersion: 1,
              name: "email",
              send: (message) => {
                emails.push({
                  email: message.email,
                  title: message.text?.title ?? "",
                });
                return { provider: "postmark", providerMessageId: "pm-1" };
              },
            },
          ],
        });

        await s.as("owner");
        await notifications
          .setPreference({ type: "*", channel: "email", enabled: true })
          .orThrow();
        await s.as("member");
        const id = await notifications
          .send("task.assigned", {
            tenant: organization,
            recipients: [USERS.owner],
            subject: { type: "task", id: "t1", label: "Close the books" },
            data: { title: "Close the books" },
            channels: ["in_app", "email"],
          })
          .orThrow();
        expect(
          await s.rows(
            "select type, organization_id from centrakit.notification_events where id = $1",
            [id],
          ),
        ).toEqual([{ type: "task.assigned", organization_id: organization }]);
        expect(
          await s.rows("select topic from realtime.messages where topic = $1", [
            `organization:${organization}:notifications:${USERS.owner}`,
          ]),
        ).toHaveLength(1);
        expect(
          await s.rows(
            "select source from centrakit.workflow_events where kind = 'notification.created' and organization_id = $1",
            [organization],
          ),
        ).toEqual([{ source: "domain" }]);

        await s.as("owner");
        const [item] = await notifications
          .list({ tenant: organization })
          .orThrow();
        expect(item).toMatchObject({
          eventId: id,
          text: { title: "Assigned: Close the books" },
        });
        expect(
          await notifications.markRead({ tenant: organization }).orThrow(),
        ).toMatchObject({ count: 1, items: [{ eventId: id }] });

        await s.as("service");
        expect(await notifications.deliver()).toEqual({
          sent: 1,
          skipped: 0,
          failed: 0,
        });
        expect(emails).toEqual([
          { email: email("owner"), title: "Assigned: Close the books" },
        ]);
        expect(
          await s.rows(
            "select channel, status from centrakit.notification_deliveries where organization_id = $1 order by channel",
            [organization],
          ),
        ).toEqual([
          { channel: "email", status: "sent" },
          { channel: "in_app", status: "sent" },
        ]);

        await s.as("owner");
        await s.client.query("set local role authenticated");
        const [destination] = await s.rows<{ id: string }>(
          "insert into centrakit.webhook_destinations (organization_id, name, url, event_kinds) values ($1, 'Ledger', 'https://ledger.example.com/hook', '{notification.*}') returning id",
          [organization],
        );
        await s.client.query("reset role");
        const sent: WebhookRequest[] = [];
        const http: WebhookTransport = {
          apiVersion: 1,
          name: "fake",
          send(request) {
            sent.push(request);
            return Promise.resolve({ status: 200, body: "ok" });
          },
        };
        const webhooks = createWebhooks({
          transport: sqlTransport(s.sql),
          http,
          signer: hmacSigner({
            signatureHeader: "x-centrakit-signature",
            timestampHeader: "x-centrakit-timestamp",
          }),
        });
        const secret = await webhooks.rotateSecret(destination!.id).orThrow();
        expect(
          await s.rows(
            "select secret from centrakit.webhook_destination_secrets where destination_id = $1",
            [destination!.id],
          ),
        ).toEqual([{ secret }]);

        await s.as("service");
        // Events written in this transaction share now(), so age them past the settle window.
        await s.rows(
          "update centrakit.workflow_events set created_at = now() - interval '1 minute'",
        );
        const outbox = createOutbox(s.sql, { source: "https://centrakit.app" });
        await outbox
          .register("webhooks", { types: ["notification.*"], fromStart: true })
          .orThrow();
        expect(await outbox.relay("webhooks", webhooks.sink())).toEqual({
          delivered: 1,
        });
        const [delivery] = await s.rows<{
          event_id: string;
          event_kind: string;
        }>(
          "select d.event_id, d.event_kind from centrakit.webhook_deliveries d join centrakit.workflow_events e on e.id = d.event_id where d.destination_id = $1",
          [destination!.id],
        );
        expect(delivery).toMatchObject({ event_kind: "notification.created" });

        expect(await webhooks.deliver()).toMatchObject({
          succeeded: 1,
          retrying: 0,
        });
        const request = sent[0]!;
        const timestamp = request.headers["x-centrakit-timestamp"]!;
        const expected = createHmac("sha256", secret)
          .update(`${timestamp}.${request.body}`)
          .digest("hex");
        expect(request.headers["x-centrakit-signature"]).toBe(`v1=${expected}`);
        expect(
          await s.rows(
            "select status, response_status from centrakit.webhook_deliveries where destination_id = $1",
            [destination!.id],
          ),
        ).toEqual([{ status: "completed", response_status: 200 }]);

        const [run] = await s.rows<{ id: string }>(
          "select id from centrakit.workflow_runs where organization_id = $1",
          [organization],
        );
        const direct = await webhooks
          .dispatch({
            endpointId: destination!.id,
            type: "run.finished",
            data: { ok: true },
            runId: run!.id,
          })
          .orThrow();
        expect(
          await s.rows(
            "select workflow_run_id from centrakit.webhook_deliveries where id = $1",
            [direct],
          ),
        ).toEqual([{ workflow_run_id: run!.id }]);
      });
    });
  },
);
