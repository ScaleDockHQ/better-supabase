import {
  createBuilder,
  rpcTransport,
} from "better-supabase/blocks/workflow-builder";

import { bs } from "@/lib/supabase/server";

import { stepLibrary } from "./step-library";

/**
 * Writes the step library, so the canvas offers the steps this deployment
 * has and publishing accepts graphs that use them. A database that is down
 * at start-up leaves the previous library in place.
 */
export async function syncStepLibrary(): Promise<void> {
  const builder = createBuilder({
    transport: rpcTransport(bs.admin().$client, { schema: "api" }),
    schema: "api",
    steps: stepLibrary,
  });
  const synced = await builder.steps.sync();
  if (!synced.ok) {
    console.warn(`Step library not synced: ${synced.error.message}`);
  }
}
