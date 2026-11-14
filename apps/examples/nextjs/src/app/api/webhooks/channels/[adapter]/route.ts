import { isChannelAdapter } from "@/features/inbox/channel-signatures";
import {
  handleChannelWebhook,
  whatsappHandshake,
} from "@/features/inbox/channel-webhook";

/**
 * `GET /api/webhooks/channels/whatsapp`: Meta's verification handshake. Every
 * other adapter takes `POST` only.
 */
export async function GET(
  request: Request,
  { params }: RouteContext<"/api/webhooks/channels/[adapter]">,
): Promise<Response> {
  const { adapter } = await params;

  return adapter === "whatsapp"
    ? whatsappHandshake(request)
    : new Response("method not allowed", { status: 405 });
}

/**
 * `POST /api/webhooks/channels/<adapter>?inbox=<id>`: a WhatsApp or Slack
 * event. It is verified with the platform's secret, stored for replay and
 * answered at once.
 */
export async function POST(
  request: Request,
  { params }: RouteContext<"/api/webhooks/channels/[adapter]">,
): Promise<Response> {
  const { adapter } = await params;

  return isChannelAdapter(adapter)
    ? handleChannelWebhook(adapter, request)
    : new Response("not found", { status: 404 });
}
