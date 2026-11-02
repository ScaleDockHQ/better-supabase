import { AsyncResult, dbErrorOfStatus, err, ok } from "better-supabase";

/** What every HTTP adapter template takes. */
export interface HttpOptions {
  readonly baseUrl: string;
  readonly apiKey: string;
  /** Defaults to the global `fetch`; tests pass a fake. */
  readonly fetch?: typeof fetch;
}

/**
 * Calls the provider and parses the JSON answer. A failed status becomes an
 * error `Result`; a transport failure becomes one too, because `AsyncResult`
 * catches what the callback throws.
 */
export function requestJson(
  options: HttpOptions,
  path: string,
  init: {
    readonly method?: string;
    readonly body?: unknown;
    readonly headers?: Readonly<Record<string, string>>;
    readonly signal?: AbortSignal;
  } = {},
): AsyncResult<unknown> {
  return AsyncResult.from(async () => {
    const send = options.fetch ?? fetch;

    const response = await send(`${options.baseUrl}${path}`, {
      method: init.method ?? "GET",
      headers: {
        authorization: `Bearer ${options.apiKey}`,
        "content-type": "application/json",
        ...init.headers,
      },
      ...(init.body === undefined ? {} : { body: JSON.stringify(init.body) }),
      ...(init.signal === undefined ? {} : { signal: init.signal }),
    });

    const text = await response.text();

    if (!response.ok) {
      return err(
        dbErrorOfStatus(
          response.status,
          text.slice(0, 200) || `HTTP ${response.status}`,
        ),
      );
    }

    const parsed: unknown = text === "" ? null : JSON.parse(text);

    return ok(parsed);
  });
}

/** An object, or a `TypeError` naming where it was expected. */
export function record(value: unknown, where: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new TypeError(`${where}: expected an object`);
  }

  return Object.fromEntries(Object.entries(value));
}

/** A string, or a `TypeError`. */
export function text(value: unknown, where: string): string {
  if (typeof value !== "string") {
    throw new TypeError(`${where}: expected a string`);
  }

  return value;
}

/** A finite number, or a `TypeError`. */
export function numberOf(value: unknown, where: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new TypeError(`${where}: expected a number`);
  }

  return value;
}

/** An array, or a `TypeError`. */
export function list(value: unknown, where: string): readonly unknown[] {
  if (!Array.isArray(value)) {
    throw new TypeError(`${where}: expected an array`);
  }

  return value;
}
