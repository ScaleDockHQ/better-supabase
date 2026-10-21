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
import { blocks } from "@/lib/blocks";
import { refreshCaller } from "@/lib/refresh-caller";
import { blockConfig } from "@/lib/supabase/blocks.generated";
import { bs } from "@/lib/supabase/server";

const SCHEMA = blockConfig["data-lifecycle"].api;
const ID = v.pipe(v.string(), v.uuid());

/**
 * Writes the export's files right away with the service role. An app with a
 * queue runs `exporter.job` from a worker instead.
 */
async function runExport(exportId: string): Promise<void> {
  const service = bs.admin().$client;

  await createDataExporter({
    transport: rpcTransport(service, { schema: SCHEMA }),
    storage: service.storage,
    schema: SCHEMA,
  }).run(exportId);
}

/** Exports the caller's own data. */
export const requestMyExport = bs.action(
  {},
  async (_input, { supabase, auth }) => {
    const requested = await blocks(supabase).dataLifecycle.requestExport();

    if (!requested.ok) {
      return requested;
    }

    await runExport(requested.data.id);
    refreshCaller(auth);

    return ok(requested.data.id);
  },
);

/** Exports the active organization's data (`organization.export`). */
export const requestOrganizationExport = bs.action(
  {
    requireTenant: true,
    authorize: (session) => can(session, "organization.export"),
  },
  async (_input, { tenant, supabase, auth }) => {
    const requested = await blocks(supabase).dataLifecycle.requestExport({
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
export const downloadExport = bs.action(
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
export const requestOrganizationDeletion = bs.action(
  {
    requireTenant: true,
    authorize: (session) => can(session, "organization.delete"),
  },
  async (_input, { tenant, supabase, auth }) => {
    const requested =
      await blocks(supabase).dataLifecycle.requestOrganizationDeletion(tenant);

    if (!requested.ok) {
      return requested;
    }

    refreshCaller(auth);

    return ok(requested.data.purgeAfter.toString());
  },
);

/** Cancels the pending purge and enables the organization again. */
export const cancelOrganizationDeletion = bs.action(
  { requireTenant: true },
  async (_input, { tenant, supabase, auth }) => {
    const cancelled =
      await blocks(supabase).dataLifecycle.cancelOrganizationDeletion(tenant);

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
