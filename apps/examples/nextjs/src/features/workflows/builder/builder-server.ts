import { type RpcClient } from "better-supabase/blocks/organizations";
import {
  createBuilder,
  rpcTransport,
} from "better-supabase/blocks/workflow-builder";
import { vaultCredentials } from "better-supabase/credentials";
import {
  compileGraph,
  graphStarter,
} from "better-supabase/workflow-sdk/builder";
import "server-only";

import { bs } from "@/lib/supabase/server";

import { graphSteps } from "./graph-steps";
import { graphExecutor } from "./graph-workflow";
import { stepLibrary } from "./step-library";

const API_SCHEMA = "api";

const start = graphStarter({ steps: graphSteps, executor: graphExecutor });

/**
 * The builder as the caller of `supabase`: RLS and the module's permissions
 * apply to every call. Webhooks, events, secrets and the step library go
 * through the service role.
 */
export function builderFor(supabase: RpcClient) {
  const service = rpcTransport(bs.admin().$client, { schema: API_SCHEMA });
  return createBuilder({
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
  return builderFor(bs.admin().$client);
}
