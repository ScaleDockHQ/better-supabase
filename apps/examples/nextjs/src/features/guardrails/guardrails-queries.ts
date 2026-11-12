import "server-only";
import type {
  GuardrailDecision,
  GuardrailPolicyConfig,
  GuardrailStage,
} from "better-supabase/blocks/ai-guardrails";

import type { OpsListQuery } from "@/components/ops-list/ops-list-params";

import { agentsBlock } from "@/features/agents/agents-server";
import { ASSISTANT_AGENT, opsTenant } from "@/features/assistant/assistant-ops";
import { bsbCore } from "@/lib/supabase/server-core";

import { guardrailsBlock } from "./guardrails-server";

const PAGE_SIZE = 25;

const STAGES: readonly GuardrailStage[] = ["input", "output"];

export interface PolicyCard {
  readonly id: string;
  /** The agent the card edits: `*`, `assistant` or an agent's slug. */
  readonly agent: string;
  readonly stage: GuardrailStage;
  readonly title: string;
  readonly config: GuardrailPolicyConfig | undefined;
  readonly enabled: boolean;
  /** The agent whose policy applies when this card has none of its own. */
  readonly inheritedFrom: string | undefined;
}

/** Every agent the organization can attach a policy to, with `*` for all. */
async function targets(
  organizationId: string,
): Promise<readonly { agent: string; title: string }[]> {
  const { supabase } = await bsbCore.context();

  const agents = await agentsBlock(supabase).list({
    organizationId,
    filter: "mine",
    limit: 100,
  });

  return [
    { agent: "*", title: "Every agent" },
    { agent: ASSISTANT_AGENT, title: "Assistant" },
    ...(agents.ok
      ? agents.data.map((agent) => ({ agent: agent.slug, title: agent.name }))
      : []),
  ];
}

/**
 * The effective policy of each agent and stage: its own, the tenant's or the
 * system's.
 */
export async function getPolicyCards(): Promise<readonly PolicyCard[]> {
  const organizationId = await opsTenant("ai_chat.manage");

  if (organizationId === undefined) {
    return [];
  }

  const guardrails = guardrailsBlock();

  return Promise.all(
    (await targets(organizationId)).flatMap((target) =>
      STAGES.map(async (stage): Promise<PolicyCard> => {
        const policy = await guardrails.policies
          .get({ agent: target.agent, stage, organizationId })
          .orThrow();

        return {
          id: `${target.agent}:${stage}`,
          agent: target.agent,
          stage,
          title: target.title,
          config: policy?.config,
          enabled: policy?.enabled ?? false,
          inheritedFrom:
            policy !== undefined && policy.agent !== target.agent
              ? policy.agent
              : undefined,
        };
      }),
    ),
  );
}

export interface DecisionRow {
  readonly id: string;
  readonly agent: string;
  readonly stage: GuardrailStage;
  readonly decision: GuardrailDecision;
  readonly reasons: string;
  readonly chatId: string | undefined;
  /** ISO 8601. */
  readonly createdAt: string;
}

/**
 * One page of the decision log: filtered by decision, searched by agent or
 * reason.
 */
export async function getDecisionPage(
  query: OpsListQuery,
): Promise<{
  readonly items: readonly DecisionRow[];
  readonly nextCursor: string | null;
}> {
  const organizationId = await opsTenant("ai_chat.manage");

  if (organizationId === undefined) {
    return { items: [], nextCursor: null };
  }

  const decision =
    query.filter === "allow" ||
    query.filter === "redact" ||
    query.filter === "block"
      ? query.filter
      : undefined;

  const entries = await guardrailsBlock()
    .decisions.list({
      organizationId,
      limit: 200,
      ...(decision === undefined ? {} : { decision }),
    })
    .orThrow();

  const needle = query.q.toLowerCase();

  const rows = entries
    .map((entry) => ({
      id: entry.id,
      agent: entry.agent,
      stage: entry.stage,
      decision: entry.decision,
      reasons: entry.reasons.map((reason) => reason.detail).join(", "),
      chatId: entry.chatId,
      createdAt: entry.createdAt.toString(),
    }))
    .filter(
      (row) =>
        needle === "" ||
        row.agent.toLowerCase().includes(needle) ||
        row.reasons.toLowerCase().includes(needle),
    );

  const sorted = query.sort === "oldest" ? rows.toReversed() : rows;

  const start = Number(query.cursor ?? 0);

  return {
    items: sorted.slice(start, start + PAGE_SIZE),
    nextCursor:
      start + PAGE_SIZE < sorted.length ? String(start + PAGE_SIZE) : null,
  };
}
