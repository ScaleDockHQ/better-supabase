import { mailSync } from "@/features/crm/mail-server";

/**
 * Opens (`/o/<token>`) and clicks (`/c/<token>/<n>`) of tracked mail. The token
 * is the only secret, so the route is public and runs as the service role.
 */
export async function GET(request: Request): Promise<Response> {
  const tracked = await mailSync().track(request);

  return tracked.ok ? tracked.data : new Response(null, { status: 503 });
}
