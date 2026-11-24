import { env } from "@/env";
import { processId, publicRead, remoteRead } from "@/lib/durable-probe";

/**
 * Reads two `"use cache: remote"` entries for tests/next-durable-cache and says
 * which process filled each. Needs `Authorization: Bearer
 * $BSB_TAG_PROBE_SECRET`; without the key, or with one shorter than 32
 * characters, the route does not exist.
 */
export async function GET(request: Request): Promise<Response> {
  const secret = env.BSB_TAG_PROBE_SECRET;

  if (!secret || secret.length < 32) {
    return new Response(null, { status: 404 });
  }

  if (request.headers.get("authorization") !== `Bearer ${secret}`) {
    return new Response(null, { status: 401 });
  }

  const [publicFill, remoteFill] = await Promise.all([
    publicRead(),
    remoteRead(),
  ]);

  return Response.json(
    { process: processId(), public: publicFill, remote: remoteFill },
    { headers: { "cache-control": "no-store" } },
  );
}
