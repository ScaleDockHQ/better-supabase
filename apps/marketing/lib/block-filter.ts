/** The fields the `/blocks` overview renders and filters on. */
export interface BlockSummary {
  readonly name: string;
  readonly title: string;
  readonly category: string;
  readonly description: string;
  readonly requires: readonly string[];
  readonly hasReact: boolean;
}

export const ALL_CATEGORIES = "All";

/**
 * The blocks in `category` (or every block for `All`) whose name, title or
 * description contains each word of `query`, ignoring case.
 */
export function filterBlocks<T extends BlockSummary>(
  blocks: readonly T[],
  category: string,
  query: string,
): T[] {
  const words = query.toLowerCase().split(/\s+/).filter(Boolean);
  return blocks.filter((block) => {
    if (category !== ALL_CATEGORIES && block.category !== category) {
      return false;
    }
    const text =
      `${block.name} ${block.title} ${block.description}`.toLowerCase();
    return words.every((word) => text.includes(word));
  });
}
