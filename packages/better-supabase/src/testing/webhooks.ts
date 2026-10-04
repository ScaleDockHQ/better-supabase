import type { WebhookTransport } from "../webhooks/http.ts";
import type { WebhookSecretStore } from "../webhooks/secrets.ts";
import type { WebhookSignInput, WebhookSigner } from "../webhooks/signers.ts";

import { temporal } from "../core/temporal-required.ts";
import { type ConformanceReport, conform, expect } from "./conformance.ts";

export interface TestWebhookSignerOptions {
  /**
   * The receiver's check, e.g. `verifyWebhook`. When given, the kit checks
   * that the signed sample verifies with its secret.
   */
  readonly verify?: (
    request: {
      readonly headers: Readonly<Record<string, string>>;
      readonly body: string;
    },
    secret: string,
  ) => Promise<boolean>;
}

const SECRET = "whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw";

function signInput(
  body: string,
  timestamp: Temporal.Instant,
): WebhookSignInput {
  return Object.freeze({
    id: "msg_conformance",
    body,
    timestamp,
    secrets: Object.freeze([SECRET]),
  });
}

function isHeaders(value: unknown): value is Readonly<Record<string, string>> {
  return (
    typeof value === "object" &&
    value !== null &&
    Object.values(value).every((entry) => typeof entry === "string")
  );
}

/**
 * Runs the `WebhookSigner` contract against `signer`: the API version, a
 * name, string headers that depend on the body and are stable for the same
 * input, and, with `verify`, a signature the receiver accepts.
 */
export function testWebhookSigner(
  signer: WebhookSigner,
  options: TestWebhookSignerOptions = {},
): Promise<ConformanceReport> {
  const body = JSON.stringify({ type: "conformance.check", data: { n: 1 } });
  const now = temporal().Now.instant();
  return conform(`WebhookSigner "${signer.name}"`, [
    [
      "has apiVersion 1",
      () => {
        const version: unknown = signer.apiVersion;
        expect(version === 1, "apiVersion must be 1");
      },
    ],
    [
      "has a name",
      () => {
        expect(
          typeof signer.name === "string" && signer.name.length > 0,
          "name must be a non-empty string",
        );
      },
    ],
    [
      "returns string headers, stable for the same input",
      async () => {
        const first: unknown = await signer.sign(signInput(body, now));
        const second: unknown = await signer.sign(signInput(body, now));
        expect(isHeaders(first), "sign must return a record of string headers");
        expect(
          isHeaders(first) && Object.keys(first).length > 0,
          "sign must return at least one header",
        );
        expect(
          JSON.stringify(first) === JSON.stringify(second),
          "the same input must produce the same headers",
        );
      },
    ],
    [
      "changes the headers when the body changes",
      async () => {
        const original = await signer.sign(signInput(body, now));
        const tampered = await signer.sign(signInput(`${body} `, now));
        expect(
          JSON.stringify(original) !== JSON.stringify(tampered),
          "the signature must cover the body",
        );
      },
    ],
    options.verify && [
      "produces a signature the receiver verifies",
      async () => {
        const headers = await signer.sign(signInput(body, now));
        expect(
          await options.verify!({ headers, body }, SECRET),
          "the receiver rejected the signature",
        );
      },
    ],
  ]);
}

export interface TestWebhookTransportOptions {
  /** A receiver the transport may POST the sample to, e.g. a local server. */
  readonly url: string;
  /** The bodies the receiver got, read after the kit sends. */
  readonly received?: () => Promise<readonly string[]>;
}

/**
 * Runs the `WebhookTransport` contract against `transport`: the API version,
 * a name, and one POST to `options.url` that returns an HTTP status and a
 * string body.
 */
export function testWebhookTransport(
  transport: WebhookTransport,
  options: TestWebhookTransportOptions,
): Promise<ConformanceReport> {
  const body = JSON.stringify({
    type: "conformance.check",
    id: crypto.randomUUID(),
  });
  return conform(`WebhookTransport "${transport.name}"`, [
    [
      "has apiVersion 1",
      () => {
        const version: unknown = transport.apiVersion;
        expect(version === 1, "apiVersion must be 1");
      },
    ],
    [
      "has a name",
      () => {
        expect(
          typeof transport.name === "string" && transport.name.length > 0,
          "name must be a non-empty string",
        );
      },
    ],
    [
      "sends the request and returns a status and a body",
      async () => {
        const response = await transport.send(
          Object.freeze({
            url: options.url,
            headers: Object.freeze({ "content-type": "application/json" }),
            body,
          }),
        );
        expect(
          Number.isInteger(response.status) &&
            response.status >= 100 &&
            response.status <= 599,
          `status must be an HTTP status, got ${String(response.status)}`,
        );
        const responseBody: unknown = response.body;
        expect(typeof responseBody === "string", "body must be a string");
      },
    ],
    options.received && [
      "delivers the body",
      async () => {
        const bodies = await options.received!();
        expect(bodies.includes(body), "the receiver did not get the body");
      },
    ],
  ]);
}

export interface TestWebhookSecretStoreOptions {
  /** A destination the store may read and, when it can rotate, rotate. */
  readonly destinationId: string;
}

/**
 * Runs the `WebhookSecretStore` contract against `store`: the API version, a
 * list of strings, and, when it can rotate, a new secret listed first while
 * the previous one keeps signing.
 */
export function testWebhookSecretStore(
  store: WebhookSecretStore,
  options: TestWebhookSecretStoreOptions,
): Promise<ConformanceReport> {
  return conform("WebhookSecretStore", [
    [
      "has apiVersion 1",
      () => {
        const version: unknown = store.apiVersion;
        expect(version === 1, "apiVersion must be 1");
      },
    ],
    [
      "lists the secrets as strings",
      async () => {
        const secrets: unknown = await store.secrets(options.destinationId);
        expect(
          Array.isArray(secrets) &&
            secrets.every((secret) => typeof secret === "string"),
          "secrets must return an array of strings",
        );
      },
    ],
    store.rotate && [
      "rotates to a new secret and keeps the previous one during the overlap",
      async () => {
        const first = await store.rotate!(options.destinationId, {
          overlap: "1 hour",
        });
        const second = await store.rotate!(options.destinationId, {
          overlap: "1 hour",
        });
        expect(
          typeof first === "string" && first.length > 0,
          "rotate must return the new secret",
        );
        expect(first !== second, "each rotation must create a new secret");
        const secrets = await store.secrets(options.destinationId);
        expect(secrets[0] === second, "the newest secret must be listed first");
        expect(
          secrets.includes(first),
          "the previous secret must keep signing during the overlap",
        );
      },
    ],
  ]);
}
