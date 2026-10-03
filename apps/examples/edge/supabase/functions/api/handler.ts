import { createEdge } from "better-supabase/edge";

import { betterSupabase } from "../_shared/supabase.ts";

const bs = createEdge(betterSupabase, { cors: true });

const me = bs.handler((_request, { auth }) => ({ kind: auth.kind }));

const resources = bs.resources(
  {
    customers: { select: ["id", "name", "status", "organizationId"] },
    tags: true,
  },
  { basePath: "/api" },
);

export const handler = (request: Request): Promise<Response> =>
  new URL(request.url).pathname === "/api/me"
    ? me(request)
    : resources(request);
