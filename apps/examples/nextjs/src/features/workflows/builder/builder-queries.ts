import type {
  WorkflowGraph,
  WorkflowNodeKindRow,
  WorkflowStepInfo,
  WorkflowTrigger,
  WorkflowTriggerKind,
} from "better-supabase/blocks/workflow-editor";

import { tenantOf } from "better-supabase/next";
import "server-only";

import { bsbCore } from "@/lib/supabase/server-core";

import { builderFor } from "./builder-server";

/** A definition as plain data, so it crosses the server boundary. */
export interface DefinitionRow {
  readonly id: string;
  readonly name: string;
  readonly slug: string;
  readonly published: number | null;
  readonly draft: boolean;
  readonly updatedAt: string;
}

export interface TriggerRow {
  readonly id: string;
  readonly kind: WorkflowTriggerKind;
  readonly config: WorkflowTrigger["config"];
  readonly enabled: boolean;
}

export interface CredentialRow {
  readonly id: string;
  readonly kind: string;
  readonly name: string;
}

/** A version as plain data; the graph loads on demand. */
export interface VersionRow {
  readonly id: string;
  readonly version: number;
  readonly status: "draft" | "published" | "archived";
  readonly createdAt: string;
  readonly publishedAt: string | null;
}

export interface BuilderDetail {
  readonly tenant: string;
  readonly definition: DefinitionRow;
  /** The open draft's graph, or the published one when no draft is open. */
  readonly graph: WorkflowGraph;
  readonly published: {
    readonly version: number;
    readonly graph: WorkflowGraph;
  } | null;
  readonly steps: readonly WorkflowStepInfo[];
  /** The deployment's own node kinds, which the palette and inspector use. */
  readonly kinds: readonly WorkflowNodeKindRow[];
  readonly versions: readonly VersionRow[];
  /** The tenant's other published definitions, for sub-workflow nodes. */
  readonly definitions: readonly {
    readonly id: string;
    readonly name: string;
  }[];
  readonly triggers: readonly TriggerRow[];
  readonly credentials: readonly CredentialRow[];
}

const EMPTY_GRAPH: WorkflowGraph = { nodes: [], edges: [] };

/**
 * Everything the canvas needs for one definition; `null` when it isn't the
 * caller's to read.
 */
export async function getBuilderDetail(
  id: string,
): Promise<BuilderDetail | null> {
  "use cache: private";
  const { session, supabase } = await bsbCore.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const builder = builderFor(supabase);
  const definition = await builder.definitions.get(id).orThrow();

  if (definition?.tenant !== tenant) {
    return null;
  }

  const [versions, steps, kinds, others, triggers, credentials] =
    await Promise.all([
      builder.versions.list(id, { limit: 50 }).orThrow(),
      builder.steps.list({ limit: 200 }).orThrow(),
      builder.nodeKinds.list().orThrow(),
      builder.definitions.list({ tenant, limit: 100 }).orThrow(),
      builder.triggers.list(id, { limit: 50 }).orThrow(),
      builder.credentials.list(tenant, { limit: 100 }).orThrow(),
    ]);

  const draftId = versions.find((version) => version.status === "draft")?.id;

  const publishedId = versions.find(
    (version) => version.status === "published",
  )?.id;

  const [draft, published] = await Promise.all([
    draftId === undefined ? undefined : builder.versions.get(draftId).orThrow(),
    publishedId === undefined
      ? undefined
      : builder.versions.get(publishedId).orThrow(),
  ]);

  return {
    tenant,
    definition: {
      id: definition.id,
      name: definition.name,
      slug: definition.slug,
      published: published?.version ?? null,
      draft: draft !== undefined,
      updatedAt: definition.updatedAt.toString(),
    },
    graph: draft?.graph ?? published?.graph ?? EMPTY_GRAPH,
    published:
      published === undefined
        ? null
        : { version: published.version, graph: published.graph ?? EMPTY_GRAPH },
    steps,
    kinds,
    versions: versions.map((version) => ({
      id: version.id,
      version: version.version,
      status: version.status,
      createdAt: version.createdAt.toString(),
      publishedAt: version.publishedAt?.toString() ?? null,
    })),
    definitions: others
      .filter((other) => other.id !== id && other.published !== undefined)
      .map((other) => ({ id: other.id, name: other.name })),
    triggers: triggers.map((trigger) => ({
      id: trigger.id,
      kind: trigger.kind,
      config: trigger.config,
      enabled: trigger.enabled,
    })),
    credentials: credentials.map((credential) => ({
      id: credential.id,
      kind: credential.kind,
      name: credential.name,
    })),
  };
}
