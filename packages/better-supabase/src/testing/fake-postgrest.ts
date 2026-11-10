import type { FakeHandler, FakeRequest } from "./fake-client.ts";

const METHODS: ReadonlySet<string> = new Set([
  "GET",
  "HEAD",
  "POST",
  "PATCH",
  "DELETE",
]);

/** What `createFakePostgrest` returns. */
export interface FakePostgrest {
  /**
   * A `fetch` that answers PostgREST requests (`/rest/v1/<table>` and
   * `/rest/v1/rpc/<name>`) from the handler. Pass it to `createClient`'s
   * `global.fetch`, to `asUser`'s `fetch` option or to a repository.
   */
  readonly fetch: typeof fetch;
  /** Every request the fetch answered, as the handler saw it. */
  readonly requests: readonly FakeRequest[];
}

function json(
  status: number,
  body: unknown,
  headers: Readonly<Record<string, string>> = {},
): Response {
  return new Response(body === undefined ? null : JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...headers },
  });
}

/**
 * A PostgREST stand-in at the `fetch` level, so the real supabase-js client
 * (and its URL building, headers and error handling) runs in a test with no
 * stack. The handler returns the rows or an error for each request, like
 * `createFakeClient`'s handler. It answers `Prefer: count=exact` with a
 * `Content-Range` header, and `.single()` like PostgREST does (406 and
 * `PGRST116` unless exactly one row matches).
 *
 * ```ts
 * const api = createFakePostgrest((request) => ({ data: [{ id: 1 }] }));
 * const client = createClient(url, key, { global: { fetch: api.fetch } });
 * ```
 */
export function createFakePostgrest(handler: FakeHandler): FakePostgrest {
  const requests: FakeRequest[] = [];

  const answer = async (
    input: Request | string | URL,
    init?: RequestInit,
  ): Promise<Response> => {
    const request = new Request(input, init);
    const url = new URL(request.url);
    const asked = request.method.toUpperCase();
    const method = asked === "HEAD" ? "GET" : asked;

    if (!METHODS.has(asked)) {
      return json(405, { message: `Method ${asked} is not supported` });
    }

    const path = url.pathname.replace(/^\/rest\/v1/, "") || "/";
    const text = await request.text();

    const prefer = (request.headers.get("prefer") ?? "")
      .split(",")
      .map((part) => part.trim())
      .filter((part) => part.length > 0);

    const body: unknown = text.length > 0 ? JSON.parse(text) : undefined;

    const seen: FakeRequest = {
      // SAFETY: `METHODS` holds the four verbs `FakeRequest` allows, plus HEAD, which became GET above.
      method: method as FakeRequest["method"],
      path,
      schema:
        request.headers.get(
          method === "GET" ? "accept-profile" : "content-profile",
        ) ??
        request.headers.get("accept-profile") ??
        "public",
      query: Object.fromEntries(url.searchParams),
      ...(body === undefined ? {} : { body }),
      prefer: prefer.filter((part) => !part.startsWith("count=")),
    };

    requests.push(seen);

    const reply = await handler(seen);

    if (reply.error) {
      return json(400, {
        message: reply.error.message,
        code: reply.error.code ?? "",
        details: reply.error.details ?? null,
        hint: reply.error.hint ?? null,
      });
    }

    const rows = Array.isArray(reply.data) ? reply.data : undefined;

    const wantsObject = (request.headers.get("accept") ?? "").includes(
      "vnd.pgrst.object",
    );

    const headers: Record<string, string> = {};

    if (prefer.includes("count=exact") || prefer.includes("count=estimated")) {
      const total = reply.count ?? rows?.length ?? 0;
      headers["content-range"] =
        `${rows && rows.length > 0 ? `0-${String(rows.length - 1)}` : "*"}/${String(total)}`;
    }

    if (wantsObject) {
      if (rows?.length !== 1) {
        return json(406, {
          message: "JSON object requested, multiple (or no) rows returned",
          code: "PGRST116",
          details: `The result contains ${String(rows?.length ?? 0)} rows`,
          hint: null,
        });
      }

      return json(200, rows[0], headers);
    }

    const returnsBody =
      method === "GET" ||
      path.startsWith("/rpc/") ||
      prefer.includes("return=representation");

    if (!returnsBody || reply.data === undefined) {
      return new Response(null, {
        status: method === "GET" ? 200 : 204,
        headers,
      });
    }

    return json(
      method === "POST" && !path.startsWith("/rpc/") ? 201 : 200,
      reply.data,
      headers,
    );
  };

  return { fetch: answer, requests };
}
