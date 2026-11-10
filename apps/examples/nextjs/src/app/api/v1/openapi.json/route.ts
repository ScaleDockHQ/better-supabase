import { createOpenApi } from "better-supabase/spec";

import { API_BASE_PATH, apiResources } from "@/features/api/api-resources";
import { loadTables } from "@/features/api/load-tables";
import { betterSupabaseCore } from "@/lib/supabase/core";

/**
 * The OpenAPI 3.1 document of `/api/v1`, from the same resource map the routes
 * serve, so the two can't drift. Built once per server instance.
 */
await loadTables(betterSupabaseCore, Object.keys(apiResources));

const document = createOpenApi(betterSupabaseCore, {
  info: { title: "Example SaaS API", version: "1.0.0" },
  basePath: API_BASE_PATH,
  resources: apiResources,
  blocks: false,
});

export function GET(): Response {
  return Response.json(document);
}
