# Formatting

- `pnpm fix` runs `ultracite fix`: Oxfmt, then the Oxlint autofixes. Run it
  before `pnpm verify` instead of fixing format findings by hand.
- A formatter reflow after a rename can move the line that an
  `oxlint-disable-next-line` or `@ts-expect-error` directive must sit above.
  Put the directive directly above the exact property or expression line it
  covers, and check it again after `pnpm format`.
- Revert unrelated regenerated output, such as a version header that a
  generator rewrote, instead of committing it.
- Oxfmt keeps Markdown and MDX line breaks as written (`proseWrap:
"preserve"`); don't rewrap a paragraph you didn't change.
- Generated files (`database.types.ts`, `generated*.ts`, `api/exports.json`)
  are in the Oxfmt and Oxlint ignore lists. Regenerate them; never format
  them by hand.
