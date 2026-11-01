export interface FakeCall {
  readonly method: string;
  readonly path: string;
  readonly body: unknown;
  readonly headers: Headers;
}

export interface FakeReply {
  readonly status?: number;
  readonly json?: unknown;
}

/**
 * A `fetch` that answers from a function and records the calls, so an adapter
 * test needs no network and no provider account.
 */
export function fakeFetch(answer: (call: FakeCall) => FakeReply): {
  readonly fetch: typeof fetch;
  readonly calls: FakeCall[];
} {
  const calls: FakeCall[] = [];

  const handler = async (
    input: Parameters<typeof fetch>[0],
    init?: Parameters<typeof fetch>[1],
  ): Promise<Response> => {
    const url = new URL(
      input instanceof Request ? input.url : String(input),
      "https://provider.test",
    );

    const raw = init?.body;
    const body: unknown = typeof raw === "string" ? JSON.parse(raw) : undefined;

    const call: FakeCall = {
      method: init?.method ?? "GET",
      path: `${url.pathname}${url.search}`,
      body,
      headers: new Headers(init?.headers),
    };

    calls.push(call);

    const reply = answer(call);

    return new Response(
      reply.json === undefined ? "" : JSON.stringify(reply.json),
      { status: reply.status ?? 200 },
    );
  };

  return { fetch: handler, calls };
}

export const OPTIONS = { baseUrl: "https://provider.test", apiKey: "key" };
