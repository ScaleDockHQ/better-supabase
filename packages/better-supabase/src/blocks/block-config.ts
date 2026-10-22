import type { BlockNaming } from "../core/block-names.ts";

/**
 * One block's entry in `blocks.generated.ts`, which `better-supabase gen`
 * writes from the `blocks` config, so the SQL and TypeScript halves of a block
 * read the same settings.
 */
export interface GeneratedBlock {
  /** The module schema (`blocks.<module>.schema`, then `sql.schema`). */
  readonly schema: string;
  /**
   * The schema of the module's API wrappers (`blocks.<module>.api`, then
   * `sql.api`).
   */
  readonly api?: string;
  /**
   * The options both halves read, with the module's defaults applied, such as
   * `attachments.requireScan` or the notifications `topic`.
   */
  readonly options: Readonly<Record<string, unknown>>;
  /**
   * The names the SQL gives the block's functions when `blocks.<name>.names` or
   * `blocks.<module>.functions` renames them. `defineBlocks` wraps the block's
   * transport with `blockNames(names)`.
   */
  readonly names?: BlockNaming;
  /**
   * The block an instance installs when its key names another
   * (`blocks.labels.block: "tags"`). `createBlocks` checks that the block
   * passed under the key is this one.
   */
  readonly block?: string;
  /**
   * Dependency block to the instance key it uses (`blocks.<instance>.uses`).
   * `createBlocks` takes a port from that instance when more than one block
   * provides it.
   */
  readonly uses?: Readonly<Record<string, string>>;
}

/**
 * `blocks.generated.ts`: the installed blocks' generated config, keyed by
 * instance: the block's name, or the key that installs it again.
 */
export type GeneratedBlocks = Readonly<Record<string, GeneratedBlock>>;

/**
 * The options a block's creator gets from its generated entry: the schema it
 * calls (the API schema when there is one, since the wrappers there are what
 * the caller may run) and the shared options. `defineBlocks` passes them;
 * spread them into a creator you call yourself: `createAiChat({
 * ...generatedOptions(blockConfig["ai-chat"]), transport })`.
 */
export function generatedOptions<const E extends GeneratedBlock>(
  entry: E,
): E["options"] & { readonly schema: string } {
  return { ...entry.options, schema: entry.api ?? entry.schema };
}

/**
 * A realtime topic template from `blocks.generated.ts` with its placeholders
 * filled in, such as the notifications topic `notifications:{userId}`.
 */
export function fillTopic(
  template: string,
  values: Readonly<Record<string, string>>,
): string {
  return template.replaceAll(/\{([A-Za-z]+)\}/g, (match, name: string) => {
    const value = values[name];

    if (value === undefined) {
      throw new TypeError(`fillTopic: no value for ${match} in "${template}"`);
    }

    return value;
  });
}
