import { describe, expect, it } from "vitest";

import {
  CONTROL_MODULES,
  CONTROL_TABLES,
} from "../../../src/sql/modules/data-lifecycle-restore.ts";
import { SQL_MODULES } from "../../../src/sql/registry.ts";

// A tenant table whose name says it grants, holds or proves access.
const ACCESS =
  /(grant|member|role|permission|approval|access|token|secret|credential|session|share|guest|factor|identit|key)/u;

describe("restore control modules", () => {
  it("lists every block whose tenant tables decide access", () => {
    const unclassified = Object.values(SQL_MODULES)
      .filter((module) => !CONTROL_MODULES.includes(module.name))
      .flatMap((module) =>
        Object.entries(module.names?.tables ?? {})
          .filter(
            ([logical, spec]) =>
              spec.lifecycle?.tenant !== undefined &&
              ACCESS.test(`${logical} ${spec.name}`) &&
              !CONTROL_TABLES.includes(`${module.name}.${logical}`) &&
              !RESTORABLE.has(`${module.name}.${logical}`),
          )
          .map(([logical]) => `${module.name}.${logical}`),
      );

    expect(unclassified).toEqual([]);
  });
});

// Tables whose name matches but that hold business data a restore may write.
const RESTORABLE: ReadonlySet<string> = new Set<string>([
  "accounting.roles",
  "assignment.members",
  "contacts.identities",
  "forms.answerKeys",
  "segments.members",
  "tills.sessions",
]);
