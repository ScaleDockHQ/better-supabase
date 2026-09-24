import { createClient, type SupabaseClient } from '@supabase/supabase-js';

export interface CapturedRequest {
  readonly method: string;
  readonly path: string;
  readonly params: URLSearchParams;
  readonly headers: Headers;
  readonly body: unknown;
}

export type Responder = (request: CapturedRequest) => {
  readonly status?: number;
  readonly body?: unknown;
  readonly headers?: Record<string, string>;
};

/**
 * A real supabase-js client whose `fetch` records requests and answers from
 * `respond`. Tests assert on the exact PostgREST URL.
 */
export function capturingClient(respond: Responder = () => ({ body: [] })): {
  client: SupabaseClient;
  requests: CapturedRequest[];
  last: () => CapturedRequest;
} {
  const requests: CapturedRequest[] = [];
  const fetch = async (
    input: RequestInfo | URL,
    init?: RequestInit,
  ): Promise<Response> => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    const headers = new Headers(init?.headers);
    const request: CapturedRequest = {
      method: init?.method ?? 'GET',
      path: url.pathname,
      params: url.searchParams,
      headers,
      body: typeof init?.body === 'string' ? JSON.parse(init.body) : undefined,
    };
    requests.push(request);
    const answer = respond(request);
    const status = answer.status ?? 200;
    return new Response(
      status === 204 ? null : JSON.stringify(answer.body ?? []),
      {
        status,
        headers: { 'content-type': 'application/json', ...answer.headers },
      },
    );
  };
  const client = createClient('http://localhost:54321', 'sb_publishable_test', {
    global: { fetch },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return {
    client,
    requests,
    last: () => {
      const request = requests.at(-1);
      if (!request) throw new Error('No request captured');
      return request;
    },
  };
}

/** Query string with decoded values, for readable assertions. */
export function query(request: CapturedRequest): string[] {
  return [...request.params.entries()].map(([key, value]) => `${key}=${value}`);
}
