import "server-only";
import type { DbError } from "better-supabase";
import type { AiRunState } from "better-supabase/blocks/ai-chat";

import { tenantOf } from "better-supabase/next";

import type { OpsListQuery } from "@/components/ops-list/ops-list-params";

import { aiChat, aiRuns } from "@/features/assistant/assistant-server";
import { memory } from "@/features/knowledge/knowledge-server";
import { getSession } from "@/features/user/user-queries";
import { bsbCore } from "@/lib/supabase/server-core";

import type { ToolPolicyChoice } from "./agents-tools";

import { agentsBlock } from "./agents-server";
import { BUILT_IN_TOOLS } from "./agents-tools";

const PAGE_SIZE = 25;

/** The newest runs one read covers; a state count past it reads "200+". */
export const RUN_WINDOW = 200;

export interface AgentRow {
  readonly id: string;
  readonly slug: string;
  readonly name: string;
  readonly description: string;
  readonly model: string | undefined;
  readonly visibility: string;
  readonly tools: number;
  readonly installed: boolean;
  readonly installs: number;
  readonly rating: number | undefined;
  /** ISO 8601. */
  readonly updatedAt: string;
}

export interface AgentPage {
  readonly items: readonly AgentRow[];
  readonly nextCursor: string | null;
}

/** The organization's agents: the store, the caller's own or the installed ones. */
export async function getAgentPage(query: OpsListQuery): Promise<AgentPage> {
  const [session, { supabase }] = await Promise.all([
    getSession(),
    bsbCore.context(),
  ]);

  const organizationId = tenantOf(session);

  if (!organizationId) {
    return { items: [], nextCursor: null };
  }

  const filter =
    query.filter === "mine" || query.filter === "installed"
      ? query.filter
      : "store";

  const agents = await agentsBlock(supabase)
    .list({
      organizationId,
      filter,
      limit: 100,
      ...(query.q === "" ? {} : { search: query.q }),
    })
    .orThrow();

  const sorted =
    query.sort === "popular"
      ? agents.toSorted((a, b) => b.installCount - a.installCount)
      : query.sort === "name"
        ? agents.toSorted((a, b) => a.name.localeCompare(b.name))
        : agents.toSorted((a, b) =>
            b.updatedAt.toString().localeCompare(a.updatedAt.toString()),
          );

  const start = Number(query.cursor ?? 0);
  const slice = sorted.slice(start, start + PAGE_SIZE);

  return {
    items: slice.map((agent) => ({
      id: agent.id,
      slug: agent.slug,
      name: agent.name,
      description: agent.description,
      model: agent.model,
      visibility: agent.visibility,
      tools: agent.tools.length,
      installed: agent.installed,
      installs: agent.installCount,
      rating: agent.rating,
      updatedAt: agent.updatedAt.toString(),
    })),
    nextCursor:
      start + PAGE_SIZE < sorted.length ? String(start + PAGE_SIZE) : null,
  };
}

export interface AgentDetail {
  readonly id: string;
  readonly slug: string;
  readonly name: string;
  readonly description: string;
  readonly instructions: string;
  readonly model: string | undefined;
  readonly tools: readonly string[];
  readonly starters: readonly string[];
  readonly visibility: "private" | "organization" | "public";
  readonly installed: boolean;
  readonly installs: number;
  readonly rating: number | undefined;
  readonly skills: number;
  readonly knowledgeScopes: readonly string[];
  readonly connectors: number;
  /** ISO 8601. */
  readonly updatedAt: string;
}

/** One agent; `undefined` when it doesn't exist or RLS hides it. */
export async function getAgent(id: string): Promise<AgentDetail | undefined> {
  const { supabase } = await bsbCore.context();
  const result = await agentsBlock(supabase).get(id);

  if (!result.ok) {
    if (result.error.kind === "not_found") {
      return undefined;
    }

    throw new Error(result.error.message);
  }

  const agent = result.data;

  return {
    id: agent.id,
    slug: agent.slug,
    name: agent.name,
    description: agent.description,
    instructions: agent.instructions,
    model: agent.model,
    tools: agent.tools,
    starters: agent.starters,
    visibility: agent.visibility,
    installed: agent.installed,
    installs: agent.installCount,
    rating: agent.rating,
    skills: agent.skills.length,
    knowledgeScopes: agent.knowledgeScopes.map((entry) => entry.scope),
    connectors: agent.connectorIds.length,
    updatedAt: agent.updatedAt.toString(),
  };
}

export interface RunRow {
  readonly id: string;
  readonly chatId: string;
  readonly status: AiRunState;
  readonly engine: string;
  readonly model: string | undefined;
  /** ISO 8601. */
  readonly startedAt: string;
  readonly seconds: number | undefined;
  readonly costMicroUsd: number | undefined;
  readonly error: string | undefined;
}

export interface RunPage {
  readonly items: readonly RunRow[];
  readonly nextCursor: string | null;
  /** Runs per state in the window, for the queue header. */
  readonly counts: Readonly<Record<AiRunState, number>>;
  /** The window was full, so each count is a lower bound. */
  readonly capped: boolean;
}

const STATES: readonly AiRunState[] = [
  "queued",
  "running",
  "cancel_requested",
  "completed",
  "failed",
  "cancelled",
];

const secondsBetween = (start: Temporal.Instant, end: Temporal.Instant) =>
  Math.round(end.since(start).total("seconds"));

/**
 * The caller's runs, filtered by state and searched by model or chat in the
 * server, newest first by default. One read covers the newest `RUN_WINDOW` runs
 * (the block lists by chat or by caller, not by state), so the counts are exact
 * until the window fills.
 */
export async function getRunPage(query: OpsListQuery): Promise<RunPage> {
  const { supabase } = await bsbCore.context();

  const runs = await aiRuns(supabase).list({ limit: RUN_WINDOW }).orThrow();

  // SAFETY: STATES lists every AiRunState, so every key is present.
  const counts = Object.fromEntries(
    STATES.map((state) => [
      state,
      runs.filter((run) => run.status === state).length,
    ]),
  ) as Record<AiRunState, number>;

  const needle = query.q.toLowerCase();

  const matching = runs
    .filter((run) => query.filter === null || run.status === query.filter)
    .filter(
      (run) =>
        needle === "" ||
        (run.model ?? "").toLowerCase().includes(needle) ||
        run.chatId.startsWith(needle) ||
        run.id.startsWith(needle),
    );

  const sorted =
    query.sort === "oldest"
      ? matching.toSorted((a, b) =>
          a.startedAt.toString().localeCompare(b.startedAt.toString()),
        )
      : query.sort === "cost"
        ? matching.toSorted(
            (a, b) => (b.costMicroUsd ?? 0) - (a.costMicroUsd ?? 0),
          )
        : matching;

  const start = Number(query.cursor ?? 0);

  return {
    items: sorted
      .slice(start, start + PAGE_SIZE)
      .map((run) => ({
        id: run.id,
        chatId: run.chatId,
        status: run.status,
        engine: run.engine,
        model: run.model,
        startedAt: run.startedAt.toString(),
        seconds:
          run.endedAt === undefined
            ? undefined
            : secondsBetween(run.startedAt, run.endedAt),
        costMicroUsd: run.costMicroUsd,
        error: run.error,
      })),
    nextCursor:
      start + PAGE_SIZE < sorted.length ? String(start + PAGE_SIZE) : null,
    counts,
    capped: runs.length >= RUN_WINDOW,
  };
}

export interface RunDetail {
  readonly run: RunRow & { readonly usage: string };
  readonly chatTitle: string;
  readonly steps: readonly {
    readonly key: string;
    readonly label: string;
    readonly status: string;
    readonly detail: string;
    readonly seconds: number | undefined;
  }[];
}

/** One run with its steps; `undefined` when it doesn't exist or RLS hides it. */
export async function getRun(id: string): Promise<RunDetail | undefined> {
  const { supabase } = await bsbCore.context();
  const runs = aiRuns(supabase);
  const found = await runs.get(id);

  if (!found.ok) {
    if (found.error.kind === "not_found") {
      return undefined;
    }

    throw new Error(found.error.message);
  }

  const run = found.data;

  const [steps, chat] = await Promise.all([
    runs.steps.list(id, { limit: 100 }).orThrow(),
    aiChat(supabase).chats.get(run.chatId),
  ]);

  return {
    run: {
      id: run.id,
      chatId: run.chatId,
      status: run.status,
      engine: run.engine,
      model: run.model,
      startedAt: run.startedAt.toString(),
      seconds:
        run.endedAt === undefined
          ? undefined
          : secondsBetween(run.startedAt, run.endedAt),
      costMicroUsd: run.costMicroUsd,
      error: run.error,
      usage: JSON.stringify(run.usage),
    },
    chatTitle: chat.ok ? chat.data.title : "",
    steps: steps.map((step) => ({
      key: step.key,
      label: step.label,
      status: step.status,
      detail: JSON.stringify(step.detail),
      seconds:
        step.endedAt === undefined
          ? undefined
          : secondsBetween(step.startedAt, step.endedAt),
    })),
  };
}

export interface PendingApprovalRow {
  readonly approvalId: string;
  readonly chatId: string;
  readonly chatTitle: string;
  readonly tool: string;
  readonly input: string;
  /** ISO 8601. */
  readonly createdAt: string;
}

/** The caller's undecided tool approvals, newest first, filtered by tool. */
export async function getApprovalInbox(query: OpsListQuery): Promise<{
  readonly items: readonly PendingApprovalRow[];
  /** Every tool with a pending approval, whatever the filter. */
  readonly tools: readonly string[];
}> {
  const { supabase } = await bsbCore.context();
  const pending = await aiRuns(supabase).pendingApprovals(100).orThrow();

  const items = pending
    .filter(
      (approval) => query.filter === null || approval.tool === query.filter,
    )
    .filter(
      (approval) =>
        query.q === "" ||
        approval.chatTitle.toLowerCase().includes(query.q.toLowerCase()),
    )
    .map((approval) => ({
      approvalId: approval.approvalId,
      chatId: approval.chatId,
      chatTitle: approval.chatTitle,
      tool: approval.tool,
      input: JSON.stringify(approval.input ?? null),
      createdAt: approval.createdAt.toString(),
    }));

  return {
    items,
    tools: [...new Set(pending.map((approval) => approval.tool))].toSorted(),
  };
}

export interface ToolAccessRow {
  readonly tool: string;
  /** The saved rule, or `undefined` when the tool follows its default. */
  readonly policy: ToolPolicyChoice | undefined;
  readonly agents: readonly string[];
}

export type ToolAccessRead =
  | { readonly ok: true; readonly rows: readonly ToolAccessRow[] }
  | { readonly ok: false; readonly error: DbError };

/**
 * Every tool the assistant or an agent can call with its rule for the active
 * organization (`ai_chat.manage` saves them).
 */
export async function getToolAccess(): Promise<ToolAccessRead> {
  const [session, { supabase }] = await Promise.all([
    getSession(),
    bsbCore.context(),
  ]);

  const organizationId = tenantOf(session);

  if (!organizationId) {
    return { ok: true, rows: [] };
  }

  const [policies, agents] = await Promise.all([
    aiChat(supabase).approvals.policies(organizationId),
    agentsBlock(supabase).list({ organizationId, limit: 100 }),
  ]);

  if (!policies.ok) {
    return { ok: false, error: policies.error };
  }

  const byTool = new Map<string, string[]>();

  for (const agent of agents.ok ? agents.data : []) {
    for (const tool of agent.tools) {
      byTool.set(tool, [...(byTool.get(tool) ?? []), agent.name]);
    }
  }

  const tools = new Set<string>([
    ...BUILT_IN_TOOLS,
    ...Object.keys(policies.data),
    ...byTool.keys(),
  ]);

  return {
    ok: true,
    rows: [...tools]
      .toSorted()
      .map((tool) => ({
        tool,
        policy: policies.data[tool],
        agents: byTool.get(tool) ?? [],
      })),
  };
}

export interface MemoryFileRow {
  readonly id: string;
  readonly path: string;
  readonly content: string;
  readonly version: number;
  /** ISO 8601. */
  readonly updatedAt: string;
}

export interface MemoryFactRow {
  readonly id: string;
  readonly content: string;
  readonly category: string | undefined;
  readonly confidence: number | undefined;
  readonly uses: number;
}

/** The organization's core memory files and archival facts for the manager. */
export async function getMemory(): Promise<{
  readonly files: readonly MemoryFileRow[];
  readonly facts: readonly MemoryFactRow[];
}> {
  const [session, { supabase }] = await Promise.all([
    getSession(),
    bsbCore.context(),
  ]);

  const organizationId = tenantOf(session);

  if (!organizationId) {
    return { files: [], facts: [] };
  }

  const memories = memory(supabase);

  const [files, facts] = await Promise.all([
    memories.core.list({ organizationId }).orThrow(),
    memories.archival.list({ organizationId, limit: 100 }).orThrow(),
  ]);

  return {
    files: files.map((file) => ({
      id: file.id,
      path: file.path ?? "",
      content: file.content,
      version: file.version,
      updatedAt: file.updatedAt.toString(),
    })),
    facts: facts.map((fact) => ({
      id: fact.id,
      content: fact.content,
      category: fact.category,
      confidence: fact.confidence,
      uses: fact.useCount,
    })),
  };
}
