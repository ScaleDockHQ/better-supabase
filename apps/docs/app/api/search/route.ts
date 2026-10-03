import { search } from "@/lib/search";

/** Browsers keep a query's results for five minutes, the CDN until the next deploy. */
const CACHE_CONTROL =
  "public, max-age=300, s-maxage=31536000, stale-while-revalidate=86400";

export async function GET(request: Request): Promise<Response> {
  const query = new URL(request.url).searchParams.get("query");
  const results = query ? await search(query) : [];
  return Response.json(results, {
    headers: { "Cache-Control": CACHE_CONTROL },
  });
}
