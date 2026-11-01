import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockContext } from "../create-blocks.ts";
import type { DataExport, DataExportFormat } from "../data-lifecycle/index.ts";
import type { CompositeOptions } from "../define-block.ts";
import type { GovernanceParts } from "./manifest.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult as Async, ok } from "../../core/result.ts";

/** What `governance.exportSubject` returns. */
export interface SubjectExport {
  readonly export: DataExport;
  /** The id of the audit entry that records the export. */
  readonly auditId: string;
}

/** The helpers `governance` adds over its parts. */
export interface Governance {
  /**
   * Requests the export of one record (`dataLifecycle.requestSubjectExport`),
   * then writes the audit entry `data.subject_exported` for it. The entry
   * carries an idempotency key from the export id, so a retry writes one.
   */
  exportSubject(input: {
    subjectType: string;
    subjectId: string;
    format?: DataExportFormat | undefined;
    organizationId?: string | undefined;
  }): AsyncResult<SubjectExport>;
}

/** What the `governance` creator receives. */
export type GovernanceOptions = BlockContext &
  CompositeOptions<GovernanceParts> & {
    /** `before` and `after` hooks per method (ADR 0015). */
    readonly hooks?: NoInfer<BlockHooks<Governance>>;
    /** Receives the errors `after` hooks throw. Default: `console`. */
    readonly logger?: Logger;
  };

/** Creates the `governance` helpers over the clients of its parts. */
export function createGovernance(options: GovernanceOptions): Governance {
  const { audit, "data-lifecycle": dataLifecycle } = options.parts;

  const client: Governance = {
    exportSubject: ({ subjectType, subjectId, format, organizationId }) =>
      Async.from(async () => {
        const requested = await dataLifecycle.requestSubjectExport({
          subjectType,
          subjectId,
          ...(format === undefined ? {} : { format }),
        });

        if (!requested.ok) {
          return requested;
        }

        const recorded = await audit.record({
          eventType: "data.subject_exported",
          targetType: subjectType,
          record: subjectId,
          idempotencyKey: `data.subject_exported:${requested.data.id}`,
          ...(organizationId === undefined ? {} : { organizationId }),
        });

        return recorded.ok
          ? ok({ export: requested.data, auditId: recorded.data })
          : recorded;
      }),
  };

  return withBlockHooks(client, options.hooks, {
    block: "governance",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
