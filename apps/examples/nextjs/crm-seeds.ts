/**
 * The demo rows of the CRM pages (`app.*`), declared once for the entity page
 * descriptors in `better-supabase.config.ts` (ADR 1035). A `seedRef` names a
 * row another page seeds, and a `seedDate` counts from the day the seed runs.
 */
import type { EntityPageInput } from "better-supabase/list";

import { seedDate, seedRef } from "better-supabase/list";

type PageSeed = NonNullable<EntityPageInput["seed"]>;

export const dealsSeed = {
  tiers: ["demo"],
  rows: [
    {
      name: "Annual plan for Globex",
      company: { type: "company", id: "00000000-0000-4000-8000-0000000c0001" },
      ownerId: "00000000-0000-4000-8000-0000000000a1",
      amount: 1_200_000,
      currency: "EUR",
      pipelineId: seedRef("app.pipelines", "Sales"),
      stage: "negotiation",
      forecast: "commit",
      closeOn: seedDate(12),
      age_days: 4,
    },
    {
      name: "Initech rollout",
      company: { type: "company", id: "00000000-0000-4000-8000-0000000c0002" },
      ownerId: "00000000-0000-4000-8000-0000000000a1",
      amount: 840_000,
      currency: "EUR",
      pipelineId: seedRef("app.pipelines", "Sales"),
      stage: "proposal",
      forecast: "best_case",
      closeOn: seedDate(25),
      age_days: 9,
      contact_email: "wile@acme-roadrunner.test",
    },
    {
      name: "Hooli pilot",
      company: { type: "company", id: "00000000-0000-4000-8000-0000000c0003" },
      ownerId: "00000000-0000-4000-8000-0000000000a2",
      amount: 300_000,
      currency: "EUR",
      pipelineId: seedRef("app.pipelines", "Sales"),
      stage: "discovery",
      forecast: "pipeline",
      closeOn: seedDate(40),
      age_days: 2,
    },
    {
      name: "Hooli seats expansion",
      company: { type: "company", id: "00000000-0000-4000-8000-0000000c0003" },
      ownerId: "00000000-0000-4000-8000-0000000000a2",
      amount: 150_000,
      currency: "EUR",
      pipelineId: seedRef("app.pipelines", "Sales"),
      stage: "qualified",
      forecast: "pipeline",
      closeOn: seedDate(55),
      age_days: 1,
    },
    {
      name: "Globex add-on",
      company: { type: "company", id: "00000000-0000-4000-8000-0000000c0001" },
      ownerId: "00000000-0000-4000-8000-0000000000a1",
      amount: 450_000,
      currency: "EUR",
      pipelineId: seedRef("app.pipelines", "Sales"),
      stage: "won",
      forecast: "commit",
      closeOn: seedDate(-6),
      age_days: 6,
    },
    {
      name: "Umbrella renewal",
      company: { type: "company", id: "00000000-0000-4000-8000-0000000c0004" },
      ownerId: "00000000-0000-4000-8000-0000000000a2",
      amount: 220_000,
      currency: "EUR",
      pipelineId: seedRef("app.pipelines", "Sales"),
      stage: "lost",
      forecast: "omit",
      closeOn: seedDate(-12),
      age_days: 12,
    },
  ],
} as const satisfies PageSeed;

export const pipelinesSeed = {
  tiers: ["demo"],
  rows: [
    {
      key: "sales",
      name: "Sales",
      subject_type: "deal",
      is_default: true,
      stages: [
        {
          key: "qualified",
          name: "Qualified",
          category: "open",
          probability: 20,
        },
        {
          key: "discovery",
          name: "Discovery",
          category: "open",
          probability: 35,
        },
        {
          key: "proposal",
          name: "Proposal",
          category: "open",
          probability: 55,
        },
        {
          key: "negotiation",
          name: "Negotiation",
          category: "open",
          probability: 75,
        },
        { key: "won", name: "Closed won", category: "won", probability: 100 },
        { key: "lost", name: "Closed lost", category: "lost", probability: 0 },
      ],
    },
    {
      key: "renewals",
      name: "Renewals",
      subject_type: "deal",
      is_default: false,
      stages: [
        {
          key: "upcoming",
          name: "Upcoming",
          category: "open",
          probability: 80,
        },
        { key: "renewed", name: "Renewed", category: "won", probability: 100 },
        { key: "churned", name: "Churned", category: "lost", probability: 0 },
      ],
    },
  ],
} as const satisfies PageSeed;

export const segmentsSeed = {
  tiers: ["demo"],
  rows: [
    {
      name: "Customers",
      description: "Companies that bought.",
      subjectType: "company",
      conditions: {
        id: "root",
        type: "group",
        combinator: "and",
        rules: [
          {
            id: "lifecycle",
            type: "rule",
            path: ["lifecycle"],
            operator: "is",
            value: "customer",
          },
        ],
      },
    },
    {
      name: "Open leads",
      description: "Companies still being qualified.",
      subjectType: "company",
      conditions: {
        id: "root",
        type: "group",
        combinator: "and",
        rules: [
          {
            id: "lifecycle",
            type: "rule",
            path: ["lifecycle"],
            operator: "is",
            value: "lead",
          },
        ],
      },
    },
  ],
} as const satisfies PageSeed;

export const queuesSeed = {
  tiers: ["demo"],
  rows: [
    {
      name: "New companies",
      subjectType: "company",
      strategy: "round_robin",
      rank: 0,
      members: [
        { userId: "00000000-0000-4000-8000-0000000000a1", weight: 1 },
        { userId: "00000000-0000-4000-8000-0000000000a2", weight: 1 },
      ],
    },
  ],
} as const satisfies PageSeed;

export const scoresSeed = {
  tiers: ["demo"],
  rows: [
    {
      key: "health",
      name: "Account health",
      subjectType: "company",
      rules: [
        {
          id: "customer",
          label: "customer",
          points: 60,
          conditions: {
            id: "root",
            type: "group",
            combinator: "and",
            rules: [
              {
                id: "r1",
                type: "rule",
                path: ["lifecycle"],
                operator: "is",
                value: "customer",
              },
            ],
          },
        },
        {
          id: "opportunity",
          label: "opportunity",
          points: 40,
          conditions: {
            id: "root",
            type: "group",
            combinator: "and",
            rules: [
              {
                id: "r1",
                type: "rule",
                path: ["lifecycle"],
                operator: "is",
                value: "opportunity",
              },
            ],
          },
        },
      ],
      bands: [
        { label: "cold", min: 0 },
        { label: "warm", min: 30 },
        { label: "hot", min: 60 },
      ],
    },
  ],
} as const satisfies PageSeed;

export const contractsSeed = {
  tiers: ["demo"],
  rows: [
    {
      title: "Globex master services agreement",
      counterpartyType: "company",
      counterpartyId: "00000000-0000-4000-8000-0000000c0001",
      ownerId: "00000000-0000-4000-8000-0000000000a1",
      value: 1_200_000,
      currency: "EUR",
      startsOn: seedDate(-90),
      endsOn: seedDate(275),
      autoRenew: true,
      renewalMonths: 12,
      noticeDays: 60,
    },
    {
      title: "Initech pilot terms",
      counterpartyType: "company",
      counterpartyId: "00000000-0000-4000-8000-0000000c0002",
      ownerId: "00000000-0000-4000-8000-0000000000a1",
      value: 840_000,
      currency: "EUR",
      startsOn: seedDate(14),
      endsOn: seedDate(379),
      autoRenew: false,
    },
    {
      title: "Hooli NDA",
      counterpartyType: "company",
      counterpartyId: "00000000-0000-4000-8000-0000000c0003",
      ownerId: "00000000-0000-4000-8000-0000000000a2",
      startsOn: seedDate(-20),
      endsOn: seedDate(345),
      autoRenew: false,
    },
  ],
} as const satisfies PageSeed;
