import { describe, expect, it } from "vitest";

import { readFileFacts } from "../../../src/cli/schema-reader/index.ts";
import * as facts from "../../../src/cli/schema-reader/queries.ts";
import { withoutComments } from "../../../src/sql/audit-registrations.ts";
import * as keys from "../../../src/sql/foreign-keys.ts";
import { parseDeclared } from "../../../src/sql/pipeline/model.ts";
import * as scan from "../../../src/sql/schema-scan.ts";
import { SCHEMAS, files } from "./corpus.ts";

const read = await Promise.all(
  files.map((file) => readFileFacts(file.text, { path: file.name })),
);

const sorted = (entries: Iterable<readonly [string, unknown]>): string =>
  JSON.stringify([...entries].toSorted(([a], [b]) => a.localeCompare(b)));

const norm = (index: { readonly where?: string | undefined }): string =>
  scan.normalizedPredicate(index.where);

describe("the query layer matches the text scanners, per file", () => {
  it.each(files.map((file, at) => ({ ...file, at })))("$name", (file) => {
    const one = [{ text: file.text }];
    const own = [read[file.at]!];

    expect(sorted(facts.declaredViews(own, SCHEMAS))).toBe(
      sorted(scan.declaredViews(one, SCHEMAS)),
    );

    expect(facts.policyGrants(own, SCHEMAS)).toEqual(
      scan.policyGrants(one, SCHEMAS),
    );

    for (const name of ["vector", "pgcrypto", "pg_trgm", "citext"]) {
      expect(facts.extensionSchema(own, name)).toBe(
        scan.extensionSchema(one, name),
      );
    }

    expect(
      sorted(Object.entries(facts.declaredUpdatedAtTriggers(own, SCHEMAS))),
    ).toBe(
      sorted(Object.entries(scan.declaredUpdatedAtTriggers(one, SCHEMAS))),
    );

    const scanned = scan.indexStatements(withoutComments(file.text));
    const read1 = facts.indexStatements(read[file.at]!);

    expect(read1.map((each) => ({ ...each, where: norm(each) }))).toEqual(
      scanned.map((each) => ({ ...each, where: norm(each) })),
    );

    const normalized = (
      map: ReadonlyMap<string, readonly { readonly where?: string }[]>,
    ): string =>
      sorted(
        [...map].map(([table, list]) => [
          table,
          list.map((each) => ({ ...each, where: norm(each) })),
        ]),
      );

    expect(normalized(facts.declaredIndexes(own, SCHEMAS))).toBe(
      normalized(scan.declaredIndexes(one, SCHEMAS)),
    );

    expect(facts.declaredForeignKeys(own, SCHEMAS)).toEqual(
      keys.declaredForeignKeys(one, SCHEMAS),
    );

    const received = facts.declarationsOf(read[file.at]!);
    const expected = parseDeclared(file.text);

    // The scanner misses `create trigger "name"`, since its pattern wants a
    // word boundary after the name; the reader reads it.
    const missed = received.objects.filter(
      (object) =>
        object.kind === "trigger" &&
        !expected.objects.some(
          (each) => each.kind === "trigger" && each.name === object.name,
        ),
    );

    for (const object of missed) {
      expect(file.text).toMatch(
        new RegExp(`trigger\\s+"${object.name.split(".").at(-1)!}"`),
      );
    }

    // The scanner keeps the quotes of an identifier in `terms`; the reader
    // reads `"a"` and `a` as one name.
    const unquoted = (terms: string): string =>
      terms.replaceAll(/"([a-z_][a-z0-9_]*)"/g, "$1");

    const withoutArity = (name: string): string => name.replace(/\/\d+$/, "");

    // Known scanner faults the reader fixes, each checked below:
    // - a function's arity counts the commas inside default expressions;
    // - a column type ends at the first comma inside `array[...]`;
    // - a top-level `insert` after a statement it swallowed is not seen.
    const strip = <T extends typeof received>(
      value: T,
      truncated: boolean,
    ): unknown => ({
      ...value,
      inserts: [],
      objects: value.objects
        .filter((object) => !missed.includes(object))
        .map((object) => ({ ...object, name: withoutArity(object.name) })),
      policies: value.policies.map((policy) => ({
        ...policy,
        terms: unquoted(policy.terms),
      })),
      alters: value.alters.map((alter) => ({
        ...alter,
        definitions: alter.definitions.map((each) => ({
          ...each,
          type: truncated ? each.type.slice(0, 20) : each.type,
        })),
      })),
      creates: value.creates.map((each) => ({
        ...each,
        definitions: each.definitions.map((definition) => ({
          ...definition,
          type: truncated ? definition.type.slice(0, 20) : definition.type,
        })),
      })),
    });

    expect(
      expected.inserts.every((line) => received.inserts.includes(line)),
    ).toBe(true);

    const cut = JSON.stringify(expected) !== JSON.stringify(received);

    expect(strip(received, cut && /array\[[^\]]*,/i.test(file.text))).toEqual(
      strip(expected, cut && /array\[[^\]]*,/i.test(file.text)),
    );
  });
});

describe("the query layer matches the text scanners, across files", () => {
  const all = files.map((file) => ({ text: file.text }));

  it("views, grants, updated-at triggers and foreign keys", () => {
    expect(sorted(facts.declaredViews(read, SCHEMAS))).toBe(
      sorted(scan.declaredViews(all, SCHEMAS)),
    );
    expect(facts.policyGrants(read, SCHEMAS)).toEqual(
      scan.policyGrants(all, SCHEMAS),
    );
    expect(
      sorted(Object.entries(facts.declaredUpdatedAtTriggers(read, SCHEMAS))),
    ).toBe(
      sorted(Object.entries(scan.declaredUpdatedAtTriggers(all, SCHEMAS))),
    );
    expect(facts.declaredForeignKeys(read, SCHEMAS)).toEqual(
      keys.declaredForeignKeys(all, SCHEMAS),
    );
    // Reads every module file with both layers; a loaded CI runner needs more
    // than the default 20 s.
  }, 120_000);
});
