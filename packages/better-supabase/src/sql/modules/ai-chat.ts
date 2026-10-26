import type { AiChatEvents } from "../../blocks/ai-chat/events.ts";
import type {
  ExtraColumn,
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition, BlockSqlLayout } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { schemaPreamble } from "../shared.ts";
import { aiChatDurable } from "./ai-chat-durable.ts";
import { aiChatFunctions, upgradeRunStates } from "./ai-chat-functions.ts";
import {
  sandboxFunctions,
  sandboxTable,
  upgradeSandboxes,
} from "./ai-chat-sandboxes.ts";
import { AI_CHAT_CONTRIBUTES } from "./ai-chat-shares.ts";
import { aiChatTables } from "./ai-chat-tables.ts";
import { moduleOperations } from "./permissions-model.ts";

const PROJECTS = {
  id: "id",
  tenant: "organization_id",
  owner: "owner_id",
  name: "name",
  instructions: "instructions",
  model: "default_model",
  pinned: "pinned",
  archivedAt: "archived_at",
  createdAt: "created_at",
  updatedAt: "updated_at",
} as const;

const CHATS = {
  id: "id",
  tenant: "organization_id",
  owner: "owner_id",
  project: "project_id",
  agent: "agent_id",
  title: "title",
  model: "model",
  visibility: "visibility",
  pinned: "pinned",
  archivedAt: "archived_at",
  temporary: "is_temporary",
  expiresAt: "expires_at",
  leaf: "current_leaf_id",
  activeStream: "active_stream_id",
  activeRun: "active_run_id",
  lastMessageAt: "last_message_at",
  createdAt: "created_at",
  updatedAt: "updated_at",
  search: "search_tsv",
} as const;

const MESSAGES = {
  chat: "chat_id",
  id: "id",
  parent: "parent_id",
  owner: "owner_id",
  role: "role",
  parts: "parts",
  format: "format",
  native: "native",
  metadata: "metadata",
  model: "model",
  status: "status",
  seq: "seq",
  createdAt: "created_at",
  search: "search_tsv",
} as const;

const RUNS = {
  id: "id",
  chat: "chat_id",
  owner: "owner_id",
  message: "assistant_message_id",
  stream: "stream_id",
  engine: "engine",
  externalRun: "external_run_id",
  model: "model",
  status: "status",
  generation: "provider_generation_id",
  usage: "usage",
  cost: "cost_micro_usd",
  error: "error",
  startedAt: "started_at",
  endedAt: "ended_at",
} as const;

const APPROVALS = {
  id: "approval_id",
  chat: "chat_id",
  owner: "owner_id",
  run: "run_id",
  message: "message_id",
  tool: "tool",
  toolCall: "tool_call_id",
  input: "input",
  decision: "decision",
  reason: "reason",
  signature: "signature",
  decidedBy: "decided_by",
  decidedAt: "decided_at",
  createdAt: "created_at",
} as const;

const POLICIES = {
  tenant: "organization_id",
  tool: "tool",
  policy: "policy",
  updatedAt: "updated_at",
} as const;

const INPUTS = {
  id: "id",
  chat: "chat_id",
  owner: "owner_id",
  run: "run_id",
  toolCall: "tool_call_id",
  question: "question",
  schema: "schema",
  answer: "answer",
  answeredAt: "answered_at",
  createdAt: "created_at",
} as const;

const SOURCES = {
  chat: "chat_id",
  message: "message_id",
  source: "source_id",
  kind: "source_type",
  url: "url",
  title: "title",
  metadata: "provider_metadata",
} as const;

const FEEDBACK = {
  chat: "chat_id",
  message: "message_id",
  user: "user_id",
  rating: "rating",
  reason: "reason",
  comment: "comment",
  createdAt: "created_at",
  updatedAt: "updated_at",
} as const;

const SHARES = {
  id: "id",
  chat: "chat_id",
  tokenHash: "token_hash",
  leaf: "leaf_id",
  createdBy: "created_by",
  createdAt: "created_at",
  revokedAt: "revoked_at",
} as const;

const MODELS = {
  id: "model_id",
  provider: "provider",
  name: "name",
  pricing: "pricing",
  capabilities: "capabilities",
  plans: "plans",
  enabled: "enabled",
  refreshedAt: "refreshed_at",
} as const;

const MODERATION = {
  id: "id",
  tenant: "organization_id",
  chat: "chat_id",
  message: "message_id",
  user: "user_id",
  stage: "stage",
  category: "category",
  score: "score",
  action: "action",
  createdAt: "created_at",
} as const;

const STEPS = {
  id: "id",
  run: "run_id",
  chat: "chat_id",
  owner: "owner_id",
  key: "step_key",
  label: "label",
  status: "status",
  detail: "detail",
  startedAt: "started_at",
  endedAt: "ended_at",
} as const;

const SANDBOXES = {
  id: "id",
  tenant: "organization_id",
  user: "user_id",
  chat: "chat_id",
  harness: "harness_id",
  provider: "provider",
  sandbox: "sandbox_id",
  container: "container_id",
  status: "status",
  metadata: "metadata",
  idleSeconds: "idle_seconds",
  error: "error",
  lastUsedAt: "last_used_at",
  expiresAt: "expires_at",
  stoppedAt: "stopped_at",
  createdAt: "created_at",
  updatedAt: "updated_at",
} as const;

const HARNESS = {
  chat: "chat_id",
  harness: "harness_id",
  owner: "owner_id",
  resume: "resume_state",
  continue: "continue_state",
  status: "status",
  holder: "lock_holder",
  lockedUntil: "locked_until",
  lastActiveAt: "last_active_at",
  createdAt: "created_at",
  updatedAt: "updated_at",
} as const;

const EVENTS: BlockSqlEvents<AiChatEvents> = {
  "ai_chat_message.completed": {
    subject: "ai-chats",
    payload: [
      "chatId",
      "messageId",
      "organizationId",
      "ownerId",
      "model",
      "status",
    ],
    retries: true,
  },
  "ai_tool_approval.decided": {
    subject: "ai-chats",
    payload: ["organizationId", "chatId", "approvalId", "tool", "decision"],
  },
  "ai_tool_policy.set": {
    subject: "organizations",
    payload: ["organizationId", "tool", "policy"],
  },
  "ai_chat.shared": {
    subject: "ai-chats",
    payload: ["chatId", "shareId", "organizationId", "ownerId", "leafId"],
  },
  "ai_chat.share_revoked": {
    subject: "ai-chats",
    payload: ["chatId", "shareId", "organizationId", "ownerId"],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    chat: { table: "chats", singular: "ai_chat", primary: true },
    project: { table: "projects", singular: "ai_project" },
  },
  events: EVENTS,
  options: [
    "topic",
    "listTopic",
    "temporaryTtl",
    "staleAfter",
    "sandboxIdleAfter",
    "meterUsage",
    "inputMeter",
    "outputMeter",
    "extraColumns",
  ],
  tables: {
    projects: {
      app: {},
      optional: ["pinned", "archivedAt", "createdAt"],
      name: "ai_projects",
      columns: PROJECTS,
      lifecycle: { user: "owner", tenant: "tenant" },
    },
    chats: {
      app: {},
      optional: ["agent", "pinned", "archivedAt", "createdAt"],
      typed: ["visibility"],
      name: "ai_chats",
      columns: CHATS,
      lifecycle: { user: "owner", tenant: "tenant", omit: ["search"] },
    },
    messages: {
      app: {},
      optional: ["format", "native", "metadata", "model"],
      typed: ["role", "status"],
      name: "ai_messages",
      columns: MESSAGES,
      lifecycle: { user: "owner", omit: ["search"] },
    },
    runs: {
      app: {},
      optional: ["generation", "cost", "error"],
      typed: ["status"],
      name: "ai_runs",
      columns: RUNS,
      lifecycle: { user: "owner" },
    },
    approvals: {
      app: {},
      optional: ["message", "input", "reason", "signature", "decidedBy"],
      typed: ["decision"],
      name: "ai_tool_approvals",
      columns: APPROVALS,
      lifecycle: { user: "owner" },
    },
    policies: {
      app: {},
      optional: ["updatedAt"],
      typed: ["policy"],
      name: "ai_tool_policies",
      columns: POLICIES,
      lifecycle: { tenant: "tenant" },
    },
    inputs: {
      app: {},
      optional: ["toolCall", "schema", "createdAt"],
      name: "ai_pending_inputs",
      columns: INPUTS,
      lifecycle: { user: "owner" },
    },
    sources: {
      app: {},
      optional: ["title", "metadata"],
      typed: ["kind"],
      name: "ai_message_sources",
      columns: SOURCES,
    },
    feedback: {
      app: {},
      optional: ["reason", "comment", "createdAt", "updatedAt"],
      name: "ai_message_feedback",
      columns: FEEDBACK,
      lifecycle: { user: "user" },
    },
    shares: {
      app: {},
      name: "ai_chat_shares",
      columns: SHARES,
      lifecycle: { user: "createdBy", omit: ["tokenHash"] },
    },
    models: {
      app: {},
      optional: ["pricing", "capabilities", "refreshedAt"],
      name: "ai_model_catalog",
      columns: MODELS,
    },
    moderation: {
      app: {},
      optional: ["message", "score"],
      typed: ["stage", "action"],
      name: "ai_moderation_events",
      columns: MODERATION,
      lifecycle: { user: "user", tenant: "tenant" },
    },
    steps: {
      app: {},
      optional: ["detail"],
      typed: ["status"],
      name: "ai_run_steps",
      columns: STEPS,
      lifecycle: { user: "owner" },
    },
    sandboxes: {
      app: {},
      optional: ["container", "metadata", "error"],
      typed: ["status"],
      name: "ai_sandboxes",
      columns: SANDBOXES,
      lifecycle: { user: "user", tenant: "tenant" },
    },
    harness: {
      app: {},
      optional: ["continue", "createdAt"],
      typed: ["status"],
      name: "ai_harness_sessions",
      columns: HARNESS,
      lifecycle: { user: "owner" },
    },
  },
};

type Columns<T> = { readonly [K in keyof T]: string };

/**
 * Every logical column of `table`, quoted. Each is read on use, so a column the
 * app's table lacks throws only where a builder reads it unguarded.
 */
function columnsOf<T extends Readonly<Record<string, string>>>(
  ctx: BlockSqlContext,
  table: string,
  spec: T,
): Columns<T> {
  const columns = {};

  for (const key of Object.keys(spec)) {
    Object.defineProperty(columns, key, {
      enumerable: true,
      get: () => ctx.col(table, key),
    });
  }

  // SAFETY: the object has a getter for each of spec's own keys.
  return columns as Columns<T>;
}

/** The quoted column names of every `ai-chat` table, for the SQL builders. */
export interface AiChatColumns {
  readonly projects: Columns<typeof PROJECTS>;
  readonly chats: Columns<typeof CHATS>;
  readonly messages: Columns<typeof MESSAGES>;
  readonly runs: Columns<typeof RUNS>;
  readonly approvals: Columns<typeof APPROVALS>;
  readonly policies: Columns<typeof POLICIES>;
  readonly inputs: Columns<typeof INPUTS>;
  readonly sources: Columns<typeof SOURCES>;
  readonly feedback: Columns<typeof FEEDBACK>;
  readonly shares: Columns<typeof SHARES>;
  readonly models: Columns<typeof MODELS>;
  readonly moderation: Columns<typeof MODERATION>;
  readonly steps: Columns<typeof STEPS>;
  readonly harness: Columns<typeof HARNESS>;
  readonly sandboxes: Columns<typeof SANDBOXES>;
}

/** What the function builders read: names, permissions and topics. */
export interface AiChatNames {
  readonly c: AiChatColumns;
  readonly t: { readonly [K in keyof AiChatColumns]: string };
  readonly perm: {
    readonly read: string;
    readonly create: string;
    readonly share: string;
    readonly moderate: string;
    readonly admin: string;
  };
  readonly topic: string;
  readonly listTopic: string;
  readonly temporaryTtl: string;
  readonly staleAfter: string;
  /** Seconds a sandbox may sit unused before the idle-stop claim takes it. */
  readonly sandboxIdleAfter: number;
  /** `options.extraColumns`, which the chats table gets. */
  readonly chatExtras: readonly ExtraColumn[];
}

/** The keys a chat read returns, which no extra column may shadow. */
const CHAT_KEYS: readonly string[] = [
  "id",
  "organization_id",
  "owner_id",
  "project_id",
  "agent_id",
  "title",
  "model",
  "visibility",
  "pinned",
  "archived_at",
  "is_temporary",
  "expires_at",
  "current_leaf_id",
  "active_stream_id",
  "active_run_id",
  "last_message_at",
  "created_at",
  "updated_at",
  "fields",
];

const TOPIC = /^[a-z][a-z0-9_-]{0,30}$/;

const INTERVAL =
  /^\d{1,6} (?:second|minute|hour|day|week)s?(?: \d{1,6} (?:second|minute|hour|day|week)s?)*$/;

function topicOption(
  ctx: BlockSqlContext,
  name: string,
  fallback: string,
): string {
  const value = ctx.text(name, fallback);

  if (!TOPIC.test(value)) {
    throw new TypeError(
      `blocks.ai-chat.options.${name} must be a lowercase name of at most 31 characters`,
    );
  }

  return value;
}

function intervalOption(
  ctx: BlockSqlContext,
  name: string,
  fallback: string,
): string {
  const value = ctx.text(name, fallback);

  if (!INTERVAL.test(value)) {
    throw new TypeError(
      `blocks.ai-chat.options.${name} must be an interval such as "1 day" or "10 minutes"`,
    );
  }

  return value;
}

function sandboxIdleAfter(ctx: BlockSqlContext): number {
  const value = ctx.number("sandboxIdleAfter", 600);

  if (!Number.isInteger(value) || value < 1) {
    throw new TypeError(
      "blocks.ai-chat.options.sandboxIdleAfter must be a whole number of seconds",
    );
  }

  return value;
}

function namesOf(ctx: BlockSqlContext): AiChatNames {
  const permissions = moduleOperations("ai-chat");
  const topic = topicOption(ctx, "topic", "ai-chat");
  const listTopic = topicOption(ctx, "listTopic", "ai-chats");

  if (topic === listTopic) {
    throw new TypeError(
      "blocks.ai-chat.options.topic and listTopic must differ",
    );
  }

  return {
    c: {
      projects: columnsOf(ctx, "projects", PROJECTS),
      chats: columnsOf(ctx, "chats", CHATS),
      messages: columnsOf(ctx, "messages", MESSAGES),
      runs: columnsOf(ctx, "runs", RUNS),
      approvals: columnsOf(ctx, "approvals", APPROVALS),
      policies: columnsOf(ctx, "policies", POLICIES),
      inputs: columnsOf(ctx, "inputs", INPUTS),
      sources: columnsOf(ctx, "sources", SOURCES),
      feedback: columnsOf(ctx, "feedback", FEEDBACK),
      shares: columnsOf(ctx, "shares", SHARES),
      models: columnsOf(ctx, "models", MODELS),
      moderation: columnsOf(ctx, "moderation", MODERATION),
      steps: columnsOf(ctx, "steps", STEPS),
      harness: columnsOf(ctx, "harness", HARNESS),
      sandboxes: columnsOf(ctx, "sandboxes", SANDBOXES),
    },
    t: {
      projects: ctx.table("projects"),
      chats: ctx.table("chats"),
      messages: ctx.table("messages"),
      runs: ctx.table("runs"),
      approvals: ctx.table("approvals"),
      policies: ctx.table("policies"),
      inputs: ctx.table("inputs"),
      sources: ctx.table("sources"),
      feedback: ctx.table("feedback"),
      shares: ctx.table("shares"),
      models: ctx.table("models"),
      moderation: ctx.table("moderation"),
      steps: ctx.table("steps"),
      harness: ctx.table("harness"),
      sandboxes: ctx.table("sandboxes"),
    },
    perm: {
      read: ctx.permission("read", permissions.read),
      create: ctx.permission("create", permissions.create),
      share: ctx.permission("share", permissions.share),
      moderate: ctx.permission("moderate", permissions.moderate),
      admin: ctx.permission("admin", permissions.admin),
    },
    topic,
    listTopic,
    temporaryTtl: intervalOption(ctx, "temporaryTtl", "1 day"),
    staleAfter: intervalOption(ctx, "staleAfter", "10 minutes"),
    sandboxIdleAfter: sandboxIdleAfter(ctx),
    chatExtras: ctx.extraColumns("chats", CHAT_KEYS),
  };
}

function realtime(ctx: BlockSqlContext, names: AiChatNames): string {
  const chatReceive = ctx.trigger("ai_chat_receive");
  const listReceive = ctx.trigger("ai_chats_receive");
  const prefix = `${names.topic}:`;

  return `-- A chat's readers join ${names.topic}:{chatId}; each user joins
-- ${names.listTopic}:{userId} for their sidebar. Payloads carry ids only.
do $$
begin
  if to_regclass('realtime.messages') is not null then
        ${renderPolicy(
          makePolicy({
            table: "realtime.messages",
            name: chatReceive,
            command: "select",
            roles: ["authenticated"],
            using: `realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) like ${sqlString(`${prefix}%`)}
        and substr((select realtime.topic()), ${String(prefix.length + 1)}) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        and ${ctx.fn("ai_chat_can_read")}(substr((select realtime.topic()), ${String(prefix.length + 1)})::uuid)`,
          }),
          { drop: true, target: "realtime.messages" },
        )}
        ${renderPolicy(
          makePolicy({
            table: "realtime.messages",
            name: listReceive,
            command: "select",
            roles: ["authenticated"],
            using: `realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) = ${sqlString(`${names.listTopic}:`)} || (select auth.uid())::text`,
          }),
          { drop: true, target: "realtime.messages" },
        )}
  end if;
end;
$$;`;
}

function build(ctx: BlockSqlContext, layout: BlockSqlLayout): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const names = namesOf(ctx);

  return `${schemaPreamble(ctx)}
${aiChatTables(ctx, names)}

${aiChatFunctions(ctx, names, layout)}

${sandboxTable(ctx, names)}

${sandboxFunctions(ctx, names)}

${aiChatDurable(ctx, names)}

${realtime(ctx, names)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  const fn = (
    name: string,
    args: readonly string[],
    returns = "jsonb",
  ): BlockSqlContractFunction => ({ name, args, returns });

  return [
    fn("ai_chat_can_read", ["uuid"], "boolean"),
    fn("create_ai_chat", ["{id}", "jsonb"]),
    fn("update_ai_chat", ["uuid", "jsonb"]),
    fn("delete_ai_chat", ["uuid"], "boolean"),
    fn("get_ai_chat", ["uuid"]),
    fn("list_ai_chats", [
      "{id}",
      "text",
      "uuid",
      "boolean",
      "boolean",
      "text",
      "integer",
    ]),
    fn("save_ai_project", ["uuid", "{id}", "jsonb"]),
    fn("delete_ai_project", ["uuid"], "boolean"),
    fn("list_ai_projects", ["{id}"]),
    fn("append_ai_user_message", ["uuid", "jsonb", "text", "text"]),
    fn("save_ai_assistant_message", [
      "uuid",
      "jsonb",
      "text",
      "text",
      "text",
      "text",
      "jsonb",
      "uuid",
    ]),
    fn("ai_message_path", ["uuid", "text", "boolean"]),
    fn("ai_message_siblings", ["uuid", "text"]),
    fn("switch_ai_branch", ["uuid", "text"]),
    fn("claim_ai_chat_stream", [
      "uuid",
      "text",
      "text",
      "text",
      "text",
      "text",
    ]),
    fn(
      "release_ai_chat_stream",
      ["uuid", "text", "text", "jsonb", "text", "text", "bigint"],
      "boolean",
    ),
    fn("request_ai_chat_stop", ["uuid"]),
    fn("set_ai_run_cost", ["text", "bigint", "jsonb"], "boolean"),
    fn("record_ai_tool_approval", ["uuid", "jsonb"]),
    fn("decide_ai_tool_approval", ["text", "boolean", "text"]),
    fn("get_ai_tool_approvals", ["uuid", "text[]"]),
    fn("set_ai_tool_policy", ["{id}", "text", "text"]),
    fn("ai_tool_policies_for", ["{id}"]),
    fn("open_ai_pending_input", ["uuid", "jsonb"]),
    fn("answer_ai_pending_input", ["uuid", "jsonb"]),
    fn("rate_ai_message", ["uuid", "text", "integer", "text", "text"]),
    fn("share_ai_chat", ["uuid", "text"]),
    fn("revoke_ai_chat_share", ["uuid"], "boolean"),
    fn("list_ai_chat_shares", ["uuid"]),
    fn("get_shared_ai_chat", ["text"]),
    fn("upsert_ai_models", ["jsonb", "boolean"], "integer"),
    fn("allowed_ai_models", ["{id}"]),
    fn("record_ai_moderation_event", ["jsonb"]),
    fn("list_ai_moderation_events", ["{id}", "integer"]),
    fn("purge_ai_chats", ["integer"], "integer"),
    fn("get_ai_run", ["uuid"]),
    fn("list_ai_runs", ["uuid", "boolean", "integer"]),
    fn("attach_ai_run", ["uuid", "text"], "boolean"),
    fn("list_pending_ai_tool_approvals", ["integer"]),
    fn("record_ai_run_step", ["uuid", "jsonb"]),
    fn("list_ai_run_steps", ["uuid"]),
    fn("load_ai_harness_session", ["uuid", "text"]),
    fn("save_ai_harness_session", ["uuid", "text", "jsonb", "text"]),
    fn(
      "lock_ai_harness_session",
      ["uuid", "text", "text", "integer"],
      "boolean",
    ),
    fn("unlock_ai_harness_session", ["uuid", "text", "text"], "boolean"),
    fn("register_ai_sandbox", ["{id}", "text", "text", "jsonb"]),
    fn("touch_ai_sandbox", ["uuid"], "boolean"),
    fn("ai_sandbox_for", ["uuid", "text"]),
    fn("idle_ai_sandboxes", ["integer", "integer"]),
    fn("finish_ai_sandbox_stop", ["uuid", "boolean", "text"], "boolean"),
    fn("list_ai_sandboxes", ["{id}", "uuid"]),
  ];
}

export const AI_CHAT: BlockSqlDefinition = {
  contributes: AI_CHAT_CONTRIBUTES,
  name: "ai-chat",
  scopes: ["tenant"],
  title: "AI chat",
  description:
    "Chats, projects and a branching message tree in the canonical AI message format, with runs (and the id of a durable engine's run), run steps for progress, a compare-and-set stream claim, harness sessions, tool approvals and policies, pending inputs, cited sources, feedback, hashed share links, a model catalog per plan, moderation events and private Realtime topics per chat and per user.",
  requires: ["memberships", "permissions", "streams"],
  integrates: [
    "entitlements",
    "ai-keys",
    "approvals",
    "data-lifecycle",
    "usage",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  version: 4,
  names: NAMES,
  upgrades: [
    {
      from: 1,
      description:
        "Runs end completed, failed or cancelled instead of done, error or stopped, and harness sessions keep their sandbox in ai_sandboxes, which ai-chat now owns, so one idle-stop claim covers every sandbox.",
      sql: (ctx) =>
        `${upgradeRunStates(ctx)}\n${upgradeSandboxes(ctx, namesOf(ctx))}\ndrop function if exists ${ctx.fn("idle_ai_harness_sessions")}(integer, integer);`,
    },
    {
      from: 2,
      description:
        "purge_ai_chats skips temporary chats under a data-lifecycle legal hold.",
      sql: () => "",
    },
    {
      from: 3,
      description:
        "With usage, release_ai_chat_stream records each run's input and output tokens on the ai.input_tokens and ai.output_tokens meters (options.meterUsage, inputMeter, outputMeter).",
      sql: () => "",
    },
  ],
  contract,
  build,
  topics: (ctx) => [
    `${topicOption(ctx, "topic", "ai-chat")}:{chatId}`,
    `${topicOption(ctx, "listTopic", "ai-chats")}:{userId}`,
  ],
};
