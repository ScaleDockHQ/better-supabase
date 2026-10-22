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

import { blockConfig } from "@/lib/supabase/blocks.generated";
import { bsb } from "@/lib/supabase/server";

import { graphSteps } from "./graph-steps";
import { graphExecutor } from "./graph-workflow";
import { stepLibrary } from "./step-library";

/** The API schema `gen` wrote for the workflow-editor block. */
const API_SCHEMA = blockConfig["workflow-editor"].api;

const start = graphStarter({ steps: graphSteps, executor: graphExecutor });

/**
 * The builder as the caller of `supabase`: RLS and the module's permissions
 * apply to every call. Webhooks, events, secrets and the step library go
 * through the service role.
 */
export function builderFor(supabase: RpcClient) {
  const service = rpcTransport(bsb.admin().$client, { schema: API_SCHEMA });

  return createWorkflowEditor({
    transport: rpcTransport(supabase, { schema: API_SCHEMA }),
    service,
    schema: API_SCHEMA,
    steps: stepLibrary,
    compile: compileGraph,
    start,
    credentials: vaultCredentials({ transport: service, schema: API_SCHEMA }),
  });
}

/** The builder for calls no user makes: webhook deliveries and the step sync. */
export function serviceBuilder() {
  return builderFor(bsb.admin().$client);
}
