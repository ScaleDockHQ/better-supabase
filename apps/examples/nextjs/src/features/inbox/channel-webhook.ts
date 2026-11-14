import "server-only";
import { webhook } from "better-supabase/chat-sdk";
import * as v from "valibot";

import { env } from "@/env";
import { bsbShell } from "@/lib/supabase/server-shell";

import type { ChannelAdapterName } from "./channel-signatures";

import { verifySlack, verifyWhatsapp } from "./channel-signatures";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/iu;

/** Meta's GET handshake: echo the challenge when the verify token matches. */
export function whatsappHandshake(request: Request): Response {
  const query = new URL(request.url).searchParams;
  const token = env.WHATSAPP_VERIFY_TOKEN;

  if (
    token === undefined ||
    query.get("hub.mode") !== "subscribe" ||
    query.get("hub.verify_token") !== token
  ) {
    return new Response("forbidden", { status: 403 });
  }

  return new Response(query.get("hub.challenge") ?? "", { status: 200 });
}

/**
 * Stores a verified platform event in `inbox_inbound_events` and answers at
 * once; the webhook events sheet shows it and `maintain` replays it. Register
 * `/api/webhooks/channels/<adapter>?inbox=<inbox id>` with the platform. A
 * deployment without the platform's secret answers 503.
 */
export async function handleChannelWebhook(
  adapter: ChannelAdapterName,
  request: Request,
): Promise<Response> {
  const secret =
    adapter === "whatsapp" ? env.WHATSAPP_APP_SECRET : env.SLACK_SIGNING_SECRET;

  if (secret === undefined) {
    return new Response(`${adapter} is not configured`, { status: 503 });
  }

  const inboxId = new URL(request.url).searchParams.get("inbox") ?? undefined;

  if (inboxId !== undefined && !UUID.test(inboxId)) {
    return new Response("invalid inbox", { status: 400 });
  }

  const options: Parameters<typeof webhook>[0] = {
    inbox: bsbShell.admin().inbox,
    adapter,
    verify: (incoming, body) =>
      adapter === "whatsapp"
        ? verifyWhatsapp(secret, incoming, body)
        : verifySlack(secret, incoming, body, Date.now() / 1000),
    passthroughHandler: async (incoming) =>
      adapter === "whatsapp"
        ? whatsappHandshake(incoming)
        : slackChallenge(incoming),
  };

  const handle = webhook(
    inboxId === undefined ? options : { ...options, inboxId },
  );

  return handle(request);
}

/** Slack's `url_verification` handshake: answer with the challenge text. */
async function slackChallenge(request: Request): Promise<Response> {
  const parsed = v.safeParse(
    v.object({ challenge: v.string() }),
    await request.json().catch(() => null),
  );

  const challenge = parsed.success ? parsed.output.challenge : null;

  return challenge === null
    ? new Response("not found", { status: 404 })
    : new Response(challenge, { status: 200 });
}
