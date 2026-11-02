import { env } from "@/env";
import {
  tickAdmission,
  tickSchedules,
} from "@/features/workflows/workflow-ticks";

/**
 * Starts due schedules (the sample workflows and builder graphs) and queued
 * admission requests. Call it every minute from a cron (Vercel Cron sends
 * `Authorization: Bearer $CRON_SECRET`).
 */
export async function GET(request: Request): Promise<Response> {
  const secret = env.CRON_SECRET;

  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) {
    return new Response(null, { status: 401 });
  }

  const [schedules, admission] = await Promise.all([
    tickSchedules().orThrow(),
    tickAdmission().orThrow(),
  ]);

  return Response.json({ schedules, admission });
}
