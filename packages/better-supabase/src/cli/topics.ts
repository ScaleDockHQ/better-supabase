import { resolve } from "node:path";

import type {
  AuthorizationFunctions,
  TopicTriggerConfig,
} from "../config/index.ts";
import type { TopicInput } from "../spec/index.ts";

import { CliError } from "./errors.ts";
import { importFresh } from "./fresh-import.ts";

/** A `defineTopic` result, as `sql sync` and `spec` read it. */
export interface LoadedTopic extends TopicInput {
  sql(options?: { readonly functions?: AuthorizationFunctions }): string;
  trigger(
    table: string,
    options?: Omit<TopicTriggerConfig, "topic" | "table">,
  ): string;
}

export interface TopicExport {
  /** The module it came from, as written in `realtime.policies.from`. */
  readonly entry: string;
  /** The first export name it was found under. */
  readonly exportName: string;
  readonly topic: LoadedTopic;
}

const isLoadedTopic = (value: unknown): value is LoadedTopic =>
  typeof value === "object" &&
  value !== null &&
  "template" in value &&
  typeof value.template === "string" &&
  "sql" in value &&
  typeof value.sql === "function" &&
  "trigger" in value &&
  typeof value.trigger === "function" &&
  "subscribe" in value &&
  typeof value.subscribe === "function";

/**
 * The topics the `from` modules export (`realtime.policies.from`), loaded
 * fresh, each once, sorted by template. Throws for a module that exports
 * no topic.
 */
export async function loadTopics(
  root: string,
  from: readonly string[],
): Promise<readonly TopicExport[]> {
  const found: TopicExport[] = [];

  for (const entry of from) {
    const loaded = await importFresh(resolve(root, entry));
    let count = 0;

    for (const [exportName, value] of Object.entries(loaded)) {
      if (!isLoadedTopic(value)) {
        continue;
      }

      count += 1;

      if (!found.some((each) => each.topic === value)) {
        found.push({ entry, exportName, topic: value });
      }
    }

    if (count === 0) {
      throw new CliError(
        "invalid_input",
        `${entry} exports no topic (defineTopic)`,
      );
    }
  }

  return found.toSorted((a, b) =>
    a.topic.template < b.topic.template
      ? -1
      : a.topic.template > b.topic.template
        ? 1
        : 0,
  );
}
