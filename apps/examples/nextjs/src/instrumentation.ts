/**
 * Syncs the workflow builder's step library and the rule fields, then, in `next
 * dev`, seeds each new organization with demo rows and starts the Supabase
 * World's poller, which delivers queued workflow steps to this server.
 * Deployments use pg_net delivery (`WORKFLOW_DELIVERY=pg_net`) or their own
 * worker instead.
 */
export async function register(): Promise<void> {
  if (process.env["NEXT_RUNTIME"] !== "nodejs") {
    return;
  }

  // Loaded here, not at the top: the edge build of this file must not pull
  // in `pg` or the server client.
  const [{ syncStepLibrary }, { syncRuleFields }] = await Promise.all([
    import("./features/workflows/builder/sync-steps"),
    import("./features/rules/sync-rule-fields"),
  ]);

  await Promise.all([syncStepLibrary(), syncRuleFields()]);

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

  const { getWorld } = await import("workflow/runtime");
  const world = await getWorld();
  await world.start?.();
}
