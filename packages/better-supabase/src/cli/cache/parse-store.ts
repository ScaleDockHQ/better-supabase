import type { ParseStore } from "../../sql/index.ts";

import { createDiskStore } from "./disk-store.ts";

/** Entries kept on disk, so the file stays bounded as the schema files change. */
const KEPT = 4096;

/** A parse store with the entries it holds and a way to write them. */
export interface DiskParseStore extends ParseStore {
  /** Writes the file when this run added an entry; returns whether it did. */
  readonly flush: () => boolean;
}

/**
 * Keeps parse results in `<cache>/parse/files.json`, keyed by the content hash
 * and parser version `createParseCache` builds (see `createDiskStore`).
 */
export function createDiskParseStore(
  folder: string,
  salt: string,
): DiskParseStore {
  return createDiskStore({
    folder,
    name: "parse/files.json",
    salt,
    kept: KEPT,
  });
}
