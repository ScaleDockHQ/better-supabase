import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { RecordRef } from "../../schema/types.ts";
import type { ContentEntry } from "../content/index.ts";
import type { BlockContext } from "../create-blocks.ts";
import type { CompositeOptions } from "../define-block.ts";
import type { SnapshotResult } from "../versions/index.ts";
import type { CmsParts } from "./manifest.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult as Async, ok } from "../../core/result.ts";

/** What `cms.publishWithVersion` returns. */
export interface PublishedVersion {
  readonly version: SnapshotResult;
  readonly entry: ContentEntry;
}

/** The helpers `cms` adds over its parts. */
export interface Cms {
  /**
   * Keeps a version of the entry's content (`versions.snapshot` on `subject`,
   * labelled `label`), then publishes the entry (`content.publish`). A snapshot
   * of unchanged content returns the latest version, so a retry adds none. A
   * failed publish returns its error with the version kept.
   */
  publishWithVersion(input: {
    entryId: string;
    subject: RecordRef;
    label?: string | undefined;
  }): AsyncResult<PublishedVersion>;
}

/** What the `cms` creator receives. */
export type CmsOptions = BlockContext &
  CompositeOptions<CmsParts> & {
    /** `before` and `after` hooks per method (ADR 0015). */
    readonly hooks?: NoInfer<BlockHooks<Cms>>;
    /** Receives the errors `after` hooks throw. Default: `console`. */
    readonly logger?: Logger;
  };

/** Creates the `cms` helpers over the clients of its parts. */
export function createCms(options: CmsOptions): Cms {
  const { content, versions } = options.parts;

  const client: Cms = {
    publishWithVersion: ({ entryId, subject, label }) =>
      Async.from(async () => {
        const version = await versions.snapshot({
          subject,
          ...(label === undefined ? {} : { input: { label } }),
        });

        if (!version.ok) {
          return version;
        }

        const entry = await content.publish(entryId);

        return entry.ok
          ? ok({ version: version.data, entry: entry.data })
          : entry;
      }),
  };

  return withBlockHooks(client, options.hooks, {
    block: "cms",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
