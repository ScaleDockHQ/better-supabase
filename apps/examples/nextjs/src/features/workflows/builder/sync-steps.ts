import {
  createWorkflowEditor,
  rpcTransport,
} from "better-supabase/blocks/workflow-editor";

import { bsbCore } from "@/lib/supabase/server-core";

import { nodeKinds } from "./node-kinds";
import { stepLibrary } from "./step-library";

/**
 * Writes the step library and the node kind registry, so the canvas offers the
 * steps this deployment has and publishing accepts graphs that use them. A
 * database that is down at start-up leaves the previous library in place.
 */
export async function syncStepLibrary(): Promise<void> {
  const builder = createWorkflowEditor({
    transport: rpcTransport(bsbCore.admin().$client, { schema: "api" }),
    schema: "api",
    steps: stepLibrary,
    nodes: nodeKinds,
  });

  const [synced, kinds] = await Promise.all([
    builder.steps.sync(),
    builder.nodeKinds.sync(),
  ]);

  if (!synced.ok) {
    console.warn(`Step library not synced: ${synced.error.message}`);
  }

  if (!kinds.ok) {
    console.warn(`Node kinds not synced: ${kinds.error.message}`);
  }
}
