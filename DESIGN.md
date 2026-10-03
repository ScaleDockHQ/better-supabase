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
carry text. Radius comes from `--radius` (0.625rem), and the scale runs
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

- `components/ui`: shadcn primitives (`button`, `accordion`). Add new ones with
  the shadcn CLI, then adjust them in place.
- `components/reui`: ReUI components from the `@reui` registry (`badge`).
  The registry needs `REUI_LICENSE_KEY`.
- `components/sections`: page sections. Every section renders through
  `Section`, which sets the width, padding, eyebrow, heading and description.
- `components/site`: the navbar, footer, logo, theme toggle, `SiteLink`,
  which picks a typed Next.js `Link` for app routes and a plain anchor for
  `/docs` and external URLs, and `LinkButton`, a `SiteLink` with the button
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
- Content width is `max-w-6xl` with `px-6 md:px-8`. Text blocks stay at
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
- The theme follows the system setting (`next-themes`, `defaultTheme="system"`),
  and the toggle overrides it.
- Headings go in order: one `h1` per page, `h2` per section.
- `jsx-a11y` runs in lint with no rules turned off.

## Reject these

- Raw colors, hex values or inline `style` (lint rejects inline styles outside
  the OG image and icon routes).
- Gradients, glows, glass effects and drop shadows used as decoration.
- A second accent hue, or `brand` on more than one element per section.
- Stock illustrations, emojis and icon-only buttons without a label.
- Components from Radix or vaul; the repo uses Base UI (lint rejects the imports).
- Copy that praises the product instead of saying what it does (`AGENTS.md`, Writing).
