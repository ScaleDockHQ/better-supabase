import "server-only";
import { tenantOf } from "better-supabase/next";

import { aiChat, aiRuns } from "@/features/assistant/assistant-server";
import { getDecisionPage } from "@/features/guardrails/guardrails-queries";
import { getSession } from "@/features/user/user-queries";
import { bsbCore } from "@/lib/supabase/server-core";

import type { PendingApprovalRow, RunRow } from "./agents-queries";

const CHAT_WINDOW = 100;

export interface AgentActivity {
  readonly runs: readonly RunRow[];
  readonly approvals: readonly PendingApprovalRow[];
  readonly decisions: readonly {
    readonly id: string;
    readonly stage: string;
    readonly decision: string;
    readonly reasons: string;
    readonly createdAt: string;
  }[];
}

/**
 * What one agent did for the caller: the runs of the chats that name it, the
 * undecided tool approvals of those chats and the guardrail decisions logged
 * for its slug. Chats carry `agent_id`, so the agent's slug links all three.
 */
export async function getAgentActivity(slug: string): Promise<AgentActivity> {
  const [session, { supabase }] = await Promise.all([
    getSession(),
    bsbCore.context(),
  ]);

  const organizationId = tenantOf(session);

  if (!organizationId) {
    return { runs: [], approvals: [], decisions: [] };
  }

  const { items: chats } = await aiChat(supabase)
    // oxlint-disable-next-line typescript/no-deprecated -- the chat list pages by cursor; one window is enough to find an agent's chats
    .chats.list({ organizationId, limit: CHAT_WINDOW })
    .orThrow();

  const own = chats.filter((chat) => chat.agentId === slug);
  const titles = new Map(own.map((chat) => [chat.id, chat.title]));

  const [runLists, pending, log] = await Promise.all([
    Promise.all(
      own.map((chat) =>
        aiRuns(supabase).list({ chatId: chat.id, limit: 20 }).orThrow(),
      ),
    ),
    aiRuns(supabase).pendingApprovals(100).orThrow(),
    getDecisionPage({ q: slug, filter: null, sort: "newest", cursor: null }),
  ]);

  return {
    runs: runLists
      .flat()
      .toSorted((a, b) =>
        b.startedAt.toString().localeCompare(a.startedAt.toString()),
      )
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
            : Math.round(run.endedAt.since(run.startedAt).total("seconds")),
        costMicroUsd: run.costMicroUsd,
        error: run.error,
      })),
    approvals: pending
      .filter((approval) => titles.has(approval.chatId))
      .map((approval) => ({
        approvalId: approval.approvalId,
        chatId: approval.chatId,
        chatTitle: approval.chatTitle,
        tool: approval.tool,
        input: JSON.stringify(approval.input ?? null),
        createdAt: approval.createdAt.toString(),
      })),
    decisions: log.items
      .filter((row) => row.agent === slug)
      .map((row) => ({
        id: row.id,
        stage: row.stage,
        decision: row.decision,
        reasons: row.reasons,
        createdAt: row.createdAt,
      })),
  };
}
