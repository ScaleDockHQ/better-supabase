import type { Iteration, Project } from "./tasks.ts";

import { optionalInstant } from "../../core/block-helpers.ts";
import { temporal } from "../../core/temporal-required.ts";
import { optionalMoneyOf } from "../money-codec.ts";
import { enumOrThrow, optionalText, recordOf, textOf } from "../shared.ts";

type Loose<T> = { [K in keyof T]: T[K] | undefined };

export function compact<T extends object>(value: Loose<T>): T {
  // SAFETY: what is left after dropping undefined keys has the shape of T.
  return Object.fromEntries(
    Object.entries(value).filter(([, item]) => item !== undefined),
  ) as T;
}

export const num = (value: unknown): number | undefined => {
  if (typeof value === "number") {
    return value;
  }

  if (typeof value === "string" && value !== "") {
    return Number(value);
  }

  return undefined;
};

const RESOLUTIONS = ["day", "month", "quarter", "half", "year"] as const;

type Resolution = (typeof RESOLUTIONS)[number];

const resolutionOf = (value: unknown): Resolution | undefined =>
  RESOLUTIONS.find((item) => item === value);

const date = (value: unknown): Temporal.PlainDate | undefined =>
  typeof value === "string"
    ? temporal().PlainDate.from(value.slice(0, 10))
    : undefined;

export function projectOf(value: unknown): Project {
  const row = recordOf(value, "project");

  return compact<Project>({
    id: textOf(row["id"]),
    key: textOf(row["key"]),
    name: textOf(row["name"]),
    ownerId: optionalText(row["owner_id"]),
    status: enumOrThrow(
      row["status"],
      ["planned", "active", "paused", "completed", "canceled"] as const,
      "project status",
    ),
    startOn: date(row["start_on"]),
    targetOn: date(row["target_on"]),
    progress: num(row["progress"]),
    budget:
      row["budget_currency"] === null || row["budget_currency"] === undefined
        ? undefined
        : optionalMoneyOf(row["budget_amount"], row["budget_currency"]),
    budgetHours: num(row["budget_hours"]),
    description: optionalText(row["description"]),
    teamId: optionalText(row["team_id"]),
    priority: num(row["priority"]),
    icon: optionalText(row["icon"]),
    color: optionalText(row["color"]),
    rank: optionalText(row["rank"]),
    health:
      row["health"] === "on_track" ||
      row["health"] === "at_risk" ||
      row["health"] === "off_track"
        ? row["health"]
        : undefined,
    healthAt: optionalInstant(row["health_at"]),
    startResolution: resolutionOf(row["start_resolution"]),
    targetResolution: resolutionOf(row["target_resolution"]),
    completedAt: optionalInstant(row["completed_at"]),
    canceledAt: optionalInstant(row["canceled_at"]),
    archived:
      row["archived_at"] !== null && row["archived_at"] !== undefined
        ? true
        : undefined,
    createdAt: optionalInstant(row["created_at"]),
    updatedAt: optionalInstant(row["updated_at"]),
  });
}

export function iterationOf(value: unknown): Iteration {
  const row = recordOf(value, "iteration");

  return compact<Iteration>({
    id: textOf(row["id"]),
    teamId: optionalText(row["team_id"]),
    name: textOf(row["name"]),
    startsOn: date(row["starts_on"]) ?? temporal().PlainDate.from("1970-01-01"),
    endsOn: date(row["ends_on"]) ?? temporal().PlainDate.from("1970-01-01"),
  });
}
