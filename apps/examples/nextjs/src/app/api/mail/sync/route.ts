import { mailSync } from "@/features/crm/mail-server";

/**
 * Pulls new mail into the mailboxes not synced in the last five minutes. Call
 * it every few minutes from a cron (Vercel Cron sends `Authorization: Bearer
 * $CRON_SECRET`).
 */
export async function GET(request: Request): Promise<Response> {
  const secret = process.env["CRON_SECRET"];

  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) {
    return new Response(null, { status: 401 });
  }

  const report = await mailSync().syncDue().orThrow();

  return Response.json(report);
}
