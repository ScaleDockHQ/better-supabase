import type { RpcClient } from "better-supabase/blocks/organizations";

import {
  createWorkflowEditor,
  rpcTransport,
} from "better-supabase/blocks/workflow-editor";
import { vaultCredentials } from "better-supabase/credentials";
import {
  compileGraph,
  graphStarter,
} from "better-supabase/workflow-sdk/builder";
import "server-only";

import { blockConfig } from "@/lib/supabase/blocks.config";
import { bsbCore } from "@/lib/supabase/server-core";

import { graphSteps, requestGraphApproval } from "./graph-steps";
import { allNodeSteps, graphExecutor } from "./graph-workflow";
import { nodeKinds } from "./node-kinds";
import { stepLibrary } from "./step-library";

/** The API schema `gen` wrote for the workflow-editor block. */
const API_SCHEMA = blockConfig["workflow-editor"].api;

const start = graphStarter({
  steps: graphSteps,
  nodeKinds,
  nodes: allNodeSteps,
  executor: graphExecutor,
  executorRunsTests: true,
  approval: requestGraphApproval,
});

/**
 * The builder as the caller of `supabase`: RLS and the module's permissions
 * apply to every call. Webhooks, events, secrets and the step library go
 * through the service role.
 */
export function builderFor(supabase: RpcClient) {
  const service = rpcTransport(bsbCore.admin().$client, { schema: API_SCHEMA });

  return createWorkflowEditor({
    transport: rpcTransport(supabase, { schema: API_SCHEMA }),
    service,
    schema: API_SCHEMA,
    steps: stepLibrary,
    nodes: nodeKinds,
    compile: (graph) => compileGraph(graph, { nodes: nodeKinds }),
    start,
    credentials: vaultCredentials({ transport: service, schema: API_SCHEMA }),
  });
}

/** The builder for calls no user makes: webhook deliveries and the step sync. */
export function serviceBuilder() {
  return builderFor(bsbCore.admin().$client);
}

/** One definition by id, or `undefined` when the caller cannot see it. */
export async function findDefinition(supabase: RpcClient, id: string) {
  const found = await builderFor(supabase).definitions.getDefinition(id);

  if (found.ok) {
    return found.data;
  }

  if (found.error.code === "not_found") {
    return;
  }

  throw new Error(found.error.message);
}
