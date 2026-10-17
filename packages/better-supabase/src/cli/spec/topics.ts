import type { ApiModel, SpecDiagnostic } from "../../spec/index.ts";
import type { TopicExport } from "../topics.ts";

/**
 * An `asyncapi-topic-undocumented` warning for each topic in
 * `realtime.policies.from` that no channel of the model has as its address.
 */
export function undocumentedTopics(
  model: ApiModel,
  topics: readonly TopicExport[],
): SpecDiagnostic[] {
  const addresses = new Set(model.channels.map((channel) => channel.address));

  return topics
    .filter(({ topic }) => !addresses.has(topic.template))
    .map(({ entry, exportName, topic }) => ({
      code: "asyncapi-topic-undocumented",
      severity: "warning",
      message: `Topic ${topic.template} (\`${exportName}\` in ${entry}) has no channel. Pass it to defineApi with \`events: { topics: topicsFrom(topics) }\`.`,
    }));
}
