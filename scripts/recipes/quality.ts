import type { RecipeSource } from "./types.ts";

import { WEB_APP } from "./types.ts";

const RISKS = `${WEB_APP}/src/features/risks/components`;
const OBSERVATIONS = `${WEB_APP}/src/features/observations/components`;
const CASES = `${WEB_APP}/src/features/cases/components`;

/** Recipes for the quality, risk, observation and case blocks. */
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
  {
    slug: "observation-chart",
    title: "Observation chart",
    blocks: ["observations"],
    kind: "component",
    description:
      "A record's latest vital signs with the flag against each reference range and a sparkline of the recent readings.",
    web: {
      file: `${OBSERVATIONS}/observation-chart.tsx`,
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
  {
    slug: "case-board",
    title: "Case board",
    blocks: ["cases"],
    kind: "component",
    description:
      "The open cases in stage columns, reported to verifying; dragging a card moves the case to that stage of its kind's pipeline.",
    web: {
      file: `${CASES}/case-board.tsx`,
      components: ["badge", "card", "@reui/kanban"],
      glue: [],
    },
  },
  {
    slug: "case-detail",
    title: "Case detail",
    blocks: ["cases"],
    kind: "component",
    description:
      "One case with its severity, root cause, what still blocks closing it and its actions, and a Close button once nothing blocks it.",
    web: {
      file: `${CASES}/case-detail.tsx`,
      components: ["alert", "badge", "button", "empty", "@reui/frame"],
      glue: [],
    },
  },
];
