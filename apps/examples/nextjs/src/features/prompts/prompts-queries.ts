import "server-only";
import type { OpsListQuery } from "@/components/ops-list/ops-list-params";

import { agentsBlock } from "@/features/agents/agents-server";
import {
  agentPrompt,
  ASSISTANT_PROMPT,
  opsAccess,
} from "@/features/assistant/assistant-ops";
import { bsbCore } from "@/lib/supabase/server-core";

import { promptsBlock } from "./prompts-server";

const PAGE_SIZE = 25;

export interface PromptRow {
  /** The prompt name, which is also the row id. */
  readonly id: string;
  readonly title: string;
  readonly latest: number | undefined;
  readonly production: number | undefined;
  readonly versions: number;
  /** ISO 8601. */
  readonly updatedAt: string | undefined;
}

export interface PromptPage {
  readonly items: readonly PromptRow[];
  readonly nextCursor: string | null;
}

/**
 * The names a tenant keeps prompts under: the assistant and each agent. The
 * block has no list of names (finding EX-312), so they come from the entities
 * that own a prompt.
 */
export async function promptSubjects(
  organizationId: string,
): Promise<readonly { name: string; title: string }[]> {
  const { supabase } = await bsbCore.context();

  const agents = await agentsBlock(supabase).list({
    organizationId,
    filter: "mine",
    limit: 100,
  });

  return [
    { name: ASSISTANT_PROMPT, title: "Assistant" },
    ...(agents.ok
      ? agents.data.map((agent) => ({
          name: agentPrompt(agent.slug),
          title: agent.name,
        }))
      : []),
  ];
}

/** One page of the prompt registry: names searched, filtered and sorted here. */
export async function getPromptPage(query: OpsListQuery): Promise<PromptPage> {
  const access = await opsAccess("ai_chat.manage");
  const organizationId = access.allowed ? access.organizationId : undefined;

  if (organizationId === undefined) {
    return { items: [], nextCursor: null };
  }

  const prompts = promptsBlock(access);
  const needle = query.q.toLowerCase();

  const subjects = (await promptSubjects(organizationId)).filter(
    (subject) =>
      needle === "" ||
      subject.name.includes(needle) ||
      subject.title.toLowerCase().includes(needle),
  );

  const start = Number(query.cursor ?? 0);

  const rows = await Promise.all(
    subjects.map(async (subject): Promise<PromptRow> => {
      const versions = await prompts
        .versions({ name: subject.name, organizationId })
        .orThrow();

      const latest = versions[0];

      return {
        id: subject.name,
        title: subject.title,
        latest: latest?.version,
        production: versions.find((entry) =>
          entry.labels.includes("production"),
        )?.version,
        versions: versions.length,
        updatedAt: latest?.createdAt?.toString(),
      };
    }),
  );

  const filtered = rows.filter((row) =>
    query.filter === "unversioned"
      ? row.versions === 0
      : query.filter === "live"
        ? row.production !== undefined
        : true,
  );

  const sorted =
    query.sort === "updated"
      ? filtered.toSorted((a, b) =>
          (b.updatedAt ?? "").localeCompare(a.updatedAt ?? ""),
        )
      : filtered.toSorted((a, b) => a.title.localeCompare(b.title));

  return {
    items: sorted.slice(start, start + PAGE_SIZE),
    nextCursor:
      start + PAGE_SIZE < sorted.length ? String(start + PAGE_SIZE) : null,
  };
}

export interface PromptVersionRow {
  readonly version: number;
  readonly template: string;
  readonly variables: readonly string[];
  readonly labels: readonly string[];
  /** ISO 8601. */
  readonly createdAt: string | undefined;
}

export interface PromptDetail {
  readonly name: string;
  readonly versions: readonly PromptVersionRow[];
}

/** Every version of one prompt with its labels, newest first. */
export async function getPrompt(
  name: string,
): Promise<PromptDetail | undefined> {
  const access = await opsAccess("ai_chat.manage");
  const organizationId = access.allowed ? access.organizationId : undefined;

  if (organizationId === undefined) {
    return undefined;
  }

  const versions = await promptsBlock(access)
    .versions({ name, organizationId })
    .orThrow();

  return {
    name,
    versions: versions.map((entry) => ({
      version: entry.version,
      template: entry.template,
      variables: entry.variables,
      labels: entry.labels,
      createdAt: entry.createdAt?.toString(),
    })),
  };
}
