import type { Iteration, Project } from "./tasks.ts";

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
