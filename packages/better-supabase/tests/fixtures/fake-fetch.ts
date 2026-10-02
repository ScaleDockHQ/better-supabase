export interface FetchCall {
  readonly url: string;
  readonly method: string;
  readonly headers: Headers;
  readonly body: string | undefined;
}

export type FetchAnswer =
  | Response
  | {
      readonly status?: number;
      readonly body?: unknown;
      readonly text?: string;
    };

/** A `fetch` that records calls and answers from `respond` (or throws what it throws). */
export function fakeFetch(
  respond: (call: FetchCall) => FetchAnswer | Promise<FetchAnswer> = () => ({
    status: 404,
  }),
): { fetch: typeof fetch; calls: FetchCall[] } {
  const calls: FetchCall[] = [];
  const fetchImpl = async (
    input: RequestInfo | URL,
    init?: RequestInit,
  ): Promise<Response> => {
    const request = input instanceof Request ? input : undefined;
    const call: FetchCall = {
      url: request ? request.url : String(input),
      method: init?.method ?? request?.method ?? "GET",
      headers: new Headers(init?.headers ?? request?.headers),
      body: typeof init?.body === "string" ? init.body : undefined,
    };
    calls.push(call);
    const answer = await respond(call);
    if (answer instanceof Response) return answer;
    const text =
      answer.text ??
      (answer.body === undefined ? "" : JSON.stringify(answer.body));
    return new Response(answer.status === 204 ? null : text, {
      status: answer.status ?? 200,
    });
  };
  return { fetch: fetchImpl, calls };
}
