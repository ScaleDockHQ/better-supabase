import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { Codemod, CodemodProject } from "./codemod.ts";

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/**
 * The grouped baseline for a `{ code: { reason, targets } }` object, or a
 * message saying why the file is not one.
 */
export function groupedFromMap(
  value: unknown,
): { readonly groups: readonly unknown[] } | { readonly problem: string } {
  if (!isRecord(value)) {
    return { problem: "is not a { code: { reason, targets } } object" };
  }

  const groups: unknown[] = [];

  for (const [code, entry] of Object.entries(value)) {
    const { reason, targets } = isRecord(entry) ? entry : {};

    if (
      typeof reason !== "string" ||
      !Array.isArray(targets) ||
      !targets.every((target: unknown) => typeof target === "string")
    ) {
      return {
        problem: `has an entry for ${code} without a reason and targets`,
      };
    }

    groups.push({ code, reason, targets });
  }

  return { groups };
}

async function doctorBaselineFiles(
  project: CodemodProject,
): ReturnType<NonNullable<Codemod["project"]>> {
  const path = project.config.doctor.baseline;

  if (path === undefined) {
    return {
      files: [],
      review: [
        { message: "tooling.doctor.baseline is not set; nothing to import." },
      ],
    };
  }

  const file = resolve(project.config.root, path);

  let parsed: unknown;

  try {
    parsed = JSON.parse(await readFile(file, "utf-8"));
  } catch {
    return {
      files: [],
      review: [{ message: `${path} could not be read as JSON.` }],
    };
  }

  if (Array.isArray(parsed)) {
    return { files: [], review: [] };
  }

  const result = groupedFromMap(parsed);

  if ("problem" in result) {
    return { files: [], review: [{ message: `${path} ${result.problem}.` }] };
  }

  return {
    files: [
      {
        path: file,
        contents: `${JSON.stringify(result.groups, null, 2)}\n`,
        policy: "edit",
      },
    ],
    review: [],
  };
}

/** The `doctor-baseline` codemod: read a `{ code: { reason, targets } }` file. */
export function doctorBaselineCodemod(): Codemod {
  return {
    name: "doctor-baseline",
    description:
      "Rewrite a { code: { reason, targets } } baseline file as the grouped list doctor reads",
    project: doctorBaselineFiles,
  };
}
