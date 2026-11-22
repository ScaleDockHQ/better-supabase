/**
 * One event of a session stream, with the position of the stored line it came
 * in.
 */
export interface StreamEvent {
  readonly type: string;
  readonly line: number;
  readonly data: Record<string, any>;
}

export interface StreamRead {
  readonly events: readonly StreamEvent[];
  /** `x-eve-stream-tail-index`, when the server sent it. */
  readonly tailIndex: number | undefined;
}

async function json(response: Response): Promise<Record<string, unknown>> {
  const body: unknown = await response.json();

  if (typeof body !== "object" || body === null) {
    throw new TypeError(`expected a JSON object, got ${JSON.stringify(body)}`);
  }

  return Object.fromEntries(Object.entries(body));
}

const AUTH = {
  authorization: `Basic ${Buffer.from("eve-world:eve-world-password").toString("base64")}`,
};

export class Client {
  readonly url: string;

  constructor(url: string) {
    this.url = url;
  }

  async create(message?: string): Promise<string> {
    const response = await fetch(`${this.url}/eve/v1/session`, {
      method: "POST",
      headers: { "content-type": "application/json", ...AUTH },
      ...(message === undefined ? {} : { body: JSON.stringify({ message }) }),
    });

    const body = await json(response);

    if (!response.ok || typeof body["sessionId"] !== "string") {
      throw new Error(
        `create failed (${String(response.status)}): ${JSON.stringify(body)}`,
      );
    }

    return body["sessionId"];
  }

  async post(
    sessionId: string,
    body: Record<string, unknown>,
    action = "",
  ): Promise<{ status: number; body: Record<string, unknown> }> {
    const response = await fetch(
      `${this.url}/eve/v1/session/${sessionId}${action}`,
      {
        method: "POST",
        headers: { "content-type": "application/json", ...AUTH },
        body: JSON.stringify(body),
      },
    );

    return { status: response.status, body: await json(response) };
  }

  send(
    sessionId: string,
    message: string,
    turnPolicy?: "steer" | "queue",
  ): Promise<{ status: number; body: Record<string, unknown> }> {
    return this.post(
      sessionId,
      turnPolicy === undefined ? { message } : { message, turnPolicy },
    );
  }

  /** Reads the recorded events without following, from `startIndex`. */
  async history(sessionId: string, startIndex = 0): Promise<StreamRead> {
    const response = await fetch(
      `${this.url}/eve/v1/session/${sessionId}/stream?follow=false&startIndex=${String(startIndex)}`,
      { headers: AUTH },
    );

    if (!response.ok) {
      throw new Error(
        `history failed (${String(response.status)}): ${await response.text()}`,
      );
    }

    const tail = response.headers.get("x-eve-stream-tail-index");

    return {
      events: parse(await response.text(), startIndex),
      tailIndex: tail === null ? undefined : Number(tail),
    };
  }

  /**
   * Follows the stream from `startIndex` until `until` returns true for an
   * event (or the server ends it), and returns what it read with the time each
   * event arrived.
   */
  async follow(
    sessionId: string,
    until: (event: StreamEvent) => boolean,
    startIndex = 0,
    timeoutMs = 45_000,
  ): Promise<{ events: StreamEvent[]; times: number[] }> {
    const controller = new AbortController();

    const timer = setTimeout(() => {
      controller.abort();
    }, timeoutMs);

    const events: StreamEvent[] = [];
    const times: number[] = [];

    try {
      const response = await fetch(
        `${this.url}/eve/v1/session/${sessionId}/stream?startIndex=${String(startIndex)}`,
        { signal: controller.signal, headers: AUTH },
      );

      if (!response.ok || response.body === null) {
        throw new Error(`stream failed (${String(response.status)})`);
      }

      const decoder = new TextDecoder();
      let buffer = "";
      let line = startIndex;

      for await (const chunk of response.body) {
        buffer += decoder.decode(chunk, { stream: true });
        const lines = buffer.split("\n");
        buffer = lines.pop() ?? "";

        const text = lines.join("\n");
        const parsed = parse(text, line);
        line += text
          .split("\n")
          .filter((raw) => raw.includes('"facts"')).length;

        for (const event of parsed) {
          events.push(event);
          times.push(performance.now());

          if (until(event)) {
            controller.abort();

            return { events, times };
          }
        }
      }
    } catch (error) {
      if (!controller.signal.aborted) {
        throw error;
      }
    } finally {
      clearTimeout(timer);
    }

    return { events, times };
  }

  async waitFor(
    sessionId: string,
    type: string,
    startIndex = 0,
    match: (event: StreamEvent) => boolean = () => true,
  ): Promise<StreamEvent[]> {
    const { events } = await this.follow(
      sessionId,
      (event) => event.type === type && match(event),
      startIndex,
    );

    if (!events.some((event) => event.type === type && match(event))) {
      throw new Error(
        `no ${type} event; saw ${events.map((event) => event.type).join(", ")}`,
      );
    }

    return events;
  }
}

/**
 * Splits NDJSON into events: each stored line holds `facts`, control lines
 * (`$eve`) hold none.
 */
function parse(text: string, firstLine: number): StreamEvent[] {
  const events: StreamEvent[] = [];
  let line = firstLine;

  for (const raw of text.split("\n")) {
    if (raw.trim() === "") {
      continue;
    }

    const value: unknown = JSON.parse(raw);

    if (
      typeof value !== "object" ||
      value === null ||
      !("facts" in value) ||
      !Array.isArray(value.facts)
    ) {
      continue;
    }

    for (const fact of value.facts) {
      events.push({ type: String(fact.type), line, data: fact.data ?? {} });
    }

    line += 1;
  }

  return events;
}
