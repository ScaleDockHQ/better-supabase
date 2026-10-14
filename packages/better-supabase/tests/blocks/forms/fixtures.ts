import type { FormDefinition } from "../../../src/core/contracts/form-definition.ts";

/** Two steps; the second shows only for the team plan. */
export const SIGNUP: FormDefinition = {
  steps: [
    {
      key: "contact",
      title: "Contact",
      description: "Who you are",
      fields: [
        {
          key: "name",
          label: "Name",
          type: "text",
          required: true,
          minLength: 2,
        },
        { key: "email", label: "Email", type: "email", required: true },
        {
          key: "plan",
          label: "Plan",
          type: "option",
          options: [
            { value: "free", label: "Free" },
            { value: "team", label: "Team" },
          ],
        },
        {
          key: "company",
          label: "Company",
          type: "text",
          required: true,
          showIf: { field: "plan", equals: "team" },
        },
      ],
    },
    {
      key: "team",
      title: "Team",
      showIf: { field: "plan", in: ["team"] },
      fields: [
        {
          key: "seats",
          label: "Seats",
          type: "integer",
          min: 2,
          max: 500,
          required: true,
        },
        { key: "terms", label: "Terms", type: "consent", required: true },
      ],
    },
    {
      key: "extra",
      fields: [
        { key: "website", label: "Website", type: "url" },
        { key: "started", label: "Start", type: "date" },
        {
          key: "topics",
          label: "Topics",
          type: "multi",
          min: 1,
          max: 2,
          options: [
            { value: "a", label: "A" },
            { value: "b", label: "B" },
            { value: "c", label: "C" },
          ],
        },
        { key: "budget", label: "Budget", type: "number", min: 0 },
        { key: "notes", label: "Notes", type: "textarea", pattern: "^[^<>]*$" },
        { key: "agree", label: "Newsletter", type: "bool" },
        { key: "meta", label: "Meta", type: "json" },
        {
          key: "why",
          label: "Why",
          type: "text",
          showIf: { field: "agree", filled: true },
        },
      ],
    },
  ],
};
