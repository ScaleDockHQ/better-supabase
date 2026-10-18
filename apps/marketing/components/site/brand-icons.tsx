/** A brand mark as one path on a 24 by 24 grid, the shape `simple-icons` exports. */
export interface BrandMark {
  readonly title: string;
  readonly path: string;
}

/*
 * Plain glyphs for the projects `simple-icons` has no mark for. They are not
 * the projects' logos; the name always sits next to them.
 */
export const elysiaGlyph: BrandMark = {
  title: "Elysia",
  path: "M14 3a9 9 0 1 0 7 14.6A7.5 7.5 0 0 1 14 3Z",
};

export const orpcGlyph: BrandMark = {
  title: "oRPC",
  path: "M6 9a3 3 0 1 1 0 6 3 3 0 0 1 0-6Zm12 0a3 3 0 1 1 0 6 3 3 0 0 1 0-6ZM9 11h6v2H9Z",
};

export const valibotGlyph: BrandMark = {
  title: "Valibot",
  path: "M4 3h16a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1Zm3 9.5L11 16.5l7-7-1.5-1.5-5.5 5.5-2.5-2.5Z",
};

export const arktypeGlyph: BrandMark = {
  title: "ArkType",
  path: "M12 3 22 21H2Zm0 5-5.5 10h11Z",
};

export const yjsGlyph: BrandMark = {
  title: "Yjs",
  path: "M3 3h3.5l5.5 7.5L17.5 3H21l-7.5 10v8h-3v-8Z",
};

export const powersyncGlyph: BrandMark = {
  title: "PowerSync",
  path: "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18Zm0 3a6 6 0 1 1 0 12 6 6 0 0 1 0-12Zm0 3a3 3 0 1 0 0 6 3 3 0 0 0 0-6Z",
};

/** A monochrome mark in `currentColor`. Decorative: the caller names it. */
export function BrandLogo({
  mark,
  className,
}: {
  readonly mark: BrandMark;
  readonly className?: string;
}) {
  return (
    <svg
      viewBox="0 0 24 24"
      aria-hidden="true"
      focusable="false"
      fill="currentColor"
      fillRule="evenodd"
      className={`shrink-0 ${className ?? "size-6"}`}
    >
      <path d={mark.path} />
    </svg>
  );
}
