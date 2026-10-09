import type { CredentialRef } from "../../credentials/provider.ts";
import type {
  AiBatch,
  AiBatchCounts,
  AiBatchItem,
  AiBatchItemStatus,
  AiBatchStatus,
  AiProviderKey,
} from "./types.ts";

import {
  credentialRefOf,
  oneOf,
  optionalInstant,
  optionalText,
  recordOf,
  recordOrEmpty,
  textOf,
  toInstant,
} from "../shared.ts";

const BATCH_STATUSES: readonly AiBatchStatus[] = [
  "pending",
  "completed",
  "failed",
  "cancelled",
];
const ITEM_STATUSES: readonly AiBatchItemStatus[] = [
  "succeeded",
  "failed",
  "cancelled",
  "expired",
];
const instant = (value: unknown): Temporal.Instant =>
  value instanceof Date ? toInstant(value) : toInstant(textOf(value));

const numberOf = (value: unknown): number =>
  typeof value === "number" && Number.isFinite(value) ? value : 0;

export function refOf(value: unknown): CredentialRef {
  const ref = credentialRefOf(value);
  if (ref === undefined) {
    throw new TypeError("ai_provider_keys returned a key without a ref");
  }
  return ref;
}

export function keyOf(value: unknown): AiProviderKey {
  const row = recordOf(value, "ai_provider_keys");
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organization_id"]),
    provider: textOf(row["provider"]),
    name: textOf(row["name"]),
    credentialRef: refOf(row["credential_ref"]),
    settings: recordOrEmpty(row["settings"]),
    enabled: row["enabled"] !== false,
    createdBy: optionalText(row["created_by"]),
    createdAt: instant(row["created_at"]),
    updatedAt: instant(row["updated_at"]),
  };
}

function countsOf(value: unknown): AiBatchCounts {
  const row = recordOrEmpty(value);
  const out: Record<string, number> = {};
  for (const key of ["total", "pending", "completed", "failed"] as const)
    if (typeof row[key] === "number") out[key] = row[key];
  return out;
}

export function batchOf(value: unknown): AiBatch {
  const row = recordOf(value, "ai_batches");
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organization_id"]),
    userId: optionalText(row["user_id"]),
    provider: textOf(row["provider"]),
    reference: recordOrEmpty(row["reference"]),
    status: oneOf(row["status"], BATCH_STATUSES, "failed"),
    rawStatus: optionalText(row["raw_status"]),
    itemCount: numberOf(row["item_count"]),
    counts: countsOf(row["counts"]),
    error: optionalText(row["error"]),
    metadata: recordOrEmpty(row["metadata"]),
    resultsSaved: row["results_saved"] === true,
    polls: numberOf(row["polls"]),
    nextPollAt: optionalInstant(row["next_poll_at"]),
    expiresAt: optionalInstant(row["expires_at"]),
    completedAt: optionalInstant(row["completed_at"]),
    createdAt: instant(row["created_at"]),
    updatedAt: instant(row["updated_at"]),
  };
}

export function itemOf(value: unknown): AiBatchItem {
  const row = recordOf(value, "ai_batch_items");
  return {
    batchId: textOf(row["batch_id"]),
    requestId: textOf(row["request_id"]),
    organizationId: textOf(row["organization_id"]),
    status: oneOf(row["status"], ITEM_STATUSES, "failed"),
    output: row["output"] ?? undefined,
    usage: row["usage"] ?? undefined,
    error: optionalText(row["error"]),
    createdAt: instant(row["created_at"]),
  };
}
