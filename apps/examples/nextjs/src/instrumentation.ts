/**
 * Meters AI SDK calls on the usage block, syncs the workflow builder's step
 * library and the rule fields, logs failed workflow runs through the Workflow
 * SDK's lifecycle hooks, then, in `next dev`, seeds each new organization with
 * demo rows and starts the Supabase World's poller, which delivers queued
 * workflow steps to this server. Deployments use pg_net delivery
 * (`WORKFLOW_DELIVERY=pg_net`) or their own worker instead.
 */
let unregisterHooks: (() => void) | undefined;

export async function register(): Promise<void> {
  if (process.env["NEXT_RUNTIME"] !== "nodejs") {
    return;
  }

  // Loaded here, not at the top: the edge build of this file must not pull
  // in `pg` or the server client.
  const [{ syncStepLibrary }, { syncRuleFields }, { registerAiTelemetry }] =
    await Promise.all([
      import("./features/workflows/builder/sync-steps"),
      import("./features/rules/sync-rule-fields"),
      import("./features/assistant/ai-telemetry"),
    ]);

  registerAiTelemetry();
  await Promise.all([syncStepLibrary(), syncRuleFields()]);

  const { registerLifecycleHooks } = await import("workflow/api");
  unregisterHooks?.();
  unregisterHooks = registerLifecycleHooks({
    onRunFailed: ({ workflowName, run, error }) => {
      console.error(
        `Workflow run ${run.runId} (${workflowName}) failed: ${error.message}`,
      );
    },
  });

  if (process.env.NODE_ENV === "development") {
    const { seedNewTenants } =
      await import("./features/onboarding/seed-new-tenants");

    seedNewTenants();
  }

  if (
    process.env.NODE_ENV !== "development" ||
    process.env["WORKFLOW_TARGET_WORLD"] === undefined
  ) {
    return;
  }

  // Only `next dev` polls: a deployment delivers through pg_net or a worker,
  // and a poller in every serverless instance would race them.
  const { getWorld } = await import("workflow/runtime");
  const world = await getWorld();
  await world.start?.();
}
