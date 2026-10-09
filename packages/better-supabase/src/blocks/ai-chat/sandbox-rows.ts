import type { AiSandbox, AiSandboxStatus } from "./sandboxes.ts";

import {
  isRecord,
  oneOf,
  optionalInstant,
  optionalText,
  recordOf,
  textOf,
  toInstant,
} from "../shared.ts";

const SANDBOX_STATUSES: readonly AiSandboxStatus[] = [
  "running",
  "stopping",
  "stopped",
];

const sandboxInstant = (value: unknown): Temporal.Instant =>
  value instanceof Date ? toInstant(value) : toInstant(textOf(value));

export function sandboxOf(value: unknown): AiSandbox {
  const row = recordOf(value, "ai_sandboxes");
  const idle = row["idle_seconds"];
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organization_id"]),
    userId: optionalText(row["user_id"]),
    chatId: optionalText(row["chat_id"]),
    harnessId: optionalText(row["harness_id"]),
    provider: textOf(row["provider"]),
    sandboxId: textOf(row["sandbox_id"]),
    containerId: optionalText(row["container_id"]),
    status: oneOf(row["status"], SANDBOX_STATUSES, "stopped"),
    metadata: isRecord(row["metadata"]) ? row["metadata"] : {},
    idleSeconds: typeof idle === "number" && Number.isFinite(idle) ? idle : 0,
    error: optionalText(row["error"]),
    lastUsedAt: sandboxInstant(row["last_used_at"]),
    expiresAt: optionalInstant(row["expires_at"]),
    stoppedAt: optionalInstant(row["stopped_at"]),
    createdAt: sandboxInstant(row["created_at"]),
  };
}
