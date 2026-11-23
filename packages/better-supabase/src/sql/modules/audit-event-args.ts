import type { BlockSqlContractFunction } from "../context.ts";
import type { BatchArgument } from "../shared.ts";

/** `audit_event`'s argument types. */
export const EVENT_ARGS = (id: string): string =>
  `text, text, text, text, text, text, ${id}, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text, uuid, uuid, text, text, jsonb`;

/** `audit_event`'s arguments, as the keys of an `audit_event_many` element. */
export const EVENT_KEYS = (id: string): readonly BatchArgument[] => [
  ["event_type", "text"],
  ["category", "text"],
  ["outcome", "text", "'success'"],
  ["source", "text"],
  ["target_type", "text"],
  ["record_id", "text"],
  ["tenant", id],
  ["metadata", "jsonb", "'{}'"],
  ["idempotency_key", "text"],
  ["restricted", "jsonb"],
  ["actor_id", "uuid"],
  ["summary", "text"],
  ["target_label", "text"],
  ["correlation_id", "text"],
  ["actor_kind", "text"],
  ["actor_label", "text"],
  ["ip", "inet"],
  ["user_agent", "text"],
  ["session_id", "text"],
  ["request_id", "text"],
  ["scope", "text"],
  ["support_session", "uuid"],
  ["impersonated_by", "uuid"],
  ["impersonation_reason", "text"],
  ["summary_key", "text"],
  ["summary_params", "jsonb"],
];

export const PREVIOUS_EVENT_ARGS = (id: string): readonly string[] => [
  `text, text, text, text, text, text, ${id}, jsonb, text, jsonb, uuid, text, text, text`,
  `text, text, text, text, text, text, ${id}, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text`,
  `text, text, text, text, text, text, ${id}, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text`,
  `text, text, text, text, text, text, ${id}, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text, uuid, uuid, text`,
];

/** `audit_event_trusted`'s signatures before the current one. */
export const PREVIOUS_TRUSTED_ARGS = (id: string): readonly string[] => [
  `text, text, text, text, text, text, ${id}, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text`,
  `text, text, text, text, text, text, ${id}, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text, uuid, uuid, text`,
];

/** The audit functions other modules and the TypeScript side call. */
export const AUDIT_CONTRACT: readonly BlockSqlContractFunction[] = [
  {
    name: "audit",
    args: [
      "regclass",
      "text[]",
      "boolean",
      "text[]",
      "text",
      "text",
      "text",
      "text",
      "text",
    ],
    returns: "void",
  },
  {
    name: "audit_event",
    args: EVENT_ARGS("{id}").split(", "),
    returns: "text",
  },
  { name: "audit_event_many", args: ["jsonb"], returns: "jsonb" },
  {
    name: "purge_audit_log",
    args: ["interval", "integer", "{id}", "boolean"],
    returns: "integer",
  },
];
