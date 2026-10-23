import type { InstanceOn } from "../../src/config/blocks.ts";

/**
 * A block entry from one flat object: its `on` key becomes the entry's `on` and
 * the rest its options, so a table of cases can mix both.
 */
export const entryOf = ({
  on,
  ...options
}: Readonly<Record<string, unknown>>): {
  readonly options: Readonly<Record<string, unknown>>;
  readonly on?: InstanceOn;
} => ({
  options,
  // SAFETY: rejection cases pass a malformed `on` on purpose.
  ...(on !== undefined && { on: on as InstanceOn }),
});
