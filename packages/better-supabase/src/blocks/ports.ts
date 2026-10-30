import type { EventSink } from "../events/cloud-event.ts";
import type { AccessRequests } from "./access-requests/access-requests.ts";
import type { AiFiles } from "./ai-files/types.ts";
import type { Attachments } from "./attachments/attachments.ts";
import type { MailSync } from "./mail-sync/mail-sync.ts";
import type { Workflows } from "./workflows/workflows.ts";

/** What a `notifier` port sends: one notification to its recipients. */
export interface NotifierInput {
  readonly recipients: readonly string[];
  readonly tenant: string;
  /** Deduplicates retries of the same send. */
  readonly key: string;
  readonly subject?: { readonly type: string; readonly id: string };
  readonly data: Readonly<Record<string, unknown>>;
}

/** Sends notifications for a block that consumes `notifier`. */
export interface Notifier {
  send(type: string, input: NotifierInput): unknown;
}

/**
 * The ports blocks provide and consume, by name. A manifest's `provides` builds
 * a port from its client, and `createBlocks` hands it to the blocks whose
 * `consumes` name it. Every port has one provider in a set of blocks, except
 * `sink`: each block that provides one adds an outbox sink.
 */
export interface BlockPorts {
  /** The `notifications` block. */
  readonly notifier: Notifier;
  /** The `ai-files` block, for knowledge. */
  readonly files: AiFiles;
  /** The `attachments` block, for the drive's files. */
  readonly attachments: Attachments;
  /** The `workflows` block, for the workflow builder's schedules. */
  readonly workflows: Workflows;
  /** The `mail-sync` block, for the sequences block's email steps. */
  readonly mailer: Pick<MailSync, "send">;
  /** The `access-requests` block, for access requests on drive nodes. */
  readonly recordAccess: Pick<AccessRequests, "requestRecord" | "records">;
  /** An outbox sink, for `outbox.relayRoute({ consumers: blocks.sinks })`. */
  readonly sink: EventSink;
}

export type PortName = keyof BlockPorts;
