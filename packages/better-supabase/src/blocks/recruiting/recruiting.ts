import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockContext } from "../create-blocks.ts";
import type { CompositeOptions } from "../define-block.ts";
import type { Employee, EmployeeInput } from "../employees/index.ts";
import type { Application } from "../hiring/index.ts";
import type { RecruitingParts } from "./manifest.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";

/** What `recruiting.hire` returns. */
export interface Hired {
  readonly application: Application;
  readonly employee: Employee;
}

/** The helpers `recruiting` adds over its parts. */
export interface Recruiting {
  /**
   * Marks the application hired, then creates the employee from it (`overrides`
   * set or replace its columns). Both steps are idempotent for one application,
   * so a retry finishes a hire that stopped in the middle.
   */
  hire(input: {
    applicationId: string;
    overrides?: Partial<EmployeeInput> | undefined;
  }): AsyncResult<Hired>;
}

/** What the `recruiting` creator receives. */
export type RecruitingOptions = BlockContext &
  CompositeOptions<RecruitingParts> & {
    /** \`before\` and \`after\` hooks per method (ADR 0015). */
    readonly hooks?: NoInfer<BlockHooks<Recruiting>>;
    /** Receives the errors \`after\` hooks throw. Default: \`console\`. */
    readonly logger?: Logger;
  };

/** Creates the `recruiting` helpers over the clients of its parts. */
export function createRecruiting(options: RecruitingOptions): Recruiting {
  const { hiring, employees } = options.parts;

  const client: Recruiting = {
    hire: ({ applicationId, overrides }) =>
      hiring
        .hire(applicationId)
        .andThen((application) =>
          employees
            .fromApplication({
              applicationId,
              ...(overrides === undefined ? {} : { overrides }),
            })
            .map((employee) => ({ application, employee })),
        ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "recruiting",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
