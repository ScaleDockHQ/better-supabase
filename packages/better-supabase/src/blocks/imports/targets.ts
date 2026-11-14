/** A block's name and the import entities its manifest declares. */
export interface ImportTargetBlock {
  readonly name: string;
  readonly importTarget?: readonly string[];
}

/** One import entity and the block that takes its rows. */
export interface ImportTargetEntry {
  readonly entity: string;
  readonly block: string;
}

/**
 * Every import entity the blocks declare through `importTarget` (ADR 0851),
 * sorted by entity, so the imports block can list what a run can write. Two
 * blocks that declare the same entity fail: the import SQL would dispatch to
 * one of them silently.
 */
export function importTargetsOf(
  blocks: readonly ImportTargetBlock[],
): readonly ImportTargetEntry[] {
  const owners = new Map<string, string>();

  for (const block of blocks) {
    for (const entity of block.importTarget ?? []) {
      const owner = owners.get(entity);

      if (owner !== undefined && owner !== block.name) {
        throw new TypeError(
          `import entity "${entity}" is declared by "${owner}" and "${block.name}"`,
        );
      }

      owners.set(entity, block.name);
    }
  }

  return [...owners]
    .map(([entity, block]) => ({ entity, block }))
    .toSorted((a, b) => a.entity.localeCompare(b.entity));
}
