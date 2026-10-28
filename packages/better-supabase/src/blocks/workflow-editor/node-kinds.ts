import type { WorkflowNodeKindInfo } from "./graph.ts";

import { isBuiltinNodeKind, NODE_KIND_PATTERN } from "./graph.ts";

/**
 * An app's own node kind. The graph stores its nodes as `{ kind, config }`; the
 * engine runs each one as a step (`GraphRuntime.node`, or graphStarter's
 * `nodes`), and `nodeKinds.sync()` writes it to `workflow_node_kinds` so
 * `publish` accepts it.
 */
export interface WorkflowNodeKindDefinition<
  Kind extends string = string,
> extends WorkflowNodeKindInfo {
  readonly apiVersion: 1;
  readonly kind: Kind;
  readonly title: string;
  readonly description?: string;
  /** The JSON Schema of the node's `config`, for the editor's inspector. */
  readonly configSchema?: Readonly<Record<string, unknown>>;
}

/**
 * Defines an app's own node kind. `kind` is 1 to 63 lowercase letters, digits,
 * `_`, `.` or `-`, starting with a letter, and never a built-in kind. Throws
 * when it isn't.
 *
 * ```ts
 * export const notify = defineNodeKind({
 *   apiVersion: 1,
 *   kind: "notify",
 *   title: "Notify",
 *   validate: (node) =>
 *     typeof node.config?.["channel"] === "string"
 *       ? []
 *       : [`Node ${node.id} names no channel`],
 * });
 * ```
 */
export function defineNodeKind<const Kind extends string>(
  definition: WorkflowNodeKindDefinition<Kind>,
): WorkflowNodeKindDefinition<Kind> {
  const apiVersion: unknown = definition.apiVersion;

  if (apiVersion !== 1) {
    throw new TypeError(
      `workflow-editor: node kind "${definition.kind}" has apiVersion ${String(apiVersion)}; this release supports 1`,
    );
  }

  if (
    isBuiltinNodeKind(definition.kind) ||
    !NODE_KIND_PATTERN.test(definition.kind)
  ) {
    throw new TypeError(
      `workflow-editor: "${definition.kind}" can't be a node kind: use 1 to 63 lowercase letters, digits, "_", "." or "-", starting with a letter, other than a built-in kind`,
    );
  }

  return definition;
}

/** The `sync_workflow_node_kinds` payload: each kind's stored fields by kind. */
export function nodeKindRows(
  kinds: readonly WorkflowNodeKindDefinition[],
): Record<string, Record<string, unknown>> {
  return Object.fromEntries(
    kinds.map((kind) => [
      kind.kind,
      {
        title: kind.title,
        description: kind.description,
        branches: kind.branches === true,
        configSchema: kind.configSchema ?? {},
      },
    ]),
  );
}

/** A node kind as `workflow_node_kinds_list` returns it. */
export interface WorkflowNodeKindRow {
  readonly kind: string;
  readonly title: string;
  readonly description: string | undefined;
  readonly branches: boolean;
  readonly configSchema: Readonly<Record<string, unknown>>;
}
