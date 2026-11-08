import type { ModuleRenderStore } from "../../sql/index.ts";

import { createDiskStore } from "./disk-store.ts";

/** Module instances kept on disk: more than any project installs. */
const KEPT = 1024;

/** A module render store with a way to write what this run added. */
export interface DiskModuleStore extends ModuleRenderStore {
  /** Writes the file when this run added an entry; returns whether it did. */
  readonly flush: () => boolean;
}

/**
 * Keeps module renders in `<cache>/modules/renders.json`, one entry per module
 * instance, overwritten in place (see `createDiskStore`).
 */
export function createDiskModuleStore(
  folder: string,
  salt: string,
): DiskModuleStore {
  const store = createDiskStore({
    folder,
    name: "modules/renders.json",
    salt,
    kept: KEPT,
  });

  return {
    salt,
    get: store.get,
    set: (key, entry) => {
      store.set(key, entry);
    },
    flush: store.flush,
  };
}
