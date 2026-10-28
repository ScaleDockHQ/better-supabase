import type { Executor } from "../core/executor.ts";

import { DbException, dbError } from "../core/errors.ts";
import { isRecord } from "../core/guards.ts";

/**
 * One bootstrap wrapper's answer: the session flag, the authz version, the
 * tenant and the data.
 */
export interface BootstrapRow {
  readonly sessionActive: boolean;
  readonly authzVersion: number | null;
  readonly tenant: string | null;
  readonly data: unknown;
}

/** Calls `<schema>.bootstrap_<rpc>(args)` and checks the row it returns. */
export async function runBootstrap(
  executor: Executor,
  schema: string,
  rpc: string,
  args: Readonly<Record<string, unknown>>,
): Promise<BootstrapRow> {
  if (!executor.rpc) {
    throw new DbException(
      dbError(
        "unsupported",
        "bsb.bootstrap() needs an executor that calls functions",
      ),
    );
  }

  const result = await executor.rpc(
    `bootstrap_${rpc}`,
    { args },
    { schema, errorMappers: [] },
  );

  if (!result.ok) {
    throw new DbException(result.error);
  }

  return bootstrapRow(result.data);
}

/** The wrapper's jsonb, checked: a row the wrapper didn't write throws. */
function bootstrapRow(value: unknown): BootstrapRow {
  if (!isRecord(value) || typeof value["session_active"] !== "boolean") {
    throw new DbException(
      dbError("unexpected", "The bootstrap wrapper returned no session_active"),
    );
  }

  const version = value["authz_version"];
  const tenant = value["tenant"];

  return {
    sessionActive: value["session_active"],
    authzVersion:
      typeof version === "number"
        ? version
        : typeof version === "string" && /^\d+$/.test(version)
          ? Number(version)
          : null,
    tenant: typeof tenant === "string" ? tenant : null,
    data: value["data"] ?? null,
  };
}
