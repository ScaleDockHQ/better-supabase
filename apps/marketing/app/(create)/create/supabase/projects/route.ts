import {
  type CreatedProjectResponse,
  generatePassword,
  type ProjectsResponse,
} from "better-supabase/create";
import { SMART_REGIONS } from "better-supabase/create/supabase";
import * as v from "valibot";

import {
  errorResponse,
  sameOrigin,
  withSupabase,
} from "@/lib/supabase-session";

const NO_STORE = { "Cache-Control": "no-store" };

const createBody = v.object({
  organizationSlug: v.pipe(v.string(), v.minLength(1)),
  name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(64)),
  region: v.picklist(SMART_REGIONS),
});

/** The visitor's Supabase organizations and projects. */
export function GET(): Promise<Response> {
  return withSupabase(async (client) => {
    const [organizations, projects] = await Promise.all([
      client.organizations(),
      client.projects(),
    ]);

    const body: ProjectsResponse = { organizations, projects };

    return Response.json(body, { headers: NO_STORE });
  });
}

/**
 * Creates a project in one of the visitor's organizations with a generated
 * database password, which the response carries once and nothing stores.
 */
export async function POST(request: Request): Promise<Response> {
  if (!sameOrigin(request)) {
    return errorResponse("invalid", "Cross-site request.", 403);
  }

  const parsed = v.safeParse(
    createBody,
    await request.json().catch(() => null),
  );

  if (!parsed.success) {
    return errorResponse(
      "invalid",
      "Pick an organization, a name and a region.",
      400,
    );
  }

  const input = parsed.output;

  return withSupabase(async (client) => {
    const dbPassword = generatePassword();

    const project = await client.createProject({
      name: input.name,
      organizationSlug: input.organizationSlug,
      region: input.region,
      dbPass: dbPassword,
    });

    const body: CreatedProjectResponse = { project, dbPassword };

    return Response.json(body, { status: 201, headers: NO_STORE });
  });
}
