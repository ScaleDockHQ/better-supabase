/**
 * Syncs the workflow builder's step library, then, in `next dev`, starts the
 * Supabase World's poller, which delivers queued workflow steps to this
 * server. Deployments use pg_net delivery (`WORKFLOW_DELIVERY=pg_net`) or
 * their own worker instead.
 */
export async function register(): Promise<void> {
  if (process.env["NEXT_RUNTIME"] !== "nodejs") return;
  // Loaded here, not at the top: the edge build of this file must not pull
  // in `pg` or the server client.
  const { syncStepLibrary } =
    await import("./features/workflows/builder/sync-steps");
  await syncStepLibrary();
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
