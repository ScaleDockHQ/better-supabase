import {
  PERMDOCK_API,
  permdockAccessToken,
  permdockConfig,
} from "@/lib/permdock-session";
import { errorResponse } from "@/lib/supabase-session";

const NO_STORE = { "Cache-Control": "no-store" };

/** The connected visitor's projects, so the Create page can pick one. */
export async function GET(): Promise<Response> {
  const config = permdockConfig();

  if (config === undefined) {
    return errorResponse("invalid", "This connection is turned off.", 404);
  }

  const token = await permdockAccessToken(config);

  if (token === undefined) {
    return errorResponse("connect", "Connect your account.", 401);
  }

  const response = await fetch(new URL("projects", `${PERMDOCK_API}/`), {
    cache: "no-store",
    headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
  });

  if (response.status === 401) {
    return errorResponse("connect", "Connect your account again.", 401);
  }

  if (!response.ok) {
    return errorResponse("supabase", "The projects could not be loaded.", 502);
  }

  return Response.json(await response.json(), { headers: NO_STORE });
}
