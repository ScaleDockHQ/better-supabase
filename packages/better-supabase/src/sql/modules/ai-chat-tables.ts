import type { BlockSqlContext } from "../context.ts";
import type { AiChatNames } from "./ai-chat.ts";

import { AI_MESSAGE_PART_TYPES } from "../../core/contracts/ai-message.ts";
import { FINAL_RUN_STATES as FINAL } from "../../core/run-state.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { addExtraColumns, extraFieldsJson, lockTable } from "../shared.ts";

/** Every status an `ai_runs` row can have, as a SQL list. */
export const AI_RUN_STATES: string = [
  "queued",
  "running",
  "cancel_requested",
  ...FINAL,
]
  .map(sqlString)
  .join(", ");

/**
 * The option that adds app columns to each table. The chats table keeps
 * `extraColumns`; every other table has its own key.
 */
export const AI_CHAT_EXTRA_OPTIONS = {
  projects: "projectExtraColumns",
  chats: "extraColumns",
  participants: "participantExtraColumns",
  messages: "messageExtraColumns",
  runs: "runExtraColumns",
  approvals: "approvalExtraColumns",
  policies: "policyExtraColumns",
  inputs: "inputExtraColumns",
  sources: "sourceExtraColumns",
  feedback: "feedbackExtraColumns",
  shares: "shareExtraColumns",
  models: "modelExtraColumns",
  moderation: "moderationExtraColumns",
  steps: "stepExtraColumns",
  sandboxes: "sandboxExtraColumns",
  harness: "harnessExtraColumns",
} as const;

export type AiChatTable = keyof typeof AI_CHAT_EXTRA_OPTIONS;

/** Whether `name` is a logical ai-chat table. */
export function isAiChatTable(name: string): name is AiChatTable {
  return Object.hasOwn(AI_CHAT_EXTRA_OPTIONS, name);
}

/**
 * `row.column` of the logical ai-chat `table`, or `fallback` when the app's
 * table lacks the optional column.
 */
export function columnOr(
  ctx: BlockSqlContext,
  table: string,
  row: string,
  column: string,
  fallback = "null",
): string {
  return ctx.has(table, column) ? `${row}.${ctx.col(table, column)}` : fallback;
}

/**
 * `jsonb_build_object` of `row` with a key per entry: `[key, column]` reads the
 * column, `[key, column, fallback]` reads `fallback` when the app's table lacks
 * the optional column.
 */
export function rowJson(
  ctx: BlockSqlContext,
  table: string,
  row: string,
  keys: readonly (readonly [string, string, string?])[],
  extra = "",
): string {
  const fields =
    table !== "chats" && isAiChatTable(table)
      ? extraFieldsJson(
          row,
          ctx.extraColumns(table, [], AI_CHAT_EXTRA_OPTIONS[table]),
        )
      : "";

  return `jsonb_build_object(${keys.map(([key, column, fallback]) => `'${key}', ${columnOr(ctx, table, row, column, fallback)}`).join(", ")}${extra}${fields})`;
}

/**
 * The quoted columns and values of the pairs whose column `table` has, for an
 * insert: `[columns, values]`, each joined with `, `. A value that starts with
 * a newline starts a new line of the values list.
 */
export function writtenPairs(
  ctx: BlockSqlContext,
  table: string,
  pairs: readonly (readonly [string, string])[],
): readonly [string, string] {
  const kept = pairs.filter(([column]) => ctx.has(table, column));

  return [
    kept.map(([column]) => ctx.col(table, column)).join(", "),
    kept
      .map(([, value]) => value)
      .join(", ")
      .replaceAll(", \n", ",\n"),
  ];
}

/**
 * A `column = value,` line for each pair whose column `table` has, for an
 * update's set list, each after the previous line's comma.
 */
export function assignments(
  ctx: BlockSqlContext,
  table: string,
  pairs: readonly (readonly [string, () => string])[],
  indent = "    ",
): string {
  return pairs
    .filter(([column]) => ctx.has(table, column))
    .map(
      ([column, value]) => `\n${indent}${ctx.col(table, column)} = ${value()},`,
    )
    .join("");
}

/**
 * `expression`, read from a typed column of `table`, as text over the app's
 * table, whose column may be an enum or a domain.
 */
export function asText(
  ctx: BlockSqlContext,
  table: string,
  expression: string,
): string {
  return ctx.owns(table) ? expression : `${expression}::text`;
}

/**
 * The `#variable_conflict` of a function writing `tables`: the app's column
 * names may match a parameter's, so over an app table columns win, and every
 * parameter is qualified with the function's name.
 */
export function variableConflict(
  ctx: BlockSqlContext,
  ...tables: readonly string[]
): string {
  return `#variable_conflict ${tables.every((table) => ctx.owns(table)) ? "use_variable" : "use_column"}`;
}

/**
 * A unique index over `columns` of the app's `table`, which `insert ... on
 * conflict` needs since the render drops the module's own keys there. Empty on
 * the module's own table, whose primary key or unique constraint serves.
 */
export function appKey(
  ctx: BlockSqlContext,
  table: string,
  what: string,
  columns: readonly string[],
): string {
  if (ctx.owns(table)) {
    return "";
  }

  return `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(table).name}_${what}_key`)} on ${ctx.table(table)} (${columns.map((column) => ctx.col(table, column)).join(", ")});`;
}

/**
 * A condition true when the caller takes part in chat `chat` (an expression)
 * through `ai_chat_participants`, in one of `roles` (any role when empty).
 */
export function participates(
  names: AiChatNames,
  chat: string,
  roles: readonly ("viewer" | "editor")[] = [],
): string {
  const pa = names.c.participants;

  return `exists (select 1 from ${names.t.participants} pa where pa.${pa.chat} = ${chat} and pa.${pa.user} = (select auth.uid())${roles.length === 0 ? "" : ` and pa.${pa.role}::text in (${roles.map(sqlString).join(", ")})`})`;
}

/**
 * The `alter table` lines that apply `options.tenant: false` to an existing
 * table the module owns: its tenant column takes nulls.
 */
function nullableTenant(
  ctx: BlockSqlContext,
  names: AiChatNames,
  table: string,
): string {
  if (!names.tenantless || !ctx.owns(table)) {
    return "";
  }

  return `\nalter table ${ctx.table(table)} alter column ${ctx.col(table, "tenant")} drop not null;`;
}

/** The ai-chat tables, their indexes and policies. */
export function aiChatTables(ctx: BlockSqlContext, names: AiChatNames): string {
  const id = ctx.idType;
  const tenantId = names.tenantless ? id : `${id} not null`;
  const { c, t, perm, extras } = names;
  const mode = names.messages;
  const pa = c.participants;
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

  /**
   * The line of an optional column, after the previous line's comma, or with
   * its own leading comma when it is the table's last line.
   */
  const opt =
    (table: string) =>
    (column: string, definition: (name: string) => string, last = false) => {
      if (!ctx.has(table, column)) {
        return "";
      }

      const line = `\n  ${ctx.col(table, column)} ${definition(ctx.col(table, column))}`;

      return last ? `,${line}` : `${line},`;
    };

  const partTypes = AI_MESSAGE_PART_TYPES.map(
    (type) => `@.type == "${type}"`,
  ).join(" || ");

  const partsCheck = mode.native
    ? `not jsonb_path_exists(${m.parts}, '$[*] ? (!exists(@.type) || @.type.type() != "string")')`
    : `not jsonb_path_exists(${m.parts}, '$[*] ? (!(${partTypes}))')`;

  const textParts = `jsonb_path_query_array(${m.parts}, '$[*] ? (@.type == "text").text')`;
  const visible = ctx.scope.check(ch.tenant, perm.read);
  const parentLine = mode.tree ? `\n  ${m.parent} ${mode.idType},` : "";

  const parentKey = mode.tree
    ? `,\n  foreign key (${m.chat}, ${m.parent}) references ${t.messages} (${m.chat}, ${m.id}) on delete cascade`
    : "";

  const messageId = mode.uuid
    ? "uuid not null default gen_random_uuid()"
    : `text not null check (length(${m.id}) between 1 and 200)`;

  const pOpt = opt("projects");
  const chOpt = opt("chats");
  const mOpt = opt("messages");
  const rOpt = opt("runs");
  const aOpt = opt("approvals");
  const iOpt = opt("inputs");
  const sOpt = opt("sources");
  const fOpt = opt("feedback");
  const moOpt = opt("models");
  const mdOpt = opt("moderation");
  const hsOpt = opt("harness");

  return `-- Projects group chats and carry instructions and a default model.
create table if not exists ${t.projects} (
  ${p.id} uuid primary key default gen_random_uuid(),
  ${p.tenant} ${tenantId},
  ${p.owner} uuid not null references auth.users (id) on delete cascade,
  ${p.name} text not null check (length(${p.name}) between 1 and 200),
  ${p.instructions} text not null default '' check (length(${p.instructions}) <= 20000),
  ${p.model} text check (length(${p.model}) <= 200),${pOpt("pinned", () => "boolean not null default false")}${pOpt("archivedAt", () => "timestamptz")}${pOpt("createdAt", () => "timestamptz not null default now()")}
  ${p.updatedAt} timestamptz not null default now()
);
create index if not exists ${ctx.naming.rename("ai_projects_owner_idx")} on ${t.projects} (${p.owner}, ${p.tenant});${nullableTenant(ctx, names, "projects")}${addExtraColumns(t.projects, extras.projects)}
${lockTable(t.projects)}
grant select on ${t.projects} to authenticated;
${renderPolicy(makePolicy({ table: t.projects, name: ctx.naming.rename("ai_projects_owner_read"), command: "select", roles: ["authenticated"], using: `${p.owner} = (select auth.uid())` }), { drop: true, target: t.projects })}

-- One row per conversation. current_leaf_id is the message the chat shows;
-- active_stream_id is the reply being written, claimed compare-and-set.
create table if not exists ${t.chats} (
  ${ch.id} uuid primary key default gen_random_uuid(),
  ${ch.tenant} ${tenantId},
  ${ch.owner} uuid not null references auth.users (id) on delete cascade,
  ${ch.project} uuid references ${t.projects} (${p.id}) on delete set null,${chOpt("agent", (name) => `text check (length(${name}) <= 200)`)}
  ${ch.title} text not null default '' check (length(${ch.title}) <= 300),
  ${ch.model} text check (length(${ch.model}) <= 200),
  ${ch.visibility} text not null default 'private' check (${ch.visibility} in ('private', 'organization')),${chOpt("pinned", () => "boolean not null default false")}${chOpt("archivedAt", () => "timestamptz")}
  ${ch.temporary} boolean not null default false,
  ${ch.expiresAt} timestamptz,
  ${ch.leaf} ${mode.idType},
  ${ch.activeStream} text,
  ${ch.activeRun} uuid,
  ${ch.lastMessageAt} timestamptz not null default clock_timestamp(),${chOpt("createdAt", () => "timestamptz not null default now()")}
  ${ch.updatedAt} timestamptz not null default now(),
  ${ch.search} tsvector generated always as (to_tsvector('simple'::regconfig, ${ch.title})) stored,
  check (not ${ch.temporary} or ${ch.expiresAt} is not null)
);
create index if not exists ${ctx.naming.rename("ai_chats_owner_idx")} on ${t.chats} (${ch.owner}, ${ch.lastMessageAt} desc, ${ch.id} desc);
create index if not exists ${ctx.naming.rename("ai_chats_tenant_idx")} on ${t.chats} (${ch.tenant});
create index if not exists ${ctx.naming.rename("ai_chats_project_idx")} on ${t.chats} (${ch.project});
create index if not exists ${ctx.naming.rename("ai_chats_expires_idx")} on ${t.chats} (${ch.expiresAt}) where ${ch.temporary};
create index if not exists ${ctx.naming.rename("ai_chats_search_idx")} on ${t.chats} using gin (${ch.search});${nullableTenant(ctx, names, "chats")}${addExtraColumns(t.chats, names.chatExtras)}
${lockTable(t.chats)}
grant select on ${t.chats} to authenticated;
${renderPolicy(
  makePolicy({
    table: t.chats,
    name: ctx.naming.rename("ai_chats_read"),
    command: "select",
    roles: ["authenticated"],
    using: `${ch.owner} = (select auth.uid())
    or (${asText(ctx, "chats", ch.visibility)} = 'organization' and ${visible})
    or ${participates(names, ch.id)}`,
  }),
  { drop: true, target: t.chats },
)}

-- People besides the owner who may read a chat (viewer) or also write to it
-- (editor). Each person sees only their own rows.
create table if not exists ${t.participants} (
  ${pa.chat} uuid not null references ${t.chats} (${ch.id}) on delete cascade,
  ${pa.user} uuid not null references auth.users (id) on delete cascade,
  ${pa.role} text not null default 'viewer' check (${pa.role} in ('viewer', 'editor')),${opt("participants")("addedBy", () => "uuid references auth.users (id) on delete set null")}${opt("participants")("createdAt", () => "timestamptz not null default now()")}
  primary key (${pa.chat}, ${pa.user})
);
create index if not exists ${ctx.naming.rename("ai_chat_participants_user_idx")} on ${t.participants} (${pa.user});${appKey(ctx, "participants", "user", ["chat", "user"])}${addExtraColumns(t.participants, extras.participants)}
${lockTable(t.participants)}
grant select on ${t.participants} to authenticated;
${renderPolicy(makePolicy({ table: t.participants, name: ctx.naming.rename("ai_chat_participants_own_read"), command: "select", roles: ["authenticated"], using: `${pa.user} = (select auth.uid())` }), { drop: true, target: t.participants })}

-- ${mode.tree ? "The message tree: (chat_id, id) is the key, parent_id the previous turn.\n-- Editing a prompt or regenerating a reply adds a sibling, never an update." : "One list of messages per chat, in seq order: a regenerated reply or an\n-- edited prompt replaces the messages after it."}
-- parts holds ${mode.native ? "the SDK's own message parts" : "the canonical AI message parts; native the SDK's own shape"}.
create table if not exists ${t.messages} (
  ${m.chat} uuid not null references ${t.chats} (${ch.id}) on delete cascade,
  ${m.id} ${messageId},${parentLine}
  ${m.owner} uuid not null,${mOpt("author", () => "uuid references auth.users (id) on delete set null")}
  ${m.role} text not null check (${m.role} in ('system', 'user', 'assistant', 'tool')),
  ${m.parts} jsonb not null default '[]' check (
    jsonb_typeof(${m.parts}) = 'array'
    and ${partsCheck}
  ),${mOpt("format", (name) => `text not null default '${mode.native ? "native" : "canonical"}' check (length(${name}) between 1 and 50)`)}${mOpt("native", () => "jsonb")}${mOpt("metadata", (name) => `jsonb not null default '{}' check (jsonb_typeof(${name}) = 'object')`)}${mOpt("model", () => "text")}
  ${m.status} text not null default 'complete' check (${m.status} in ('complete', 'aborted', 'error')),
  ${m.seq} bigint generated always as identity,
  ${m.createdAt} timestamptz not null default now(),
  ${m.search} tsvector generated always as (to_tsvector('simple'::regconfig, ${textParts})) stored,
  primary key (${m.chat}, ${m.id})${parentKey}
);${mode.tree ? `\ncreate index if not exists ai_messages_parent_idx on ${t.messages} (${m.chat}, ${m.parent});` : `\ncreate index if not exists ai_messages_seq_idx on ${t.messages} (${m.chat}, ${m.seq});`}
create index if not exists ai_messages_owner_idx on ${t.messages} (${m.owner});
create index if not exists ai_messages_search_idx on ${t.messages} using gin (${m.search});${ctx.owns("messages") && ctx.has("messages", "author") ? `\nalter table ${t.messages} add column if not exists ${m.author} uuid references auth.users (id) on delete set null;` : ""}${addExtraColumns(t.messages, extras.messages)}${appKey(ctx, "messages", "id", ["chat", "id"])}
${lockTable(t.messages)}
grant select on ${t.messages} to authenticated;
${renderPolicy(makePolicy({ table: t.messages, name: "ai_messages_read", command: "select", roles: ["authenticated"], using: `${m.chat} in (select x.${ch.id} from ${t.chats} x)` }), { drop: true, target: t.messages })}

-- One generation: the stream it wrote, its usage and cost.
create table if not exists ${t.runs} (
  ${r.id} uuid primary key default gen_random_uuid(),
  ${r.chat} uuid not null references ${t.chats} (${ch.id}) on delete cascade,
  ${r.owner} uuid not null,
  ${r.message} ${mode.idType},
  ${r.stream} text,
  ${r.engine} text not null default 'ai-sdk' check (length(${r.engine}) between 1 and 50),
  ${r.externalRun} text check (length(${r.externalRun}) <= 200),
  ${r.model} text,
  ${r.status} text not null default 'running' check (${r.status} in (${AI_RUN_STATES})),${rOpt("generation", () => "text")}
  ${r.usage} jsonb not null default '{}' check (jsonb_typeof(${r.usage}) = 'object'),${rOpt("cost", (name) => `bigint check (${name} >= 0)`)}${rOpt("error", () => "text")}
  ${r.startedAt} timestamptz not null default now(),
  ${r.endedAt} timestamptz
);${addExtraColumns(t.runs, extras.runs)}
create index if not exists ai_runs_chat_idx on ${t.runs} (${r.chat}, ${r.startedAt} desc);
create index if not exists ai_runs_owner_idx on ${t.runs} (${r.owner});${ctx.has("runs", "generation") ? `\ncreate index if not exists ai_runs_generation_idx on ${t.runs} (${r.generation}) where ${r.generation} is not null;` : ""}
create index if not exists ai_runs_external_idx on ${t.runs} (${r.engine}, ${r.externalRun}) where ${r.externalRun} is not null;
${lockTable(t.runs)}
grant select on ${t.runs} to authenticated;
${renderPolicy(makePolicy({ table: t.runs, name: "ai_runs_owner_read", command: "select", roles: ["authenticated"], using: `${r.owner} = (select auth.uid())` }), { drop: true, target: t.runs })}

-- Tool calls that wait for a person: requested by the server, decided once.
create table if not exists ${t.approvals} (
  ${a.id} text primary key check (length(${a.id}) between 1 and 200),
  ${a.chat} uuid not null references ${t.chats} (${ch.id}) on delete cascade,
  ${a.owner} uuid not null,
  ${a.run} uuid references ${t.runs} (${r.id}) on delete set null,${aOpt("message", () => mode.idType)}
  ${a.tool} text not null check (length(${a.tool}) between 1 and 200),
  ${a.toolCall} text not null,${aOpt("input", () => "jsonb")}
  ${a.decision} text check (${a.decision} in ('approved', 'denied')),${aOpt("reason", (name) => `text check (length(${name}) <= 2000)`)}${aOpt("signature", () => "text")}${aOpt("decidedBy", () => "uuid")}
  ${a.decidedAt} timestamptz,
  ${a.createdAt} timestamptz not null default now()
);
create index if not exists ai_tool_approvals_chat_idx on ${t.approvals} (${a.chat});
create index if not exists ai_tool_approvals_run_idx on ${t.approvals} (${a.run});
create index if not exists ai_tool_approvals_owner_idx on ${t.approvals} (${a.owner});${appKey(ctx, "approvals", "id", ["id"])}${addExtraColumns(t.approvals, extras.approvals)}
${lockTable(t.approvals)}
grant select on ${t.approvals} to authenticated;
${renderPolicy(makePolicy({ table: t.approvals, name: "ai_tool_approvals_owner_read", command: "select", roles: ["authenticated"], using: `${a.owner} = (select auth.uid())` }), { drop: true, target: t.approvals })}

-- Per tenant: whether a tool runs (auto), waits for approval (ask) or never
-- runs (deny).
create table if not exists ${t.policies} (
  ${po.tenant} ${id} not null,
  ${po.tool} text not null check (length(${po.tool}) between 1 and 200),
  ${po.policy} text not null check (${po.policy} in ('auto', 'ask', 'deny')),${opt("policies")("updatedAt", () => "timestamptz not null default now()")}
  primary key (${po.tenant}, ${po.tool})
);${appKey(ctx, "policies", "tool", ["tenant", "tool"])}${addExtraColumns(t.policies, extras.policies)}
${lockTable(t.policies)}

-- A question the model asked the user mid-run (a form or a choice).
create table if not exists ${t.inputs} (
  ${i.id} uuid primary key default gen_random_uuid(),
  ${i.chat} uuid not null references ${t.chats} (${ch.id}) on delete cascade,
  ${i.owner} uuid not null,
  ${i.run} uuid references ${t.runs} (${r.id}) on delete set null,${iOpt("toolCall", () => "text")}
  ${i.question} text not null check (length(${i.question}) between 1 and 2000),${iOpt("schema", () => "jsonb")}
  ${i.answer} jsonb,
  ${i.answeredAt} timestamptz${iOpt("createdAt", () => "timestamptz not null default now()", true)}
);
create index if not exists ai_pending_inputs_chat_idx on ${t.inputs} (${i.chat});
create index if not exists ai_pending_inputs_run_idx on ${t.inputs} (${i.run});
create index if not exists ai_pending_inputs_owner_idx on ${t.inputs} (${i.owner});${addExtraColumns(t.inputs, extras.inputs)}
${lockTable(t.inputs)}
grant select on ${t.inputs} to authenticated;
${renderPolicy(makePolicy({ table: t.inputs, name: "ai_pending_inputs_owner_read", command: "select", roles: ["authenticated"], using: `${i.owner} = (select auth.uid())` }), { drop: true, target: t.inputs })}

-- The sources a reply cited, copied out of its parts when it is saved.
create table if not exists ${t.sources} (
  ${s.chat} uuid not null,
  ${s.message} ${mode.idType} not null,
  ${s.source} text not null,
  ${s.kind} text not null default 'url' check (${s.kind} in ('url', 'document')),
  ${s.url} text,${sOpt("title", () => "text")}${sOpt("metadata", () => "jsonb")}
  primary key (${s.chat}, ${s.message}, ${s.source}),
  foreign key (${s.chat}, ${s.message}) references ${t.messages} (${m.chat}, ${m.id}) on delete cascade
);${addExtraColumns(t.sources, extras.sources)}
${lockTable(t.sources)}
grant select on ${t.sources} to authenticated;
${renderPolicy(makePolicy({ table: t.sources, name: "ai_message_sources_read", command: "select", roles: ["authenticated"], using: `${s.chat} in (select x.${ch.id} from ${t.chats} x)` }), { drop: true, target: t.sources })}

-- Thumbs up (1) or down (-1) on a reply, one per user.
create table if not exists ${t.feedback} (
  ${f.chat} uuid not null,
  ${f.message} ${mode.idType} not null,
  ${f.user} uuid not null references auth.users (id) on delete cascade,
  ${f.rating} smallint not null check (${f.rating} in (-1, 1)),${fOpt("reason", (name) => `text check (length(${name}) <= 200)`)}${fOpt("comment", (name) => `text check (length(${name}) <= 4000)`)}${fOpt("createdAt", () => "timestamptz not null default now()")}${fOpt("updatedAt", () => "timestamptz not null default now()")}
  primary key (${f.chat}, ${f.message}, ${f.user}),
  foreign key (${f.chat}, ${f.message}) references ${t.messages} (${m.chat}, ${m.id}) on delete cascade
);
create index if not exists ai_message_feedback_user_idx on ${t.feedback} (${f.user});${appKey(ctx, "feedback", "user", ["chat", "message", "user"])}${addExtraColumns(t.feedback, extras.feedback)}
${lockTable(t.feedback)}
grant select on ${t.feedback} to authenticated;
${renderPolicy(makePolicy({ table: t.feedback, name: "ai_message_feedback_own_read", command: "select", roles: ["authenticated"], using: `${f.user} = (select auth.uid())` }), { drop: true, target: t.feedback })}

-- A read-only link to one branch of a chat. Only the SHA-256 of the token is
-- stored; the token is returned once.
create table if not exists ${t.shares} (
  ${sh.id} uuid primary key default gen_random_uuid(),
  ${sh.chat} uuid not null references ${t.chats} (${ch.id}) on delete cascade,
  ${sh.tokenHash} text not null unique check (${sh.tokenHash} ~ '^[0-9a-f]{64}$'),
  ${sh.leaf} ${mode.idType} not null,
  ${sh.createdBy} uuid not null references auth.users (id) on delete cascade,
  ${sh.createdAt} timestamptz not null default now(),
  ${sh.revokedAt} timestamptz
);
create index if not exists ${ctx.naming.rename("ai_chat_shares_chat_idx")} on ${t.shares} (${sh.chat});
create index if not exists ${ctx.naming.rename("ai_chat_shares_created_by_idx")} on ${t.shares} (${sh.createdBy});${appKey(ctx, "shares", "token", ["tokenHash"])}${addExtraColumns(t.shares, extras.shares)}
${lockTable(t.shares)}

-- The models a tenant may pick, refreshed from the gateway. plans limits a
-- model to tenants with one of those entitlements; empty means everyone.
create table if not exists ${t.models} (
  ${mo.id} text primary key check (length(${mo.id}) between 1 and 200),
  ${mo.provider} text not null default '',
  ${mo.name} text not null default '',${moOpt("pricing", () => "jsonb not null default '{}'")}${moOpt("capabilities", () => "jsonb not null default '{}'")}
  ${mo.plans} text[] not null default '{}',
  ${mo.enabled} boolean not null default true${moOpt("refreshedAt", () => "timestamptz not null default now()", true)}
);${appKey(ctx, "models", "id", ["id"])}${addExtraColumns(t.models, extras.models)}
${lockTable(t.models)}

-- What moderation decided about an input, an output or a tool call.
create table if not exists ${t.moderation} (
  ${md.id} uuid primary key default gen_random_uuid(),
  ${md.tenant} ${tenantId},
  ${md.chat} uuid references ${t.chats} (${ch.id}) on delete set null,${mdOpt("message", () => mode.idType)}
  ${md.user} uuid references auth.users (id) on delete set null,
  ${md.stage} text not null check (${md.stage} in ('input', 'output', 'tool')),
  ${md.category} text not null check (length(${md.category}) between 1 and 100),${mdOpt("score", () => "real")}
  ${md.action} text not null check (${md.action} in ('allow', 'flag', 'redact', 'block')),
  ${md.createdAt} timestamptz not null default now()
);
create index if not exists ai_moderation_events_tenant_idx on ${t.moderation} (${md.tenant}, ${md.createdAt} desc);
create index if not exists ai_moderation_events_chat_idx on ${t.moderation} (${md.chat});
create index if not exists ai_moderation_events_user_idx on ${t.moderation} (${md.user});${nullableTenant(ctx, names, "moderation")}${addExtraColumns(t.moderation, extras.moderation)}
${lockTable(t.moderation)}

-- The progress of a long run, one row per step key, so a reload shows it.
create table if not exists ${t.steps} (
  ${rs.id} uuid primary key default gen_random_uuid(),
  ${rs.run} uuid not null references ${t.runs} (${r.id}) on delete cascade,
  ${rs.chat} uuid not null references ${t.chats} (${ch.id}) on delete cascade,
  ${rs.owner} uuid not null,
  ${rs.key} text not null check (length(${rs.key}) between 1 and 200),
  ${rs.label} text not null check (length(${rs.label}) between 1 and 300),
  ${rs.status} text not null default 'running' check (${rs.status} in ('running', 'done', 'error', 'skipped')),${opt("steps")("detail", (name) => `jsonb not null default '{}' check (jsonb_typeof(${name}) = 'object')`)}
  ${rs.startedAt} timestamptz not null default now(),
  ${rs.endedAt} timestamptz,
  unique (${rs.run}, ${rs.key})
);
create index if not exists ai_run_steps_chat_idx on ${t.steps} (${rs.chat});
create index if not exists ai_run_steps_owner_idx on ${t.steps} (${rs.owner});${appKey(ctx, "steps", "key", ["run", "key"])}${addExtraColumns(t.steps, extras.steps)}
${lockTable(t.steps)}
grant select on ${t.steps} to authenticated;
${renderPolicy(makePolicy({ table: t.steps, name: "ai_run_steps_owner_read", command: "select", roles: ["authenticated"], using: `${rs.owner} = (select auth.uid())` }), { drop: true, target: t.steps })}

-- What a coding-agent harness needs to pick up a chat again: its resume and
-- continue state; its sandbox is a row in ai_sandboxes. lock_holder and locked_until
-- keep two turns from driving one sandbox. Experimental.
create table if not exists ${t.harness} (
  ${hs.chat} uuid not null references ${t.chats} (${ch.id}) on delete cascade,
  ${hs.harness} text not null check (length(${hs.harness}) between 1 and 200),
  ${hs.owner} uuid not null,
  ${hs.resume} jsonb,${hsOpt("continue", () => "jsonb")}
  ${hs.status} text not null default 'active' check (${hs.status} in ('active', 'idle', 'stopped', 'error')),
  ${hs.holder} text check (length(${hs.holder}) <= 200),
  ${hs.lockedUntil} timestamptz,
  ${hs.lastActiveAt} timestamptz not null default now(),${hsOpt("createdAt", () => "timestamptz not null default now()")}
  ${hs.updatedAt} timestamptz not null default now(),
  primary key (${hs.chat}, ${hs.harness})
);
create index if not exists ai_harness_sessions_owner_idx on ${t.harness} (${hs.owner});
create index if not exists ai_harness_sessions_idle_idx on ${t.harness} (${hs.lastActiveAt}) where ${hs.status} = 'active';${appKey(ctx, "harness", "harness", ["chat", "harness"])}${addExtraColumns(t.harness, extras.harness)}
${lockTable(t.harness)}
-- Resume state can carry harness credentials and sandbox ids, so only the
-- service role reads it, through load_ai_harness_session.
drop policy if exists ai_harness_sessions_owner_read on ${t.harness};`;
}
