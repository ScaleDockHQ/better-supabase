import type { ImportFollow, PathSegment } from "./config-document/index.ts";

import {
  changedFiles,
  ConfigDocument,
  followedReview,
  openImports,
  ownerOf,
  parsePath,
} from "./config-document/index.ts";

/** Whether `text` is an object literal with nothing in it. */
const emptyObject = (text: string | undefined): boolean =>
  text !== undefined && /^\{\s*\}$/.test(text);

/**
 * Removes the entry at `path`, then each parent object it leaves empty, down to
 * the block's own entry (`blocks.<name>` stays: it installs the block).
 */
function removeWithEmptyParents(
  document: ConfigDocument,
  path: readonly PathSegment[],
  floor = 3,
): "done" | "absent" | "review" {
  const first = document.remove(path);

  if (first.status !== "done") {
    return first.status;
  }

  for (let length = path.length - 1; length >= floor; length -= 1) {
    const parent = path.slice(0, length);

    if (!emptyObject(document.valueText(parent))) {
      break;
    }

    document.remove(parent);
  }

  return "done";
}

/**
 * `text` without the config entries at `paths` (`blocks.<name>.columns.x` or
 * `sameTenant[1]`), the paths it could not find, and a review line for each
 * entry it could not edit in place. With `follow`, an entry under a value the
 * config imports is removed from the file that declares it, and `others` lists
 * the files it changed.
 */
export function withoutConfigPaths(
  text: string,
  paths: readonly string[],
  follow?: ImportFollow,
): {
  readonly text: string;
  readonly missed: readonly string[];
  readonly review: readonly string[];
  readonly others: readonly { readonly file: string; readonly text: string }[];
} {
  const document = ConfigDocument.parse(text);
  const imports = openImports(follow, document);
  const missed: string[] = [];

  for (const path of paths) {
    const segments = parsePath(path);

    if (removeWithEmptyParents(document, segments) === "done") {
      continue;
    }

    const found = ownerOf(imports, segments);

    if (
      found === undefined ||
      removeWithEmptyParents(
        found.owner.document,
        found.inner,
        Math.max(3 - found.owner.prefix.length, 1),
      ) !== "done"
    ) {
      missed.push(path);
    }
  }

  return {
    text: document.text,
    missed,
    review: [...document.review, ...followedReview(imports)],
    others: changedFiles(imports),
  };
}

/**
 * Splits `groups` (a key and the config paths under it) into the groups whose
 * paths can all go and the keys that must stay. `unchanged` says whether the
 * config without a set of paths still renders the same. All groups go together
 * first; a failing set is halved until the groups something still needs are
 * alone, so a few bad groups cost a few renders, not one per group.
 */
export async function settleGroups(
  groups: readonly (readonly [string, readonly string[]])[],
  unchanged: (paths: readonly string[]) => Promise<boolean>,
): Promise<{ kept: string[]; refused: string[] }> {
  const kept: string[] = [];
  const refused: string[] = [];

  const settle = async (
    batch: readonly (readonly [string, readonly string[]])[],
  ): Promise<void> => {
    const paths = batch.flatMap(([, entries]) => entries);

    if (batch.length === 0) {
      return;
    }

    if (await unchanged([...kept, ...paths])) {
      kept.push(...paths);

      return;
    }

    const [only] = batch;

    if (batch.length === 1 && only !== undefined) {
      refused.push(only[0]);

      return;
    }

    const middle = Math.ceil(batch.length / 2);

    await settle(batch.slice(0, middle));
    await settle(batch.slice(middle));
  };

  await settle(groups);

  return { kept, refused };
}
