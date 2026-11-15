import "server-only";
import type { PromptSummary } from "better-supabase/blocks/prompts";

import type { OpsListQuery } from "@/components/ops-list/ops-list-params";

import { agentsBlock } from "@/features/agents/agents-server";
import {
  agentPrompt,
  ASSISTANT_PROMPT,
  opsAccess,
} from "@/features/assistant/assistant-ops";
import { present } from "@/lib/present";
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
 * The names an organization keeps prompts under: the assistant and each agent.
 * They give a name its title; `prompts.list` adds the saved names that no agent
 * owns.
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

/** Every prompt the organization saved, by name, read a page at a time. */
async function savedPrompts(
  prompts: ReturnType<typeof promptsBlock>,
  organizationId: string,
): Promise<ReadonlyMap<string, PromptSummary>> {
  const saved = new Map<string, PromptSummary>();
  let after: readonly string[] | undefined;

  for (let pages = 0; pages < 10; pages += 1) {
    const page = await prompts
      .list({ organizationId, limit: 200, ...present({ after }) })
      .orThrow();

    for (const item of page.items) {
      saved.set(item.name, item);
    }

    if (page.nextCursor === null) {
      break;
    }

    after = page.nextCursor;
  }

  return saved;
}

/**
 * One page of the prompt registry: the assistant and each agent, plus any other
 * saved name. Names are searched, filtered and sorted here.
 */
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

  const saved = await savedPrompts(prompts, organizationId);

  const rows: PromptRow[] = [
    ...subjects.map((subject): PromptRow => {
      const found = saved.get(subject.name);

      return {
        id: subject.name,
        title: subject.title,
        latest: found?.latestVersion,
        production: found?.labels["production"],
        versions: found?.versionCount ?? 0,
        updatedAt: found?.updatedAt?.toString(),
      };
    }),
    ...[...saved.values()]
      .filter(
        (found) =>
          !subjects.some((subject) => subject.name === found.name) &&
          (needle === "" || found.name.includes(needle)),
      )
      .map((found): PromptRow => ({
        id: found.name,
        title: found.name,
        latest: found.latestVersion,
        production: found.labels["production"],
        versions: found.versionCount,
        updatedAt: found.updatedAt?.toString(),
      })),
  ];

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
