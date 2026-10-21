import { channel } from "node:diagnostics_channel";

import { VERSION } from "../version.ts";
import { CliError } from "./errors.ts";
import { redactUrl } from "./redact.ts";
import { HTTP_CHANNEL, type HttpEvent } from "./trace.ts";

const httpChannel = channel(HTTP_CHANNEL);

/** How long one request may take before it fails with `network_error`. */
const REQUEST_TIMEOUT_MS = 30_000;

export const USER_AGENT: string = `better-supabase/${VERSION}`;

export interface HttpOptions {
  /**
   * What the request does, for messages: `Management API query for project
   * abc`.
   */
  readonly what: string;
  readonly method?: string;
  readonly headers?: Readonly<Record<string, string>>;
  readonly body?: string;
  /** The run's signal; aborting it cancels the request. */
  readonly signal?: AbortSignal;
  readonly timeoutMs?: number;
  readonly fetch?: typeof fetch;
}

/**
 * The response body of a request, with the CLI's user agent, the run's signal
 * and a timeout. A request that gets no response is `network_error`, 401 and
 * 403 are `auth_required`, and any other failed status is `request_failed`.
 * Each request is published on `HTTP_CHANNEL` for `--debug`.
 */
export async function request(
  url: string,
  options: HttpOptions,
): Promise<string> {
  const method = options.method ?? "GET";
  const timeout = AbortSignal.timeout(options.timeoutMs ?? REQUEST_TIMEOUT_MS);

  const signal = options.signal
    ? AbortSignal.any([options.signal, timeout])
    : timeout;

  const started = performance.now();

  const publish = (status?: number): void => {
    if (httpChannel.hasSubscribers) {
      const event: HttpEvent = {
        method,
        url: redactUrl(url),
        ...(status === undefined ? {} : { status }),
        milliseconds: Math.round(performance.now() - started),
      };

      httpChannel.publish(event);
    }
  };

  let response: Response;

  try {
    response = await (options.fetch ?? fetch)(url, {
      method,
      headers: { "user-agent": USER_AGENT, ...options.headers },
      ...(options.body === undefined ? {} : { body: options.body }),
      signal,
    });
  } catch (cause) {
    publish();

    if (options.signal?.aborted === true) {
      throw cause;
    }

    const reason = timeout.aborted
      ? `timed out after ${Math.round((options.timeoutMs ?? REQUEST_TIMEOUT_MS) / 1000)}s`
      : cause instanceof Error
        ? cause.message
        : String(cause);

    throw new CliError(
      "network_error",
      `${options.what} got no response from ${new URL(url).host}: ${reason}`,
      { cause },
    );
  }

  publish(response.status);
  const text = await response.text();

  if (!response.ok) {
    throw new CliError(
      response.status === 401 || response.status === 403
        ? "auth_required"
        : "request_failed",
      `${options.what} failed (${response.status}): ${text.slice(0, 300)}`,
    );
  }

  return text;
}
