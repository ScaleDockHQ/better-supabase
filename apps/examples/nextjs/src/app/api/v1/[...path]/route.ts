import { API_BASE_PATH, apiResources } from "@/features/api/api-resources";
import { loadTables } from "@/features/api/load-tables";
import { betterSupabaseApi } from "@/lib/supabase/api";
import { bsbApi } from "@/lib/supabase/server-api";

/**
 * The REST API as the caller (RLS): customers, projects, tasks and memberships
 * from the app's tables, and the organization's teams and roles from the
 * blocks. Paths outside the map answer 404 before auth resolves. The document
 * is at `/api/v1/openapi.json`. The server is built from the api block set (ADR
 * 0636), not from every block.
 */
await loadTables(betterSupabaseApi, Object.keys(apiResources));

export const { GET, POST, PATCH, PUT, DELETE } = bsbApi.resources(
  apiResources,
  { basePath: API_BASE_PATH },
);
