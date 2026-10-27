# Design

This covers the marketing site (`apps/marketing`, bettersupabase.com). The docs
site uses the Fumadocs UI theme with its own tokens. Marketing is built from
shadcn components (style `base-vega` on Base UI) and ReUI, with Tailwind CSS 4.

## Tokens

All colors are CSS variables in `app/globals.css`, set for `:root` and `.dark`
and exposed to Tailwind through `@theme inline`. Use the token classes
(`bg-background`, `text-muted-foreground`, `border-border`), never a raw
color.

| Token                                       | Use                                                         |
| ------------------------------------------- | ----------------------------------------------------------- |
| `background`, `foreground`                  | the page and body text                                      |
| `muted-foreground`                          | secondary text, descriptions, captions                      |
| `primary`, `primary-foreground`             | the main call to action                                     |
| `secondary`, `accent`, `muted`              | quiet surfaces and hover states                             |
| `card`, `popover`                           | raised surfaces                                             |
| `border`, `input`, `ring`                   | lines, fields and focus rings                               |
| `brand`                                     | the green accent: eyebrows, dots, one highlight per section |
| `destructive`, `success`, `warning`, `info` | status, each with a `-foreground` pair                      |

The neutrals are grayscale (`oklch` with zero chroma). `brand` is the only
hue in the chrome; in light mode it is dark enough (4.5:1 on `background`) to
carry text.

The ten catalog categories each have a Tailwind palette hue in
`features/blocks/categories.ts` (`text`, `tint`, `solid`, `soft`, `ring`,
every light class with its `dark:` pair). The hue marks which category a
block belongs to and appears only in catalog visuals: previews, category
icons and counts. Status still uses the status tokens. Preview surfaces sit on
the `bg-dots` utility from `app/globals.css`. Radius comes from `--radius` (0.625rem), and the scale runs
from `rounded-sm` to `rounded-4xl`.

## Type roles

Inter is the sans face (`--font-sans`) and Geist Mono the code face
(`--font-mono`), both loaded in `lib/fonts.ts`. Code uses `text-code`
(0.8125rem).

| Role              | Classes                                                              |
| ----------------- | -------------------------------------------------------------------- |
| Hero heading      | `text-4xl sm:text-5xl lg:text-6xl font-semibold text-balance`        |
| Page heading      | `text-3xl font-semibold tracking-tight`                              |
| Section heading   | `text-2xl sm:text-3xl font-semibold tracking-tight text-balance`     |
| Eyebrow           | `text-brand text-xs font-semibold tracking-wide uppercase`           |
| Body and lead     | `text-base leading-7 text-pretty`, `text-muted-foreground` for leads |
| UI and small text | `text-sm`                                                            |

## Components

- `components/ui`: shadcn primitives (`button`, `accordion`, `tabs`, `input`).
  Add new ones with the shadcn CLI, then adjust them in place; the registry's
  `base-vega` items import `cn` from a `cn` package, so point the import at
  `@/lib/utils` instead of installing it.
- `components/reui`: ReUI components from the `@reui` registry (`alert`,
  `badge`, `frame`). The registry needs `REUI_LICENSE_KEY`.
- `features/`: one folder per area, each with its `components/` and helpers.
  - `features/catalog`: what the catalog sections share. Each section has
    its own route group and layout: `app/(blocks)/layout.tsx` and
    `app/(recipes)/layout.tsx` wrap their pages in `SidebarShell`, which
    takes the section's nav as a prop and renders it in a sticky aside on
    large screens and in a `Sheet` below `lg`. Both sidebars scroll through `SidebarScroll`
    (the shadcn `ScrollArea`, with an overlay scrollbar, edges that fade while
    there is more to scroll, and the current link scrolled into view). The
    folder also holds `PageHeader`, `Breadcrumbs`, `OnThisPage` and the
    `DetailSkeleton` that detail pages show while they read their params.
  - `features/blocks`: `categories.ts` (each category's icon, slug, summary
    and color classes), `block-icons.ts` (one lucide icon per block, with the
    category icon as the fallback), the coded mini-UI previews
    (`BlockPreview`), tiles, the search and the detail sections. `BlockIcon`
    draws a block's icon in a tile tinted with its category color; tiles, the
    hero, the sidebars and the recipes
    use it, and category headings keep `CategoryIcon`. `BlocksNav` is the
    blocks sidebar (it was `CatalogNav`). `MigrationViewer` shows a block's
    migration files in one `Frame`: a file list next to the selected file,
    highlighted on the server, with a `Select` on small screens.
    `DependencyGraph` is a static SVG rendered on the server from the layout
    helpers in `lib/blocks.ts` (`blockGraphLayout`, `columnLayout`), so it
    ships no client JS. The pages read `lib/blocks.ts`, which parses
    `lib/catalog.json`; `scripts/build-catalog.ts` writes that file from the
    SQL module registry before every marketing task.
  - `features/recipes`: tiles, the screenshot cover, the step list,
    `RecipesNav` (recipes grouped by their block's category) and the Web and
    Native tabs, kept in `?platform=`.
  - Create is not part of this site. It runs in the cloud app at
    `app.bettersupabase.com/create` (ADR 0057), and `next.config.ts`
    redirects `/create` there with a 308.
- `components/sections`: page sections. Every section renders through
  `Section`, which sets the width, padding, eyebrow, heading and description.
  `LogoCloud` on the home page lists every framework, runtime and
  integration from `lib/integrations.ts`, each linking to its docs page. Marks come from `simple-icons`, imported by name; the few it
  lacks are inline SVGs in `components/site/brand-icons.tsx`.
- `components/site`: the navbar (with `NavLink` for the active section and an
  icon button for GitHub), footer, logo, `ThemeHotkey`, `SiteLink`, which
  picks a typed Next.js `Link` for app routes and a plain anchor for `/docs`
  and external URLs, and `LinkButton`, a `SiteLink` with the button
  classes.
- Buttons use the `buttonVariants` variants (`default`, `outline`,
  `secondary`, `ghost`, `destructive`, `link`) and sizes (`xs`, `sm`,
  `default`, `lg` and the `icon` sizes) from `components/ui/button-variants.ts`.
  Don't restyle a button with ad hoc classes.
- A link that looks like a button is a `LinkButton`, rendered on the server.
  A client component that needs button classes gets them as a `className`
  prop from its server parent, so `cva` and `tailwind-merge` stay out of the
  client bundle. The Base UI `Button` is for client components that need its
  behavior.
- Code samples render through `components/code-block.tsx` (Shiki, highlighted
  at build time).

## Responsive rules

- Design for 360px first, then add `sm:`, `md:` and `lg:` steps.
- Content width is `max-w-7xl` with `px-6 md:px-8` (`max-w-6xl` for the hero). Text blocks stay at
  `max-w-2xl` or narrower.
- Grids collapse to one column on small screens. Nothing scrolls sideways
  except code blocks.

## Motion

Motion comes from `tw-animate-css` and the component states (the accordion's
`animate-accordion-down` and `animate-accordion-up`, `transition-colors` on
hover). Keep it short and tied to a state change. No scroll-triggered or
looping animation.

## Accessibility

- Text meets WCAG 2.2 AA contrast in both themes. Check `muted-foreground` on
  `muted` surfaces when you add one.
- Every interactive element has a visible focus ring (`focus-visible:ring-ring/50`)
  and an accessible name.
- The theme follows the system setting (`next-themes`, `defaultTheme="system"`).
  There is no theme button: pressing D switches it (`ThemeHotkey` skips
  modifier keys and form fields), and the footer names the shortcut.
- Headings go in order: one `h1` per page, `h2` per section.
- `jsx-a11y` runs in lint with no rules turned off.
- The first tab stop is the "Skip to content" link to `main#main`.
- A region that scrolls on its own (a long code panel) is focusable and named.
- Every data region has a loading skeleton, an empty state with an action and
  an inline error with Retry.

## Reject these

- Raw colors, hex values or inline `style` (lint rejects inline styles outside
  the OG image and icon routes).
- Gradients, glows, glass effects and drop shadows used as decoration.
- A second accent hue in the chrome, a category hue outside catalog visuals,
  or `brand` on more than one element per section.
- Stock illustrations, emojis and icon-only buttons without a label.
- Components from Radix or vaul; the repo uses Base UI (lint rejects the imports).
- Copy that praises the product instead of saying what it does (`.agents/rules/writing.mdc`).
