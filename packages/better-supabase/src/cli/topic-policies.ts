import { resolve } from "node:path";

import type {
  AuthorizationFunctions,
  ResolvedConfig,
  TopicTriggerConfig,
} from "../config/index.ts";
import type { ModuleTopic } from "../sql/index.ts";

import { importFresh } from "./fresh-import.ts";

/** What the writer reads from a `defineTopic` result. */
interface TopicLike {
  readonly template: string;
  sql(options?: { readonly functions?: AuthorizationFunctions }): string;
  trigger(
    table: string,
    options?: Omit<TopicTriggerConfig, "topic" | "table">,
  ): string;
}

const isTopic = (value: unknown): value is TopicLike =>
  typeof value === "object" &&
  value !== null &&
  "template" in value &&
  typeof value.template === "string" &&
  "sql" in value &&
  typeof value.sql === "function" &&
  "trigger" in value &&
  typeof value.trigger === "function";

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
  const triggers = config.realtime.triggers;

  if (policies === undefined) {
    if (triggers.length > 0) {
      throw new Error(
        "realtime.triggers needs realtime.policies: the triggers go to its output, for topics its from files export",
      );
    }

    return undefined;
  }

  if (triggers.length > 0 && !config.blockNames.includes("realtime-tables")) {
    throw new Error(
      "realtime.triggers call better_supabase.broadcast_topic(): add realtime-tables to blocks",
    );
  }

  const topics: TopicLike[] = [];

  for (const entry of policies.from) {
    const loaded = await importFresh(resolve(config.root, entry));
    const found = Object.values(loaded).filter(isTopic);

    if (found.length === 0) {
      throw new Error(`${entry} exports no topic (defineTopic)`);
    }

    for (const topic of found) {
      if (!topics.includes(topic)) {
        topics.push(topic);
      }
    }
  }

  topics.sort((a, b) =>
    a.template < b.template ? -1 : a.template > b.template ? 1 : 0,
  );
  const functions = config.authorization?.functions;

  const sqlOf = (topic: TopicLike): string =>
    topic.sql(functions === undefined ? undefined : { functions });

  const skipped: string[] = [];

  const written = topics.filter((topic) => {
    const owner = owned.find((entry) => owns(entry.topic, topic.template));

    if (owner === undefined || !receivesOnly(sqlOf(topic))) {
      return true;
    }

    skipped.push(
      `-- Skipped topic ${topic.template}: the ${owner.module} module writes its receive policy.`,
    );

    return false;
  });

  const triggerSql = triggers.map(({ topic: template, table, ...options }) => {
    const topic = topics.find((candidate) => candidate.template === template);

    if (topic === undefined) {
      throw new Error(
        `realtime.triggers: no topic "${template}" in ${policies.from.join(", ")}`,
      );
    }

    return topic.trigger(table, options);
  });

  const header = [
    "-- better-supabase: realtime topic policies",
    `-- Written by \`better-supabase sql sync\` from ${policies.from.join(", ")}; edit the topics, not this file.`,
    ...skipped,
  ].join("\n");

  return {
    path: policies.output,
    contents: `${header}\n\n${[...written.map(sqlOf), ...triggerSql].join("\n")}`,
  };
}
