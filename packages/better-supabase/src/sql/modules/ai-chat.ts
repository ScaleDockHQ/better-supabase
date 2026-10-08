import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import { AI_MESSAGE_PART_TYPES } from "../../blocks/ai-chat/message.ts";
import { sqlString } from "../../core/template.ts";
import { schemaPreamble, tenantIn } from "../shared.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";
import { aiChatDurable } from "./ai-chat-durable.ts";
import { aiChatFunctions } from "./ai-chat-functions.ts";

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

const HARNESS = {
  chat: "chat_id",
  harness: "harness_id",
  owner: "owner_id",
  resume: "resume_state",
  continue: "continue_state",
  sandbox: "sandbox_id",
  status: "status",
  holder: "lock_holder",
  lockedUntil: "locked_until",
  lastActiveAt: "last_active_at",
  createdAt: "created_at",
  updatedAt: "updated_at",
} as const;

const NAMES: ModuleNames = {
  options: ["topic", "listTopic", "temporaryTtl", "staleAfter"],
  tables: {
    projects: {
      name: "ai_projects",
      columns: PROJECTS,
      lifecycle: { user: "owner", tenant: "tenant" },
    },
    chats: {
      name: "ai_chats",
      columns: CHATS,
      lifecycle: { user: "owner", tenant: "tenant", omit: ["search"] },
    },
    messages: {
      name: "ai_messages",
      columns: MESSAGES,
      lifecycle: { user: "owner", omit: ["search"] },
    },
    runs: { name: "ai_runs", columns: RUNS, lifecycle: { user: "owner" } },
    approvals: {
      name: "ai_tool_approvals",
      columns: APPROVALS,
      lifecycle: { user: "owner" },
    },
    policies: {
      name: "ai_tool_policies",
      columns: POLICIES,
      lifecycle: { tenant: "tenant" },
    },
    inputs: {
      name: "ai_pending_inputs",
      columns: INPUTS,
      lifecycle: { user: "owner" },
    },
    sources: { name: "ai_message_sources", columns: SOURCES },
    feedback: {
      name: "ai_message_feedback",
      columns: FEEDBACK,
      lifecycle: { user: "user" },
    },
    shares: {
      name: "ai_chat_shares",
      columns: SHARES,
      lifecycle: { user: "createdBy", omit: ["tokenHash"] },
    },
    models: { name: "ai_model_catalog", columns: MODELS },
    moderation: {
      name: "ai_moderation_events",
      columns: MODERATION,
      lifecycle: { user: "user", tenant: "tenant" },
    },
    steps: {
      name: "ai_run_steps",
      columns: STEPS,
      lifecycle: { user: "owner" },
    },
    harness: {
      name: "ai_harness_sessions",
      columns: HARNESS,
      lifecycle: { user: "owner" },
    },
  },
};

type Columns<T> = { readonly [K in keyof T]: string };

/** Every logical column of `table`, quoted. */
function columnsOf<T extends Readonly<Record<string, string>>>(
  ctx: ModuleContext,
  table: string,
  spec: T,
): Columns<T> {
  // SAFETY: the keys are spec's own keys, each mapped to its quoted name.
  return Object.fromEntries(
    Object.keys(spec).map((key) => [key, ctx.col(table, key)]),
  ) as Columns<T>;
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
}

const TOPIC = /^[a-z][a-z0-9_-]{0,30}$/;
const INTERVAL =
  /^\d{1,6} (?:second|minute|hour|day|week)s?(?: \d{1,6} (?:second|minute|hour|day|week)s?)*$/;

function topicOption(
  ctx: ModuleContext,
  name: string,
  fallback: string,
): string {
  const value = ctx.text(name, fallback);
  if (!TOPIC.test(value)) {
    throw new TypeError(
      `sql.modules.ai-chat.options.${name} must be a lowercase name of at most 31 characters`,
    );
  }
  return value;
}

function intervalOption(
  ctx: ModuleContext,
  name: string,
  fallback: string,
): string {
  const value = ctx.text(name, fallback);
  if (!INTERVAL.test(value)) {
    throw new TypeError(
      `sql.modules.ai-chat.options.${name} must be an interval such as "1 day" or "10 minutes"`,
    );
  }
  return value;
}

function namesOf(ctx: ModuleContext): AiChatNames {
  const permissions = MODULE_PERMISSIONS["ai-chat"];
  const topic = topicOption(ctx, "topic", "ai-chat");
  const listTopic = topicOption(ctx, "listTopic", "ai-chats");
  if (topic === listTopic) {
    throw new TypeError(
      "sql.modules.ai-chat.options.topic and listTopic must differ",
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
  };
}

function tables(ctx: ModuleContext, names: AiChatNames): string {
  const id = ctx.idType;
  const { c, t, perm } = names;
  const p = c.projects;
  const ch = c.chats;
  const m = c.messages;
  const r = c.runs;
  const a = c.approvals;
  const po = c.policies;
  const i = c.inputs;
  const s = c.sources;
  const f = c.feedback;
  const sh = c.shares;
  const mo = c.models;
  const md = c.moderation;
  const rs = c.steps;
  const hs = c.harness;
  const partTypes = AI_MESSAGE_PART_TYPES.map(
    (type) => `@.type == "${type}"`,
  ).join(" || ");
  const textParts = `jsonb_path_query_array(${m.parts}, '$[*] ? (@.type == "text").text')`;
  const lock = (
    table: string,
  ): string => `alter table ${table} enable row level security;
revoke all on ${table} from anon, authenticated;
grant all on ${table} to service_role;`;
  const visible = tenantIn(ch.tenant, perm.read);

  return `-- Projects group chats and carry instructions and a default model.
create table if not exists ${t.projects} (
  ${p.id} uuid primary key default gen_random_uuid(),
  ${p.tenant} ${id} not null,
  ${p.owner} uuid not null references auth.users (id) on delete cascade,
  ${p.name} text not null check (length(${p.name}) between 1 and 200),
  ${p.instructions} text not null default '' check (length(${p.instructions}) <= 20000),
  ${p.model} text check (length(${p.model}) <= 200),
  ${p.pinned} boolean not null default false,
  ${p.archivedAt} timestamptz,
  ${p.createdAt} timestamptz not null default now(),
  ${p.updatedAt} timestamptz not null default now()
);
create index if not exists ai_projects_owner_idx on ${t.projects} (${p.owner}, ${p.tenant});
${lock(t.projects)}
grant select on ${t.projects} to authenticated;
drop policy if exists ai_projects_owner_read on ${t.projects};
create policy ai_projects_owner_read on ${t.projects} for select to authenticated
  using (${p.owner} = (select auth.uid()));

-- One row per conversation. current_leaf_id is the message the chat shows;
-- active_stream_id is the reply being written, claimed compare-and-set.
create table if not exists ${t.chats} (
  ${ch.id} uuid primary key default gen_random_uuid(),
  ${ch.tenant} ${id} not null,
  ${ch.owner} uuid not null references auth.users (id) on delete cascade,
  ${ch.project} uuid references ${t.projects} (${p.id}) on delete set null,
  ${ch.agent} text check (length(${ch.agent}) <= 200),
  ${ch.title} text not null default '' check (length(${ch.title}) <= 300),
  ${ch.model} text check (length(${ch.model}) <= 200),
  ${ch.visibility} text not null default 'private' check (${ch.visibility} in ('private', 'organization')),
  ${ch.pinned} boolean not null default false,
  ${ch.archivedAt} timestamptz,
  ${ch.temporary} boolean not null default false,
  ${ch.expiresAt} timestamptz,
  ${ch.leaf} text,
  ${ch.activeStream} text,
  ${ch.activeRun} uuid,
  ${ch.lastMessageAt} timestamptz not null default clock_timestamp(),
  ${ch.createdAt} timestamptz not null default now(),
  ${ch.updatedAt} timestamptz not null default now(),
  ${ch.search} tsvector generated always as (to_tsvector('simple'::regconfig, ${ch.title})) stored,
  check (not ${ch.temporary} or ${ch.expiresAt} is not null)
);
create index if not exists ai_chats_owner_idx on ${t.chats} (${ch.owner}, ${ch.lastMessageAt} desc, ${ch.id} desc);
create index if not exists ai_chats_tenant_idx on ${t.chats} (${ch.tenant});
create index if not exists ai_chats_project_idx on ${t.chats} (${ch.project});
create index if not exists ai_chats_expires_idx on ${t.chats} (${ch.expiresAt}) where ${ch.temporary};
create index if not exists ai_chats_search_idx on ${t.chats} using gin (${ch.search});
${lock(t.chats)}
grant select on ${t.chats} to authenticated;
drop policy if exists ai_chats_read on ${t.chats};
create policy ai_chats_read on ${t.chats} for select to authenticated
  using (
    ${ch.owner} = (select auth.uid())
    or (${ch.visibility} = 'organization' and ${visible})
  );

-- The message tree: (chat_id, id) is the key, parent_id the previous turn.
-- Editing a prompt or regenerating a reply adds a sibling, never an update.
-- parts holds the canonical AI message parts; native the SDK's own shape.
create table if not exists ${t.messages} (
  ${m.chat} uuid not null references ${t.chats} (${ch.id}) on delete cascade,
  ${m.id} text not null check (length(${m.id}) between 1 and 200),
  ${m.parent} text,
  ${m.owner} uuid not null,
  ${m.role} text not null check (${m.role} in ('system', 'user', 'assistant', 'tool')),
  ${m.parts} jsonb not null default '[]' check (
    jsonb_typeof(${m.parts}) = 'array'
    and not jsonb_path_exists(${m.parts}, '$[*] ? (!(${partTypes}))')
  ),
  ${m.format} text not null default 'canonical' check (length(${m.format}) between 1 and 50),
  ${m.native} jsonb,
  ${m.metadata} jsonb not null default '{}' check (jsonb_typeof(${m.metadata}) = 'object'),
  ${m.model} text,
  ${m.status} text not null default 'complete' check (${m.status} in ('complete', 'aborted', 'error')),
  ${m.seq} bigint generated always as identity,
  ${m.createdAt} timestamptz not null default now(),
  ${m.search} tsvector generated always as (to_tsvector('simple'::regconfig, ${textParts})) stored,
  primary key (${m.chat}, ${m.id}),
  foreign key (${m.chat}, ${m.parent}) references ${t.messages} (${m.chat}, ${m.id}) on delete cascade
);
create index if not exists ai_messages_parent_idx on ${t.messages} (${m.chat}, ${m.parent});
create index if not exists ai_messages_owner_idx on ${t.messages} (${m.owner});
create index if not exists ai_messages_search_idx on ${t.messages} using gin (${m.search});
${lock(t.messages)}
grant select on ${t.messages} to authenticated;
drop policy if exists ai_messages_read on ${t.messages};
create policy ai_messages_read on ${t.messages} for select to authenticated
  using (${m.chat} in (select x.${ch.id} from ${t.chats} x));

-- One generation: the stream it wrote, its usage and cost.
create table if not exists ${t.runs} (
  ${r.id} uuid primary key default gen_random_uuid(),
  ${r.chat} uuid not null references ${t.chats} (${ch.id}) on delete cascade,
  ${r.owner} uuid not null,
  ${r.message} text,
  ${r.stream} text,
  ${r.engine} text not null default 'ai-sdk' check (length(${r.engine}) between 1 and 50),
  ${r.externalRun} text check (length(${r.externalRun}) <= 200),
  ${r.model} text,
  ${r.status} text not null default 'running' check (${r.status} in ('queued', 'running', 'cancel_requested', 'done', 'error', 'stopped')),
  ${r.generation} text,
  ${r.usage} jsonb not null default '{}' check (jsonb_typeof(${r.usage}) = 'object'),
  ${r.cost} bigint check (${r.cost} >= 0),
  ${r.error} text,
  ${r.startedAt} timestamptz not null default now(),
  ${r.endedAt} timestamptz
);
create index if not exists ai_runs_chat_idx on ${t.runs} (${r.chat}, ${r.startedAt} desc);
create index if not exists ai_runs_owner_idx on ${t.runs} (${r.owner});
create index if not exists ai_runs_generation_idx on ${t.runs} (${r.generation}) where ${r.generation} is not null;
create index if not exists ai_runs_external_idx on ${t.runs} (${r.engine}, ${r.externalRun}) where ${r.externalRun} is not null;
${lock(t.runs)}
grant select on ${t.runs} to authenticated;
drop policy if exists ai_runs_owner_read on ${t.runs};
create policy ai_runs_owner_read on ${t.runs} for select to authenticated
  using (${r.owner} = (select auth.uid()));

-- Tool calls that wait for a person: requested by the server, decided once.
create table if not exists ${t.approvals} (
  ${a.id} text primary key check (length(${a.id}) between 1 and 200),
  ${a.chat} uuid not null references ${t.chats} (${ch.id}) on delete cascade,
  ${a.owner} uuid not null,
  ${a.run} uuid references ${t.runs} (${r.id}) on delete set null,
  ${a.message} text,
  ${a.tool} text not null check (length(${a.tool}) between 1 and 200),
  ${a.toolCall} text not null,
  ${a.input} jsonb,
  ${a.decision} text check (${a.decision} in ('approved', 'denied')),
  ${a.reason} text check (length(${a.reason}) <= 2000),
  ${a.signature} text,
  ${a.decidedBy} uuid,
  ${a.decidedAt} timestamptz,
  ${a.createdAt} timestamptz not null default now()
);
create index if not exists ai_tool_approvals_chat_idx on ${t.approvals} (${a.chat});
create index if not exists ai_tool_approvals_run_idx on ${t.approvals} (${a.run});
create index if not exists ai_tool_approvals_owner_idx on ${t.approvals} (${a.owner});
${lock(t.approvals)}
grant select on ${t.approvals} to authenticated;
drop policy if exists ai_tool_approvals_owner_read on ${t.approvals};
create policy ai_tool_approvals_owner_read on ${t.approvals} for select to authenticated
  using (${a.owner} = (select auth.uid()));

-- Per tenant: whether a tool runs (auto), waits for approval (ask) or never
-- runs (deny).
create table if not exists ${t.policies} (
  ${po.tenant} ${id} not null,
  ${po.tool} text not null check (length(${po.tool}) between 1 and 200),
  ${po.policy} text not null check (${po.policy} in ('auto', 'ask', 'deny')),
  ${po.updatedAt} timestamptz not null default now(),
  primary key (${po.tenant}, ${po.tool})
);
${lock(t.policies)}

-- A question the model asked the user mid-run (a form or a choice).
create table if not exists ${t.inputs} (
  ${i.id} uuid primary key default gen_random_uuid(),
  ${i.chat} uuid not null references ${t.chats} (${ch.id}) on delete cascade,
  ${i.owner} uuid not null,
  ${i.run} uuid references ${t.runs} (${r.id}) on delete set null,
  ${i.toolCall} text,
  ${i.question} text not null check (length(${i.question}) between 1 and 2000),
  ${i.schema} jsonb,
  ${i.answer} jsonb,
  ${i.answeredAt} timestamptz,
  ${i.createdAt} timestamptz not null default now()
);
create index if not exists ai_pending_inputs_chat_idx on ${t.inputs} (${i.chat});
create index if not exists ai_pending_inputs_run_idx on ${t.inputs} (${i.run});
create index if not exists ai_pending_inputs_owner_idx on ${t.inputs} (${i.owner});
${lock(t.inputs)}
grant select on ${t.inputs} to authenticated;
drop policy if exists ai_pending_inputs_owner_read on ${t.inputs};
create policy ai_pending_inputs_owner_read on ${t.inputs} for select to authenticated
  using (${i.owner} = (select auth.uid()));

-- The sources a reply cited, copied out of its parts when it is saved.
create table if not exists ${t.sources} (
  ${s.chat} uuid not null,
  ${s.message} text not null,
  ${s.source} text not null,
  ${s.kind} text not null default 'url' check (${s.kind} in ('url', 'document')),
  ${s.url} text,
  ${s.title} text,
  ${s.metadata} jsonb,
  primary key (${s.chat}, ${s.message}, ${s.source}),
  foreign key (${s.chat}, ${s.message}) references ${t.messages} (${m.chat}, ${m.id}) on delete cascade
);
${lock(t.sources)}
grant select on ${t.sources} to authenticated;
drop policy if exists ai_message_sources_read on ${t.sources};
create policy ai_message_sources_read on ${t.sources} for select to authenticated
  using (${s.chat} in (select x.${ch.id} from ${t.chats} x));

-- Thumbs up (1) or down (-1) on a reply, one per user.
create table if not exists ${t.feedback} (
  ${f.chat} uuid not null,
  ${f.message} text not null,
  ${f.user} uuid not null references auth.users (id) on delete cascade,
  ${f.rating} smallint not null check (${f.rating} in (-1, 1)),
  ${f.reason} text check (length(${f.reason}) <= 200),
  ${f.comment} text check (length(${f.comment}) <= 4000),
  ${f.createdAt} timestamptz not null default now(),
  ${f.updatedAt} timestamptz not null default now(),
  primary key (${f.chat}, ${f.message}, ${f.user}),
  foreign key (${f.chat}, ${f.message}) references ${t.messages} (${m.chat}, ${m.id}) on delete cascade
);
create index if not exists ai_message_feedback_user_idx on ${t.feedback} (${f.user});
${lock(t.feedback)}
grant select on ${t.feedback} to authenticated;
drop policy if exists ai_message_feedback_own_read on ${t.feedback};
create policy ai_message_feedback_own_read on ${t.feedback} for select to authenticated
  using (${f.user} = (select auth.uid()));

-- A read-only link to one branch of a chat. Only the SHA-256 of the token is
-- stored; the token is returned once.
create table if not exists ${t.shares} (
  ${sh.id} uuid primary key default gen_random_uuid(),
  ${sh.chat} uuid not null references ${t.chats} (${ch.id}) on delete cascade,
  ${sh.tokenHash} text not null unique check (${sh.tokenHash} ~ '^[0-9a-f]{64}$'),
  ${sh.leaf} text not null,
  ${sh.createdBy} uuid not null references auth.users (id) on delete cascade,
  ${sh.createdAt} timestamptz not null default now(),
  ${sh.revokedAt} timestamptz
);
create index if not exists ai_chat_shares_chat_idx on ${t.shares} (${sh.chat});
create index if not exists ai_chat_shares_created_by_idx on ${t.shares} (${sh.createdBy});
${lock(t.shares)}

-- The models a tenant may pick, refreshed from the gateway. plans limits a
-- model to tenants with one of those entitlements; empty means everyone.
create table if not exists ${t.models} (
  ${mo.id} text primary key check (length(${mo.id}) between 1 and 200),
  ${mo.provider} text not null default '',
  ${mo.name} text not null default '',
  ${mo.pricing} jsonb not null default '{}',
  ${mo.capabilities} jsonb not null default '{}',
  ${mo.plans} text[] not null default '{}',
  ${mo.enabled} boolean not null default true,
  ${mo.refreshedAt} timestamptz not null default now()
);
${lock(t.models)}

-- What moderation decided about an input, an output or a tool call.
create table if not exists ${t.moderation} (
  ${md.id} uuid primary key default gen_random_uuid(),
  ${md.tenant} ${id} not null,
  ${md.chat} uuid references ${t.chats} (${ch.id}) on delete set null,
  ${md.message} text,
  ${md.user} uuid references auth.users (id) on delete set null,
  ${md.stage} text not null check (${md.stage} in ('input', 'output', 'tool')),
  ${md.category} text not null check (length(${md.category}) between 1 and 100),
  ${md.score} real,
  ${md.action} text not null check (${md.action} in ('allow', 'flag', 'redact', 'block')),
  ${md.createdAt} timestamptz not null default now()
);
create index if not exists ai_moderation_events_tenant_idx on ${t.moderation} (${md.tenant}, ${md.createdAt} desc);
create index if not exists ai_moderation_events_chat_idx on ${t.moderation} (${md.chat});
create index if not exists ai_moderation_events_user_idx on ${t.moderation} (${md.user});
${lock(t.moderation)}

-- The progress of a long run, one row per step key, so a reload shows it.
create table if not exists ${t.steps} (
  ${rs.id} uuid primary key default gen_random_uuid(),
  ${rs.run} uuid not null references ${t.runs} (${r.id}) on delete cascade,
  ${rs.chat} uuid not null references ${t.chats} (${ch.id}) on delete cascade,
  ${rs.owner} uuid not null,
  ${rs.key} text not null check (length(${rs.key}) between 1 and 200),
  ${rs.label} text not null check (length(${rs.label}) between 1 and 300),
  ${rs.status} text not null default 'running' check (${rs.status} in ('running', 'done', 'error', 'skipped')),
  ${rs.detail} jsonb not null default '{}' check (jsonb_typeof(${rs.detail}) = 'object'),
  ${rs.startedAt} timestamptz not null default now(),
  ${rs.endedAt} timestamptz,
  unique (${rs.run}, ${rs.key})
);
create index if not exists ai_run_steps_chat_idx on ${t.steps} (${rs.chat});
create index if not exists ai_run_steps_owner_idx on ${t.steps} (${rs.owner});
${lock(t.steps)}
grant select on ${t.steps} to authenticated;
drop policy if exists ai_run_steps_owner_read on ${t.steps};
create policy ai_run_steps_owner_read on ${t.steps} for select to authenticated
  using (${rs.owner} = (select auth.uid()));

-- What a coding-agent harness needs to pick up a chat again: its resume and
-- continue state and the sandbox it runs in. lock_holder and locked_until
-- keep two turns from driving one sandbox. Experimental.
create table if not exists ${t.harness} (
  ${hs.chat} uuid not null references ${t.chats} (${ch.id}) on delete cascade,
  ${hs.harness} text not null check (length(${hs.harness}) between 1 and 200),
  ${hs.owner} uuid not null,
  ${hs.resume} jsonb,
  ${hs.continue} jsonb,
  ${hs.sandbox} text check (length(${hs.sandbox}) <= 500),
  ${hs.status} text not null default 'active' check (${hs.status} in ('active', 'idle', 'stopped', 'error')),
  ${hs.holder} text check (length(${hs.holder}) <= 200),
  ${hs.lockedUntil} timestamptz,
  ${hs.lastActiveAt} timestamptz not null default now(),
  ${hs.createdAt} timestamptz not null default now(),
  ${hs.updatedAt} timestamptz not null default now(),
  primary key (${hs.chat}, ${hs.harness})
);
create index if not exists ai_harness_sessions_owner_idx on ${t.harness} (${hs.owner});
create index if not exists ai_harness_sessions_idle_idx on ${t.harness} (${hs.lastActiveAt}) where ${hs.status} = 'active' and ${hs.sandbox} is not null;
${lock(t.harness)}
grant select on ${t.harness} to authenticated;
drop policy if exists ai_harness_sessions_owner_read on ${t.harness};
create policy ai_harness_sessions_owner_read on ${t.harness} for select to authenticated
  using (${hs.owner} = (select auth.uid()));`;
}

function realtime(ctx: ModuleContext, names: AiChatNames): string {
  const chatReceive = ctx.trigger("ai_chat_receive");
  const listReceive = ctx.trigger("ai_chats_receive");
  const prefix = `${names.topic}:`;
  return `-- A chat's readers join ${names.topic}:{chatId}; each user joins
-- ${names.listTopic}:{userId} for their sidebar. Payloads carry ids only.
do $$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists ${chatReceive} on realtime.messages;
    create policy ${chatReceive} on realtime.messages for select to authenticated
      using (
        realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) like ${sqlString(`${prefix}%`)}
        and substr((select realtime.topic()), ${String(prefix.length + 1)}) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        and ${ctx.fn("ai_chat_can_read")}(substr((select realtime.topic()), ${String(prefix.length + 1)})::uuid)
      );
    drop policy if exists ${listReceive} on realtime.messages;
    create policy ${listReceive} on realtime.messages for select to authenticated
      using (
        realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) = ${sqlString(`${names.listTopic}:`)} || (select auth.uid())::text
      );
  end if;
end;
$$;`;
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const names = namesOf(ctx);
  return `${schemaPreamble(ctx)}
${tables(ctx, names)}

${aiChatFunctions(ctx, names)}

${aiChatDurable(ctx, names)}

${realtime(ctx, names)}`;
}

function contract(): readonly ModuleContractFunction[] {
  const fn = (
    name: string,
    args: readonly string[],
    returns = "jsonb",
  ): ModuleContractFunction => ({ name, args, returns });
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
    fn("idle_ai_harness_sessions", ["integer", "integer"]),
  ];
}

export const AI_CHAT: ModuleDefinition = {
  name: "ai-chat",
  title: "AI chat",
  description:
    "Chats, projects and a branching message tree in the canonical AI message format, with runs (and the id of a durable engine's run), run steps for progress, a compare-and-set stream claim, harness sessions, tool approvals and policies, pending inputs, cited sources, feedback, hashed share links, a model catalog per plan, moderation events and private Realtime topics per chat and per user.",
  requires: ["tenant", "access", "streams"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
  topics: (ctx) => [
    `${topicOption(ctx, "topic", "ai-chat")}:{chatId}`,
    `${topicOption(ctx, "listTopic", "ai-chats")}:{userId}`,
  ],
};
