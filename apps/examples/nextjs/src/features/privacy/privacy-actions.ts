"use server";

import { ok } from "better-supabase";
import {
  createDataExporter,
  createDataLifecycle,
  rpcTransport,
} from "better-supabase/blocks/data-lifecycle";
import { refresh } from "next/cache";
import * as v from "valibot";

import { can } from "@/features/user/user-permissions";
import { refreshCaller } from "@/lib/refresh-caller";
import { blockConfig } from "@/lib/supabase/blocks.generated";
import { bsb } from "@/lib/supabase/server";

const SCHEMA = blockConfig["data-lifecycle"].api;
const ID = v.pipe(v.string(), v.uuid());

/**
 * Writes the export's files right away with the service role. An app with a
 * queue runs `exporter.job` from a worker instead.
 */
async function runExport(exportId: string): Promise<void> {
  const service = bsb.admin().$client;

  await createDataExporter({
    transport: rpcTransport(service, { schema: SCHEMA }),
    storage: service.storage,
    schema: SCHEMA,
  }).run(exportId);
}

/** Exports the caller's own data. */
export const requestMyExport = bsb.action({}, async (_input, { db, auth }) => {
  const requested = await db.dataLifecycle.requestExport();

  if (!requested.ok) {
    return requested;
  }

  await runExport(requested.data.id);
  refreshCaller(auth);

  return ok(requested.data.id);
});

/** Exports the active organization's data (`organization.export`). */
export const requestOrganizationExport = bsb.action(
  {
    requireOrganization: true,
    authorize: (session) => can(session, "organization.export"),
  },
  async (_input, { tenant, db, auth }) => {
    const requested = await db.dataLifecycle.requestExport({
      organizationId: tenant,
    });

    if (!requested.ok) {
      return requested;
    }

    await runExport(requested.data.id);
    refreshCaller(auth);

    return ok(requested.data.id);
  },
);

/** Signed download URLs for a ready export, one per table. */
export const downloadExport = bsb.action(
  { input: v.object({ id: ID }) },
  async ({ id }, { supabase }) => {
    const download = await createDataLifecycle({
      transport: rpcTransport(supabase, { schema: SCHEMA }),
      storage: supabase.storage,
      schema: SCHEMA,
    }).download(id);

    return download.ok ? ok(download.data.files) : download;
  },
);

/**
 * Disables the organization and schedules its purge after the module's grace
 * period (`organization.delete`).
 */
export const requestOrganizationDeletion = bsb.action(
  {
    requireOrganization: true,
    authorize: (session) => can(session, "organization.delete"),
  },
  async (_input, { tenant, db, auth }) => {
    const requested =
      await db.dataLifecycle.requestOrganizationDeletion(tenant);

    if (!requested.ok) {
      return requested;
    }

    refreshCaller(auth);

    return ok(requested.data.purgeAfter.toString());
  },
);

/** Cancels the pending purge and enables the organization again. */
export const cancelOrganizationDeletion = bsb.action(
  { requireOrganization: true },
  async (_input, { tenant, db, auth }) => {
    const cancelled = await db.dataLifecycle.cancelOrganizationDeletion(tenant);

    if (!cancelled.ok) {
      return cancelled;
    }

    refreshCaller(auth);

    return ok(cancelled.data !== undefined);
  },
);

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
export async function refreshPrivacy() {
  refresh();
}
