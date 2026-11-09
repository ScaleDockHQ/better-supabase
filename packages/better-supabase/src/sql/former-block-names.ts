import naming from "../../api/naming.json" with { type: "json" };

const BLOCK_KEY = /^blocks\.([^.]+)$/;

/**
 * Blocks that were renamed, as the new name to the old one (`time-entries` to
 * `time-tracking`). They are the `blocks.<name>` `configKey` rows of
 * `api/naming.json`.
 */
export const FORMER_BLOCK_NAMES: ReadonlyMap<string, string> = new Map(
  naming.renames.flatMap((rename) => {
    const from = BLOCK_KEY.exec(rename.from);
    const to = BLOCK_KEY.exec(rename.to);

    return rename.kind === "configKey" && from !== null && to !== null
      ? [[to[1]!, from[1]!] as const]
      : [];
  }),
);

/**
 * `name` under its current block name, for a file or row from before the
 * rename.
 */
export function currentBlockName(name: string): string {
  for (const [current, former] of FORMER_BLOCK_NAMES) {
    if (former === name) {
      return current;
    }
  }

  return name;
}
