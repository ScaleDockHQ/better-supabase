import type { RecipeSource } from "./types.ts";

import { WEB_APP } from "./types.ts";

const RISKS = `${WEB_APP}/src/features/risks/components`;

/** Recipes for the quality and risk management blocks. */
export const QUALITY_RECIPES: readonly RecipeSource[] = [
  {
    slug: "risk-register",
    title: "Risk register",
    blocks: ["risks"],
    kind: "component",
    description:
      "The organization's risks in a data grid with their residual band, status and next review date, the highest residual score first.",
    web: {
      file: `${RISKS}/risk-register.tsx`,
      components: [
        "alert",
        "badge",
        "button",
        "empty",
        "skeleton",
        "@reui/data-grid",
        "@reui/frame",
      ],
      glue: [],
    },
  },
  {
    slug: "risk-heatmap",
    title: "Risk heatmap",
    blocks: ["risks"],
    kind: "component",
    description:
      "The open risks on the default matrix, one cell per likelihood and impact with the count in the band's color.",
    web: {
      file: `${RISKS}/risk-heatmap.tsx`,
      components: [
        "alert",
        "badge",
        "button",
        "empty",
        "skeleton",
        "table",
        "@reui/frame",
      ],
      glue: [],
    },
  },
];
