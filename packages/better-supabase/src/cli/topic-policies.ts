import type { ResolvedConfig } from "../config/index.ts";
import type { BlockSqlTopic } from "../sql/index.ts";
import type { LoadedTopic, LoadedTriggerOptions } from "./topics.ts";

import { CliError } from "./core/errors.ts";
import { loadTopics } from "./topics.ts";

const literalParts = (template: string): string =>
  template.replaceAll(/\{[^}]+\}/g, "{}");

const owns = (owned: string, template: string): boolean =>
  owned.endsWith("*")
    ? template.startsWith(owned.slice(0, -1))
    : literalParts(owned) === literalParts(template);

const receivesOnly = (sql: string): boolean =>
  !sql.includes(" for insert ") && !sql.includes("'presence'");

function triggerStatement(
  topic: LoadedTopic,
  table: string,
  options: LoadedTriggerOptions,
  index: number,
): string {
  try {
    return topic.trigger(table, options);
  } catch (error) {
    if (error instanceof TypeError) {
      throw new CliError(
        "config_invalid",
        `database.realtime.triggers[${String(index)}]: ${error.message}`,
      );
    }

    throw error;
  }
}

/** The file `realtime.policies` writes, or `undefined` when it isn't set. */
export async function topicPolicyFile(
  config: ResolvedConfig,
  owned: readonly BlockSqlTopic[] = [],
): Promise<{ readonly path: string; readonly contents: string } | undefined> {
  const policies = config.realtime.policies;
  const triggers = config.realtime.triggers;

  if (policies === undefined) {
    if (triggers.length > 0) {
      throw new CliError(
        "config_invalid",
        "database.realtime.triggers needs database.realtime.policies: the triggers go to its output, for topics its from files export",
      );
    }

    return undefined;
  }

  const topics = (await loadTopics(config.root, policies.from)).map(
    (each) => each.topic,
  );

  const functions = config.authorization?.functions;

  const sqlOf = (topic: LoadedTopic): string =>
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

  const topicFor = (template: string, where: string): LoadedTopic => {
    const topic = topics.find((candidate) => candidate.template === template);

    if (topic === undefined) {
      throw new CliError(
        "config_invalid",
        `${where}: no topic "${template}" in ${policies.from.join(", ")}`,
      );
    }

    return topic;
  };

  const triggerSql = triggers.map(
    ({ topic: template, table, topics: extra, ...options }, index) => {
      const topic = topicFor(template, "database.realtime.triggers");

      const resolved = {
        ...options,
        ...(extra === undefined
          ? {}
          : {
              topics: extra.map((each) => ({
                topic: topicFor(
                  each.topic,
                  `database.realtime.triggers[${String(index)}].topics`,
                ),
                ...(each.values === undefined ? {} : { values: each.values }),
              })),
            }),
      };

      const statement = triggerStatement(topic, table, resolved, index);

      if (
        statement.includes("better_supabase.broadcast_topic(") &&
        !config.blockNames.includes("realtime-tables")
      ) {
        throw new CliError(
          "config_invalid",
          `database.realtime.triggers: the trigger for ${template} on ${table} calls better_supabase.broadcast_topic(): add realtime-tables to blocks`,
        );
      }

      return statement;
    },
  );

  const header = [
    "-- better-supabase: realtime topic policies",
    `-- Written by \`better-supabase upgrade\` from ${policies.from.join(", ")}; edit the topics, not this file.`,
    ...skipped,
  ].join("\n");

  return {
    path: policies.output,
    contents: `${header}\n\n${[...written.map(sqlOf), ...triggerSql].join("\n")}`,
  };
}
