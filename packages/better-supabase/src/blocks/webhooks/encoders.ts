import type { CredentialToken } from "../../credentials/provider.ts";
import type { CloudEvent } from "../../events/index.ts";
import type { WebhookResponse } from "./http.ts";

import { temporal } from "../../core/temporal-required.ts";
import { toHttp } from "../../events/index.ts";
import { isRecord } from "../shared.ts";

/** The endpoint an encoder writes for. */
export interface WebhookEncodeTarget {
  readonly url: string;
  /** The endpoint takes many events per request. */
  readonly batch: boolean;
  readonly tenant: string | null;
}

/** The request body and the headers that describe it, such as `content-type`. */
export interface WebhookEncoded {
  readonly body: string;
  readonly headers: Readonly<Record<string, string>>;
}

/**
 * What a response means when the status alone doesn't tell: a collector
 * that answers 200 with an error code, or accepts part of a batch.
 * `retry` tries the delivery again; `dead` dead-letters it.
 */
export interface WebhookVerdict {
  readonly outcome: "succeeded" | "retry" | "dead";
  readonly error?: string;
}

/**
 * Turns claimed deliveries, as CloudEvents, into the request one endpoint
 * `format` expects. Versioned: a breaking change to this contract ships a
 * new `apiVersion`.
 */
export interface WebhookEncoder {
  readonly apiVersion: 1;
  /** The endpoint `format` it serves: lowercase letters, digits and dashes. */
  readonly name: string;
  /**
   * Adds the Standard Webhooks signature headers. Collectors that
   * authenticate with a token from `credential_ref` don't need them.
   */
  readonly signed: boolean;
  encode(
    events: readonly CloudEvent[],
    target: WebhookEncodeTarget,
  ): WebhookEncoded | Promise<WebhookEncoded>;
  /** The headers a `credential_ref` token becomes. Defaults to the token's own `headers`. */
  authorize?(token: CredentialToken): Readonly<Record<string, string>>;
  /** Reads the response; `undefined` leaves it to the status and the retry policy. */
  classify?(response: WebhookResponse): WebhookVerdict | undefined;
}

/** The default format: CloudEvents over HTTP, structured or batched per endpoint. */
export function cloudEvents(): WebhookEncoder {
  return {
    apiVersion: 1,
    name: "cloudevents",
    signed: true,
    encode(events, target) {
      const [message] = target.batch
        ? toHttp(events, "batch")
        : toHttp(events[0]!);

      return message!;
    },
  };
}

type AnyValue =
  | Record<string, never>
  | { readonly stringValue: string }
  | { readonly boolValue: boolean }
  | { readonly intValue: string }
  | { readonly doubleValue: number }
  | { readonly arrayValue: { readonly values: readonly AnyValue[] } }
  | { readonly kvlistValue: { readonly values: readonly KeyValue[] } };

interface KeyValue {
  readonly key: string;
  readonly value: AnyValue;
}

/** A JSON value as an OTLP `AnyValue`; 64-bit integers are strings in OTLP/JSON. */
function anyValue(value: unknown): AnyValue {
  if (value === null || value === undefined) {
    return {};
  }

  if (typeof value === "string") {
    return { stringValue: value };
  }

  if (typeof value === "boolean") {
    return { boolValue: value };
  }

  if (typeof value === "bigint") {
    return { intValue: value.toString() };
  }

  if (typeof value === "number") {
    return Number.isSafeInteger(value)
      ? { intValue: String(value) }
      : { doubleValue: value };
  }

  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map(anyValue) } };
  }

  if (isRecord(value)) {
    return { kvlistValue: { values: attributes(value) } };
  }

  return { stringValue: String(value) };
}

function attributes(record: Readonly<Record<string, unknown>>): KeyValue[] {
  return Object.entries(record).flatMap(([key, value]) =>
    value === undefined ? [] : [{ key, value: anyValue(value) }],
  );
}

const nanos = (time: string | undefined): string =>
  (time === undefined
    ? temporal().Now.instant()
    : temporal().Instant.from(time)
  ).epochNanoseconds.toString();

export interface OtlpLogsOptions {
  /** The resource's `service.name`. Defaults to `better-supabase`. */
  readonly serviceName?: string;
  /** More resource attributes, such as `deployment.environment.name`. */
  readonly resource?: Readonly<Record<string, string>>;
  /** The `severityNumber` of each record. Defaults to 9 (INFO). */
  readonly severity?: (event: CloudEvent) => number;
}

const SEVERITY_TEXT = ["TRACE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL"];

/** OTLP/HTTP retries 429, 502, 503 and 504 only. */
const OTLP_RETRYABLE = new Set([429, 502, 503, 504]);

/**
 * OTLP/HTTP logs in the JSON encoding: one `ExportLogsServiceRequest` per
 * request, a log record per event with the CloudEvents attributes. Point
 * the endpoint at a collector's `/v1/logs`.
 */
export function otlpLogs(options: OtlpLogsOptions = {}): WebhookEncoder {
  const resource = attributes({
    "service.name": options.serviceName ?? "better-supabase",
    ...options.resource,
  });

  return {
    apiVersion: 1,
    name: "otlp-logs",
    signed: false,
    encode(events) {
      const observed = nanos(undefined);

      const logRecords = events.map((event) => {
        const severity = options.severity?.(event) ?? 9;

        return {
          timeUnixNano: nanos(event.time),
          observedTimeUnixNano: observed,
          severityNumber: severity,
          severityText:
            SEVERITY_TEXT[
              Math.min(Math.max(Math.ceil(severity / 4), 1), 6) - 1
            ],
          eventName: event.type,
          body: anyValue(event.data),
          attributes: attributes({
            "cloudevents.event_id": event.id,
            "cloudevents.event_source": event.source,
            "cloudevents.event_spec_version": event.specversion,
            "cloudevents.event_type": event.type,
            "cloudevents.event_subject": event.subject,
          }),
        };
      });

      return {
        body: JSON.stringify({
          resourceLogs: [
            {
              resource: { attributes: resource },
              scopeLogs: [
                { scope: { name: "better-supabase/webhooks" }, logRecords },
              ],
            },
          ],
        }),
        headers: { "content-type": "application/json" },
      };
    },
    classify(response) {
      if (response.status < 200 || response.status >= 300) {
        return OTLP_RETRYABLE.has(response.status)
          ? { outcome: "retry", error: `HTTP ${String(response.status)}` }
          : { outcome: "dead", error: `HTTP ${String(response.status)}` };
      }

      const partial = jsonOf(response.body)?.["partialSuccess"];

      if (!isRecord(partial)) {
        return;
      }

      const rejected = Number(partial["rejectedLogRecords"] ?? 0);

      if (!(rejected > 0)) {
        return;
      }

      const message = partial["errorMessage"];

      return {
        outcome: "succeeded",
        error: `The collector rejected ${String(rejected)} log records${
          typeof message === "string" && message !== "" ? `: ${message}` : ""
        }`,
      };
    },
  };
}

function jsonOf(body: string): Record<string, unknown> | undefined {
  try {
    const value: unknown = JSON.parse(body);

    return isRecord(value) ? value : undefined;
  } catch {
    return undefined;
  }
}

export interface SplunkHecOptions {
  /** The index to write to. Defaults to the token's default index. */
  readonly index?: string;
  /** Defaults to `_json`. */
  readonly sourcetype?: string;
  /** Defaults to the CloudEvents `source`. */
  readonly source?: string;
  readonly host?: string;
}

/** HEC codes worth a retry: internal error and server busy. */
const HEC_RETRYABLE = new Set([8, 9]);

/**
 * The Splunk HTTP Event Collector's event format: one JSON object per
 * event, the CloudEvent as `event`. Point the endpoint at
 * `/services/collector/event` and set `credential_ref` to the HEC token.
 */
export function splunkHec(options: SplunkHecOptions = {}): WebhookEncoder {
  return {
    apiVersion: 1,
    name: "splunk-hec",
    signed: false,
    encode(events) {
      const body = events
        .map((event) =>
          JSON.stringify({
            time:
              (event.time === undefined
                ? temporal().Now.instant()
                : temporal().Instant.from(event.time)
              ).epochMilliseconds / 1000,
            ...(options.host === undefined ? {} : { host: options.host }),
            source: options.source ?? event.source,
            sourcetype: options.sourcetype ?? "_json",
            ...(options.index === undefined ? {} : { index: options.index }),
            event,
          }),
        )
        .join("\n");

      return { body, headers: { "content-type": "application/json" } };
    },
    authorize: (token) => ({ authorization: `Splunk ${token.token}` }),
    classify(response) {
      const reply = jsonOf(response.body);
      const code = reply?.["code"];

      if (typeof code !== "number") {
        return;
      }

      if (code === 0) {
        return response.status >= 200 && response.status < 300
          ? { outcome: "succeeded" }
          : undefined;
      }

      const text = reply?.["text"];

      return {
        outcome: HEC_RETRYABLE.has(code) ? "retry" : "dead",
        error: `HEC ${String(code)}${typeof text === "string" ? `: ${text}` : ""}`,
      };
    },
  };
}

/** RFC 8935 error codes a transmitter can't fix by sending the SET again. */
const SET_RETRYABLE = new Set(["invalid_key"]);

/**
 * RFC 8935 push delivery of Security Event Tokens: the body is the compact
 * SET from the delivery's `data.set`, one per request. The shared-signals
 * block creates these endpoints (`format: 'set'`) and dispatches to them.
 */
export function securityEvents(): WebhookEncoder {
  return {
    apiVersion: 1,
    name: "set",
    signed: false,
    encode(events) {
      const data: unknown = events[0]?.data;
      const set = isRecord(data) ? data["set"] : undefined;

      if (typeof set !== "string" || set.split(".").length !== 3) {
        throw new TypeError("A set delivery carries a compact SET in data.set");
      }

      return {
        body: set,
        headers: {
          "content-type": "application/secevent+jwt",
          accept: "application/json",
        },
      };
    },
    classify(response) {
      if (response.status === 202 || response.status === 200) {
        return { outcome: "succeeded" };
      }

      if (response.status !== 400) {
        return;
      }

      const reply = jsonOf(response.body);
      const code = typeof reply?.["err"] === "string" ? reply["err"] : "";

      const description =
        typeof reply?.["description"] === "string"
          ? `: ${reply["description"]}`
          : "";

      return {
        outcome: SET_RETRYABLE.has(code) ? "retry" : "dead",
        error: `SET rejected (${code || "HTTP 400"})${description}`,
      };
    },
  };
}

const FORMAT = /^[a-z][a-z0-9-]{0,39}$/;

/** The built-in encoders by format, with `encoders` replacing any by name. */
export function encoderRegistry(
  encoders: readonly WebhookEncoder[] = [],
): ReadonlyMap<string, WebhookEncoder> {
  const registry = new Map<string, WebhookEncoder>(
    [cloudEvents(), otlpLogs(), splunkHec(), securityEvents()].map(
      (encoder) => [encoder.name, encoder],
    ),
  );

  for (const encoder of encoders) {
    if (!FORMAT.test(encoder.name)) {
      throw new TypeError(
        `createWebhooks: encoder name "${encoder.name}" must match ${String(FORMAT)}`,
      );
    }

    registry.set(encoder.name, encoder);
  }

  return registry;
}
