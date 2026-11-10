import { createOpenApi } from "better-supabase/spec";

import { API_BASE_PATH, apiResources } from "@/features/api/api-resources";
import { loadTables } from "@/features/api/load-tables";
import { betterSupabaseApi } from "@/lib/supabase/api";
import { bsbApi } from "@/lib/supabase/server-api";

/**
 * The OpenAPI 3.1 document of `/api/v1`, from the same resource map the routes
 * serve, so the two can't drift. Built once per server instance. Creating the
 * api server installs the connection runtime (ADR 0635) that `loadTables`
 * needs; without it the build passes only when another route in the same worker
 * has installed it. No request goes through the server here.
 */
void bsbApi;

await loadTables(betterSupabaseApi, Object.keys(apiResources));

const document = createOpenApi(betterSupabaseApi, {
  info: { title: "Example SaaS API", version: "1.0.0" },
  basePath: API_BASE_PATH,
  resources: apiResources,
  blocks: false,
});

export function GET(): Response {
  return Response.json(document);
}
