import { createOpenApi } from "better-supabase/spec";

import { API_BASE_PATH, apiResources } from "@/features/api/api-resources";
import { betterSupabase } from "@/lib/supabase";

/**
 * The OpenAPI 3.1 document of `/api/v1`, from the same resource map the routes
 * serve, so the two can't drift. Built once per server instance.
 */
const document = createOpenApi(betterSupabase, {
  info: { title: "Example SaaS API", version: "1.0.0" },
  basePath: API_BASE_PATH,
  resources: apiResources,
  blocks: false,
});

export function GET(): Response {
  return Response.json(document);
}
