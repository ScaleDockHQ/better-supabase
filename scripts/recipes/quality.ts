import type { RecipeSource } from "./types.ts";

import { WEB_APP } from "./types.ts";

const RISKS = `${WEB_APP}/src/features/risks/components`;
const OBSERVATIONS = `${WEB_APP}/src/features/observations/components`;
const CASES = `${WEB_APP}/src/features/cases/components`;
const INSPECTIONS = `${WEB_APP}/src/features/inspections/components`;
const MEETINGS = `${WEB_APP}/src/features/meetings/components`;

/**
 * Recipes for the quality, risk, observation, case, inspection and meeting
 * blocks.
 */
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
  {
    slug: "inspection-program-calendar",
    title: "Inspection programme calendar",
    blocks: ["inspections"],
    kind: "component",
    description:
      "The audit programme in a data grid: each inspection in the month it is planned, with its number, kind, programme and status.",
    web: {
      file: `${INSPECTIONS}/inspection-program-calendar.tsx`,
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
    slug: "inspection-run",
    title: "Inspection run",
    blocks: ["inspections"],
    kind: "component",
    description:
      "One inspection with its status, checklist and team, its findings with a Raise case button for each nonconformity, and a Close button once every one has its case.",
    web: {
      file: `${INSPECTIONS}/inspection-run.tsx`,
      components: ["alert", "badge", "button", "empty", "@reui/frame"],
      glue: [],
    },
  },
  {
    slug: "meeting-agenda",
    title: "Meeting agenda",
    blocks: ["meetings"],
    kind: "component",
    description:
      "The organization's meetings in a data grid with their kind, place and status, the most recent first, each linking to its minutes.",
    web: {
      file: `${MEETINGS}/meeting-agenda.tsx`,
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
    slug: "meeting-minutes",
    title: "Meeting minutes",
    blocks: ["meetings"],
    kind: "component",
    description:
      "One meeting with the minutes of each agenda item, its decisions with the votes so far and a Settle button, the tasks it opened, and Start and Hold buttons for the people who run it.",
    web: {
      file: `${MEETINGS}/meeting-minutes.tsx`,
      components: ["alert", "badge", "button", "empty", "@reui/frame"],
      glue: [],
    },
  },
];
