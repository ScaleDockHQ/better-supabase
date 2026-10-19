import type { ProjectStatusResponse } from "better-supabase/create";

import { isProjectRef } from "better-supabase/create/supabase";

import { errorResponse, withSupabase } from "@/lib/supabase-session";

/**
 * Whether a project's database accepts the deploy yet, and how many tables
 * `public` already has, so the dialog can ask before deploying over them.
 */
export async function GET(
  _request: Request,
  { params }: { params: Promise<{ ref: string }> },
): Promise<Response> {
  const { ref } = await params;

  if (!isProjectRef(ref)) {
    return errorResponse("invalid", "That isn't a project ref.", 400);
  }

  return withSupabase(async (client) => {
    const project = await client.project(ref);

    const ready =
      project.status === "ACTIVE_HEALTHY" &&
      (await client.databaseHealthy(ref));

    const body: ProjectStatusResponse = {
      project,
      ready,
      publicTables: ready ? await client.publicTableCount(ref) : null,
    };

    return Response.json(body, { headers: { "Cache-Control": "no-store" } });
  });
}
