import { resolve } from "node:path";

import type { ResolvedConfig } from "../config/index.ts";
import type { ModuleTopic } from "../sql/index.ts";

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

const literalParts = (template: string): string =>
  template.replaceAll(/\{[^}]+\}/g, "{}");

const owns = (owned: string, template: string): boolean =>
  owned.endsWith("*")
    ? template.startsWith(owned.slice(0, -1))
    : literalParts(owned) === literalParts(template);

const receivesOnly = (sql: string): boolean =>
  !sql.includes(" for insert ") && !sql.includes("'presence'");

/** The file `realtime.policies` writes, or `undefined` when it isn't set. */
export async function topicPolicyFile(
  config: ResolvedConfig,
  owned: readonly ModuleTopic[] = [],
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
  const skipped: string[] = [];
  const written = topics.filter((topic) => {
    const owner = owned.find((entry) => owns(entry.topic, topic.template));
    if (owner === undefined || !receivesOnly(topic.sql())) return true;
    skipped.push(
      `-- Skipped topic ${topic.template}: the ${owner.module} module writes its receive policy.`,
    );
    return false;
  });
  const header = [
    "-- better-supabase: realtime topic policies",
    `-- Written by \`better-supabase sql sync\` from ${policies.from.join(", ")}; edit the topics, not this file.`,
    ...skipped,
  ].join("\n");
  return {
    path: policies.output,
    contents: `${header}\n\n${written.map((topic) => topic.sql()).join("\n")}`,
  };
}
