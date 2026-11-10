import { API_BASE_PATH, apiResources } from "@/features/api/api-resources";
import { loadTables } from "@/features/api/load-tables";
import { betterSupabaseCore } from "@/lib/supabase/core";
import { bsb } from "@/lib/supabase/server";

/**
 * The REST API as the caller (RLS): customers, projects, tasks and memberships
 * from the app's tables, and the organization's teams and roles from the
 * blocks. Paths outside the map answer 404 before auth resolves. The document
 * is at `/api/v1/openapi.json`.
 */
await loadTables(betterSupabaseCore, Object.keys(apiResources));

export const { GET, POST, PATCH, PUT, DELETE } = bsb.resources(apiResources, {
  basePath: API_BASE_PATH,
});
