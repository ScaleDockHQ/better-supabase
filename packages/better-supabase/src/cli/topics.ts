import { resolve } from "node:path";

import type {
  AuthorizationFunctions,
  TopicTriggerConfig,
  TopicTriggerValueConfig,
} from "../config/index.ts";
import type { TopicInput } from "../spec/index.ts";

import { CliError } from "./core/errors.ts";
import { importFresh } from "./fresh-import.ts";

export interface LoadedTriggerOptions extends Omit<
  TopicTriggerConfig,
  "topic" | "table" | "topics"
> {
  readonly topics?: readonly {
    readonly topic: {
      readonly template: string;
      readonly params: readonly string[];
      readonly private: boolean;
    };
    readonly values?: Readonly<Record<string, TopicTriggerValueConfig>>;
  }[];
}

/** A `defineTopic` result, as `sql sync` and `spec` read it. */
export interface LoadedTopic extends TopicInput {
  readonly params: readonly string[];
  readonly private: boolean;
  sql(options?: { readonly functions?: AuthorizationFunctions }): string;
  trigger(table: string, options?: LoadedTriggerOptions): string;
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
  "params" in value &&
  Array.isArray(value.params) &&
  "private" in value &&
  typeof value.private === "boolean" &&
  "sql" in value &&
  typeof value.sql === "function" &&
  "trigger" in value &&
  typeof value.trigger === "function" &&
  "subscribe" in value &&
  typeof value.subscribe === "function";

/**
 * The topics the `from` modules export (`realtime.policies.from`), loaded
 * fresh, each once, sorted by template. Throws for a module that exports no
 * topic.
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
