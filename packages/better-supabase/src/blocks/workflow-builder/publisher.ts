import type { BlockCall } from "../../core/block-helpers.ts";
import type {
  AutomationHooks,
  AutomationRef,
} from "../../core/contracts/authorization-hooks.ts";
import type { WorkflowVersion } from "./types.ts";

import { type DbError, dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { isRecord, optionalText, recordOf, stringsOf } from "../shared.ts";
import { graphOf } from "./graph.ts";
import { definitionOf } from "./rows.ts";

const forbidden = (
  message: string,
  hint: string,
  permissions?: readonly string[],
): DbError =>
  dbError("forbidden", message, {
    hint,
    ...(permissions === undefined ? {} : { permissions }),
  });

/** A hook's answer, with a throw or a rejection as `undefined`. */
async function settled<T>(run: () => T | Promise<T>): Promise<T | undefined> {
  try {
    return await run();
  } catch {
    return undefined;
  }
}

/**
 * Asks `automation.mayPublish` about `version` as the caller: `undefined`
 * when it allows the publish, the refusal otherwise. Without claims, or when
 * the hook refuses or throws, the publish is refused.
 */
export function mayPublishRefusal(
  call: BlockCall,
  mayPublish: NonNullable<AutomationHooks["mayPublish"]>,
  version: WorkflowVersion,
  claims: Readonly<Record<string, unknown>> | undefined,
): AsyncResult<DbError | undefined> {
  return call(
    "workflow_definition_get",
    { definition: version.definition },
    (value) =>
      definitionOf(recordOf(value, "workflow_definition_get")).tenant ?? null,
  ).andThen(async (tenant) => {
    if (claims === undefined) {
      return ok(
        forbidden(
          "Pass the publisher's claims to versions.publish: authorization.automation.mayPublish decides this publish",
          "WORKFLOW_PUBLISHER_FORBIDDEN",
        ),
      );
    }
    const permissions = await call(
      "workflow_graph_permissions",
      { graph: version.graph ?? graphOf(undefined) },
      (value) => (Array.isArray(value) ? stringsOf(value) : []),
    );
    if (!permissions.ok) return permissions;
    const sub = claims["sub"];
    const allowed = await settled(() =>
      mayPublish({
        publisher: typeof sub === "string" ? sub : null,
        tenant,
        permissions: permissions.data,
        claims,
      }),
    );
    return ok(
      allowed === true
        ? undefined
        : forbidden(
            "The authorization provider refused to publish this workflow",
            "WORKFLOW_PUBLISHER_FORBIDDEN",
            permissions.data,
          ),
    );
  });
}

/**
 * The claims a step of `version` runs with: `workflow_run_principal` checks
 * the stored publisher, then `runAs` narrows their claims. Every refusal is
 * an error; nothing falls back to the service role.
 */
export function runAsPublisher(
  serviceCall: BlockCall,
  runAs: AutomationHooks["runAs"],
  version: string | undefined,
): AsyncResult<Readonly<Record<string, unknown>>> {
  if (version === undefined) {
    return AsyncResult.err(
      dbError(
        "invalid_request",
        "The step call has no version id: pass meta.versionId to the graph runtime as version",
      ),
    );
  }
  return serviceCall(
    "workflow_run_principal",
    { version },
    (value): AutomationRef => {
      const row = recordOf(value, "workflow_run_principal");
      return {
        publisher: optionalText(row["publisher"]) ?? null,
        tenant: optionalText(row["tenant"]) ?? null,
        permissions: Array.isArray(row["permissions"])
          ? stringsOf(row["permissions"])
          : [],
      };
    },
  ).andThen(async (automation) => {
    if (runAs === undefined) {
      return err(
        forbidden(
          "Pass authorization hooks with automation.runAs to createBuilder: a published workflow's steps run as its publisher",
          "WORKFLOW_PUBLISHER_REVOKED",
        ),
      );
    }
    const claims = await settled(() => runAs(automation));
    if (claims === undefined || claims === null || !isRecord(claims)) {
      return err(
        forbidden(
          automation.publisher === null
            ? "The app has no service principal for this organization's workflow"
            : "The user who published this workflow can no longer run it",
          "WORKFLOW_PUBLISHER_REVOKED",
        ),
      );
    }
    return ok(claims);
  });
}
