import type { BlockOf } from "../define-block.ts";

import { attachmentsBlock } from "../attachments/manifest.ts";
import { defineBlock } from "../define-block.ts";
import { driveBlock } from "../drive/manifest.ts";
import { searchBlock } from "../search/manifest.ts";
import { shareLinksBlock } from "../share-links/manifest.ts";
import { trashBlock } from "../trash/manifest.ts";
import { versionsBlock } from "../versions/manifest.ts";
import { createFilespace } from "./filespace.ts";

/** The blocks `filespace` is made of, by block name. */
export const filespaceParts: {
  readonly drive: typeof driveBlock;
  readonly attachments: typeof attachmentsBlock;
  readonly versions: typeof versionsBlock;
  readonly "share-links": typeof shareLinksBlock;
  readonly search: typeof searchBlock;
  readonly trash: typeof trashBlock;
} = {
  drive: driveBlock,
  attachments: attachmentsBlock,
  versions: versionsBlock,
  "share-links": shareLinksBlock,
  search: searchBlock,
  trash: trashBlock,
};

export type FilespaceParts = typeof filespaceParts;

/**
 * The `filespace` composite (ADR 0177): a drive with attachments, versions,
 * share links, search and trash. It installs its parts and sets their defaults;
 * the parts stay ordinary blocks in the config.
 */
export const filespaceBlock: BlockOf<"filespace", typeof createFilespace> =
  defineBlock({
    name: "filespace",
    composes: filespaceParts,
    create: createFilespace,
    category: "content",
  });
