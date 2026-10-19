import {
  previewFiles,
  deployBlocker,
  deployQuery,
  type DeployResponse,
  MIGRATION_NAME,
} from "better-supabase/create";
import {
  isProjectRef,
  type SupabaseLint,
} from "better-supabase/create/supabase";
import {
  decodeDesign,
  isDesignCode,
  isPresetCode,
  presetOf,
} from "better-supabase/preset";
import * as v from "valibot";

import {
  errorResponse,
  sameOrigin,
  withSupabase,
} from "@/lib/supabase-session";

const deployBody = v.object({
  ref: v.string(),
  preset: v.string(),
  design: v.optional(v.string(), ""),
  confirm: v.optional(v.boolean(), false),
});

/**
 * Renders the preset's SQL on the server, the same files `/create/migrations`
 * shows, and applies them to the project as one migration, so a failure
 * rolls all of it back. It refuses a `public` schema that already has
 * tables unless the request confirms it.
 */
export async function POST(request: Request): Promise<Response> {
  if (!sameOrigin(request)) {
    return errorResponse("invalid", "Cross-site request.", 403);
  }

  const parsed = v.safeParse(
    deployBody,
    await request.json().catch(() => null),
  );

  if (
    !parsed.success ||
    !isProjectRef(parsed.output.ref) ||
    !isPresetCode(parsed.output.preset) ||
    (parsed.output.design !== "" && !isDesignCode(parsed.output.design))
  ) {
    return errorResponse(
      "invalid",
      "Send a project, a preset and a design.",
      400,
    );
  }

  const { ref, preset, design, confirm } = parsed.output;
  const blocker = deployBlocker(presetOf(preset));

  if (blocker !== undefined) {
    return errorResponse("blocked", blocker, 422);
  }

  const files = previewFiles(preset, await decodeDesign(design));

  return withSupabase(async (client) => {
    if (!confirm && (await client.publicTableCount(ref)) > 0) {
      return errorResponse(
        "confirm",
        "The public schema already has tables. Confirm to deploy over them.",
        409,
      );
    }

    await client.applyMigration(ref, MIGRATION_NAME, deployQuery(files));

    // The advisor is a report on top of a deploy that already succeeded.
    const lints: readonly SupabaseLint[] = await client
      .securityLints(ref)
      .catch(() => []);

    const body: DeployResponse = { ref, migration: MIGRATION_NAME, lints };

    return Response.json(body, { headers: { "Cache-Control": "no-store" } });
  });
}
