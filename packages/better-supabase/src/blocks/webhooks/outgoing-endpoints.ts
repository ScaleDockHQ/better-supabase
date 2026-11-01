import type { BlockCall } from "../../core/block-helpers.ts";
import type { CredentialRef } from "../../credentials/provider.ts";
import type {
  WebhookEndpoint,
  WebhookEndpointFields,
  WebhookEndpoints,
} from "./outgoing-types.ts";

import { temporal } from "../../core/temporal-required.ts";
import { isRecord } from "../shared.ts";

const textOrNull = (value: unknown): string | null =>
  typeof value === "string" ? value : null;

const instantOrNull = (value: unknown): Temporal.Instant | null =>
  typeof value === "string" ? temporal().Instant.from(value) : null;

const credentialRefOf = (value: unknown): CredentialRef | null =>
  isRecord(value) && typeof value["provider"] === "string"
    ? { ...value, provider: value["provider"] }
    : null;

/**
 * One endpoint from `list_webhook_endpoints` or an endpoint write. Throws a
 * `TypeError` when `value` is not an endpoint object.
 */
function endpointOf(value: unknown, defaultFormat: string): WebhookEndpoint {
  if (
    !isRecord(value) ||
    typeof value["id"] !== "string" ||
    typeof value["url"] !== "string"
  ) {
    throw new TypeError("Expected a webhook endpoint object");
  }

  const createdAt = instantOrNull(value["createdAt"]);

  return {
    id: value["id"],
    tenant:
      value["tenant"] === null || value["tenant"] === undefined
        ? null
        : String(value["tenant"]),
    name: textOrNull(value["name"]),
    url: value["url"],
    enabled: value["enabled"] !== false,
    eventTypes: Array.isArray(value["eventTypes"])
      ? value["eventTypes"].map(String)
      : [],
    permissions: Array.isArray(value["permissions"])
      ? value["permissions"].map(String)
      : null,
    batch: value["batch"] === true,
    signing: value["signing"] === "v1a" ? "v1a" : "v1",
    format: textOrNull(value["format"]) ?? defaultFormat,
    credentialRef: credentialRefOf(value["credentialRef"]),
    failingSince: instantOrNull(value["failingSince"]),
    disabledAt: instantOrNull(value["disabledAt"]),
    disabledReason: textOrNull(value["disabledReason"]),
    createdBy: textOrNull(value["createdBy"]),
    createdAt: createdAt ?? temporal().Now.instant(),
    updatedAt: instantOrNull(value["updatedAt"]),
  };
}

/** The `fields` argument: only the keys the input sets. */
function fieldsOf(input: WebhookEndpointFields): Record<string, unknown> {
  const fields: Record<string, unknown> = {};

  for (const key of [
    "name",
    "url",
    "enabled",
    "eventTypes",
    "permissions",
    "batch",
    "signing",
    "format",
    "credentialRef",
  ] as const) {
    if (input[key] !== undefined) {
      fields[key] = input[key];
    }
  }

  return fields;
}

/** The endpoint methods of `createWebhooks`. */
export function endpointMethods(
  db: BlockCall,
  defaultFormat: string,
): WebhookEndpoints {
  const one = (value: unknown) => endpointOf(value, defaultFormat);

  return {
    createEndpoint: ({ tenant, ...input }) =>
      db("create_webhook_endpoint", { tenant, fields: fieldsOf(input) }, one),
    updateEndpoint: ({ endpointId, changes }) =>
      db(
        "update_webhook_endpoint",
        { endpoint: endpointId, fields: fieldsOf(changes) },
        one,
      ),
    listEndpoints: (tenant) =>
      db("list_webhook_endpoints", { tenant }, (value) =>
        Array.isArray(value) ? value.map(one) : [],
      ),
    deleteEndpoint: (endpointId) =>
      db("delete_webhook_endpoint", { endpoint: endpointId }, () => undefined),
  };
}
