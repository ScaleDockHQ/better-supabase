import "server-only";
import type { RpcClient } from "better-supabase/blocks";

import { DbException, dbError } from "better-supabase";
import { rpcTransport } from "better-supabase/blocks";

import { blocks } from "@/lib/blocks";
import { blockConfig } from "@/lib/supabase/blocks.generated";
import { bs } from "@/lib/supabase/server";

const API_SCHEMA = blockConfig.imports.api;

type ImportStatus = "completed" | "failed";

/**
 * The `runImport` hooks that record a run in the imports block. The caller
 * starts the run; `mark_import_running` and `finish_import` are granted to the
 * service role only, so they run as that role after the action checked
 * `imports.manage`.
 */
export function importRunHooks(
  supabase: RpcClient,
  organizationId: string,
  kind: string,
  mapping: Readonly<Record<string, string>>,
) {
  const service = rpcTransport(bs.admin().$client, { schema: API_SCHEMA });
  let runId: string | undefined;

  const finish = async (
    id: string,
    status: ImportStatus,
    count: number,
    error: string | null,
  ) => {
    try {
      await service.call(API_SCHEMA, "finish_import", {
        id,
        status,
        count,
        error,
      });
    } catch (cause) {
      throw new DbException(
        dbError("unexpected", `Could not finish the import: ${String(cause)}`),
      );
    }
  };

  return {
    organizationId,
    start: async () => {
      const run = await blocks(supabase).imports.start(
        organizationId,
        kind,
        mapping,
      );

      if (!run.ok) {
        throw new DbException(run.error);
      }

      runId = run.data.id;

      return run.data.id;
    },
    running: async (id: string) => {
      await service.call(API_SCHEMA, "mark_import_running", { id });
    },
    finish,
    /** Marks a started run failed after a write threw. */
    fail: async (message: string) => {
      if (runId !== undefined) {
        await finish(runId, "failed", 0, message).catch(() => null);
      }
    },
  };
}
