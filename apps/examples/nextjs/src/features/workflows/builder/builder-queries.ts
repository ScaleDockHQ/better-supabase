import type {
  WorkflowGraph,
  WorkflowStepInfo,
  WorkflowTrigger,
  WorkflowTriggerKind,
} from "better-supabase/blocks/workflow-builder";

import { tenantOf } from "better-supabase/next";
import "server-only";

import { bs } from "@/lib/supabase/server";

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
  readonly triggers: readonly TriggerRow[];
  readonly credentials: readonly CredentialRow[];
}

const EMPTY_GRAPH: WorkflowGraph = { nodes: [], edges: [] };

/** The active organization's workflow definitions. */
export async function getDefinitions(): Promise<readonly DefinitionRow[]> {
  "use cache: private";
  const { session, supabase } = await bs.cached();
  const tenant = tenantOf(session);
  if (!tenant) return [];
  const definitions = await builderFor(supabase)
    .definitions.list(tenant)
    .orThrow();
  return definitions.map((definition) => ({
    id: definition.id,
    name: definition.name,
    slug: definition.slug,
    published: definition.published ?? null,
    draft: definition.draft ?? false,
    updatedAt: definition.updatedAt.toString(),
  }));
}

/** Everything the canvas needs for one definition; `null` when it isn't the caller's to read. */
export async function getBuilderDetail(
  id: string,
): Promise<BuilderDetail | null> {
  "use cache: private";
  const { session, supabase } = await bs.cached();
  const tenant = tenantOf(session);
  if (!tenant) return null;
  const builder = builderFor(supabase);
  const definition = await builder.definitions.get(id).orThrow();
  if (definition?.tenant !== tenant) return null;
  const [versions, steps, triggers, credentials] = await Promise.all([
    builder.versions.list(id).orThrow(),
    builder.steps.list().orThrow(),
    builder.triggers.list(id).orThrow(),
    builder.credentials.list(tenant).orThrow(),
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
