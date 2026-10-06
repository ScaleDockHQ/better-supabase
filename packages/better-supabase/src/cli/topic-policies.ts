import { resolve } from "node:path";

import type { ResolvedConfig } from "../config/index.ts";

import { importModule } from "./config.ts";

/** What the writer reads from a `defineTopic` result. */
interface TopicLike {
  readonly template: string;
  sql(): string;
}

const isTopic = (value: unknown): value is TopicLike =>
  typeof value === "object" &&
  value !== null &&
  "template" in value &&
  typeof value.template === "string" &&
  "sql" in value &&
  typeof value.sql === "function" &&
  "triggerSql" in value;

/** The file `realtime.policies` writes, or `undefined` when it isn't set. */
export async function topicPolicyFile(
  config: ResolvedConfig,
): Promise<{ readonly path: string; readonly contents: string } | undefined> {
  const policies = config.realtime.policies;
  if (policies === undefined) return undefined;
  const topics: TopicLike[] = [];
  for (const entry of policies.from) {
    const loaded = await importModule(resolve(config.root, entry));
    const found = Object.values(loaded).filter(isTopic);
    if (found.length === 0) {
      throw new Error(`${entry} exports no topic (defineTopic)`);
    }
    for (const topic of found) if (!topics.includes(topic)) topics.push(topic);
  }
  topics.sort((a, b) =>
    a.template < b.template ? -1 : a.template > b.template ? 1 : 0,
  );
  const header = [
    "-- better-supabase: realtime topic policies",
    `-- Written by \`better-supabase sql sync\` from ${policies.from.join(", ")}; edit the topics, not this file.`,
  ].join("\n");
  return {
    path: policies.output,
    contents: `${header}\n\n${topics.map((topic) => topic.sql()).join("\n")}`,
  };
}
