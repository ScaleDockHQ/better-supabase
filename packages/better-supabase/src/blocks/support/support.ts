import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockContext } from "../create-blocks.ts";
import type { CompositeOptions } from "../define-block.ts";
import type { SlaClock } from "../sla/index.ts";
import type { WorkItem, WorkItemInput } from "../tasks/index.ts";
import type { SupportParts } from "./manifest.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult as Async, ok } from "../../core/result.ts";

/** What `support.openTicket` returns. */
export interface OpenedTicket {
  readonly ticket: WorkItem;
  /** The SLA clocks started for the ticket. */
  readonly clocks: readonly SlaClock[];
}

/** What `support.escalate` returns. */
export interface EscalatedTicket {
  /** How many assignees the ticket has now. */
  readonly assignees: number;
  /** The SLA clocks, recomputed for the new priority. */
  readonly clocks: readonly SlaClock[];
}

/** The helpers `support` adds over its parts. */
export interface Support {
  /**
   * Creates the ticket, a task named by `blocks.tasks.names` (`tasks.create`),
   * then starts its SLA clocks (`sla.start`, with `priority`). A failed SLA
   * start returns its error and leaves the ticket created, so retry it with
   * `sla.start` on `{ type: "task", id }`, not `openTicket`.
   */
  openTicket(input: {
    organizationId: string;
    ticket: WorkItemInput;
    assigneeIds?: readonly string[] | undefined;
    priority?: string | undefined;
  }): AsyncResult<OpenedTicket>;
  /**
   * Escalates a ticket: hands it to `assigneeIds` (`tasks.assign`, which
   * replaces the assignees and notifies the new ones), then restarts its SLA
   * clocks at the higher `priority` (`sla.start`). A failed SLA start returns
   * its error and leaves the new assignees in place, so retry it with
   * `sla.start`.
   */
  escalate(input: {
    ticketId: string;
    assigneeIds: readonly string[];
    priority: string;
  }): AsyncResult<EscalatedTicket>;
}

/** What the `support` creator receives. */
export type SupportOptions = BlockContext &
  CompositeOptions<SupportParts> & {
    /** `before` and `after` hooks per method (ADR 0015). */
    readonly hooks?: NoInfer<BlockHooks<Support>>;
    /** Receives the errors `after` hooks throw. Default: `console`. */
    readonly logger?: Logger;
  };

/** Creates the `support` helpers over the clients of its parts. */
export function createSupport(options: SupportOptions): Support {
  const { tasks, sla } = options.parts;

  const client: Support = {
    openTicket: ({ organizationId, ticket, assigneeIds, priority }) =>
      Async.from<OpenedTicket>(async () => {
        const created = await tasks.create({
          organizationId,
          input: ticket,
          ...(assigneeIds === undefined ? {} : { assigneeIds }),
        });

        if (!created.ok) {
          return created;
        }

        const clocks = await sla.start({
          subject: { type: "task", id: created.data.id },
          ...(priority === undefined ? {} : { priority }),
        });

        return clocks.ok
          ? ok({ ticket: created.data, clocks: clocks.data })
          : clocks;
      }),
    escalate: ({ ticketId, assigneeIds, priority }) =>
      Async.from<EscalatedTicket>(async () => {
        const assigned = await tasks.assign({
          workItemId: ticketId,
          userIds: assigneeIds,
        });

        if (!assigned.ok) {
          return assigned;
        }

        const clocks = await sla.start({
          subject: { type: "task", id: ticketId },
          priority,
        });

        return clocks.ok
          ? ok({ assignees: assigned.data, clocks: clocks.data })
          : clocks;
      }),
  };

  return withBlockHooks(client, options.hooks, {
    block: "support",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
