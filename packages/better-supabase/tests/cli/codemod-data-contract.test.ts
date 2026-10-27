import { describe, expect, it } from "vitest";

import { rewriteDataContract } from "../../src/cli/codemod-data-contract.ts";

const rewrite = (source: string): string => rewriteDataContract(source).text;

describe("rewriteDataContract", () => {
  it("renames the methods that kept their arguments", () => {
    expect(rewrite("db.notes.findMany({ limit: 5 })")).toBe(
      "db.notes.list({ limit: 5 })",
    );
    expect(rewrite("db.notes.paginate({ page: 2, size: 10 })")).toBe(
      "db.notes.page({ page: 2, size: 10 })",
    );
    expect(rewrite("db.notes.findById(id, { select: ['id'] })")).toBe(
      "db.notes.get(id, { select: ['id'] })",
    );
    expect(rewrite("db.notes.createMany(rows)")).toBe("db.notes.create(rows)");
    expect(rewrite("db.notes.upsertMany(rows, { onConflict: 'slug' })")).toBe(
      "db.notes.upsert(rows, { onConflict: 'slug' })",
    );
  });

  it("flags calls it can't rewrite and skips the rest", () => {
    const review = (source: string) =>
      rewriteDataContract(source).review.length;

    expect(review("db.notes.deleteMany(filter, options)")).toBe(1);
    expect(review("db.notes.updateMany({ data: patch })")).toBe(1);
    expect(review("db.notes.updateMany({ where: { id: 1 } })")).toBe(1);
    expect(rewrite("storage.exists(path, bucket)")).toBe(
      "storage.exists(path, bucket)",
    );
    expect(rewrite("db.notes.deleteMany({ where")).toBe(
      "db.notes.deleteMany({ where",
    );
    expect(rewrite("db.notes.findFirst({})")).toBe(
      "db.notes.list({ limit: 1 }).map((rows) => rows[0] ?? null)",
    );
  });

  it("moves where into a filter for updateMany and deleteMany", () => {
    expect(
      rewrite("db.notes.updateMany({ where: { done: true }, data: patch })"),
    ).toBe("db.notes.update({ where: { done: true } }, patch)");
    expect(
      rewrite(
        "db.notes.updateMany({ where, data: { done: true }, returning: true })",
      ),
    ).toBe("db.notes.update({ where }, { done: true }, { returning: true })");
    expect(rewrite("db.notes.deleteMany({ where: { id: 1 } })")).toBe(
      "db.notes.delete({ where: { id: 1 } })",
    );
    expect(
      rewrite("db.notes.deleteMany({ where: { id: 1 }, maxAffected: 1 })"),
    ).toBe("db.notes.delete({ where: { id: 1 } }, { maxAffected: 1 })");
  });

  it("turns findUnique and findOnly into optional gets", () => {
    expect(
      rewrite("db.users.findUnique({ where: { email }, select: ['id'] })"),
    ).toBe("db.users.get({ email }, { select: ['id'], optional: true })");
    expect(rewrite("db.users.findOnly({ where: { role: 'owner' } })")).toBe(
      "db.users.get({ where: { role: 'owner' } }, { optional: true })",
    );
  });

  it("turns findFirst into a one-row list", () => {
    expect(rewrite("db.notes.findFirst()")).toBe(
      "db.notes.list({ limit: 1 }).map((rows) => rows[0] ?? null)",
    );
    expect(rewrite("db.notes.findFirst({ where: { id } })")).toBe(
      "db.notes.list({ where: { id }, limit: 1 }).map((rows) => rows[0] ?? null)",
    );
    expect(rewrite("db.notes.findFirst(args)")).toBe(
      "db.notes.list({ ...args, limit: 1 }).map((rows) => rows[0] ?? null)",
    );
  });

  it("turns exists into a count, and leaves other exists calls alone", () => {
    expect(rewrite("db.notes.exists({ where: { id } })")).toBe(
      "db.notes.count({ where: { id } }).map((n) => n > 0)",
    );
    expect(rewrite("db.notes.exists()")).toBe(
      "db.notes.count().map((n) => n > 0)",
    );
    expect(rewrite("storage.exists(path)")).toBe("storage.exists(path)");
    expect(rewrite("bucket.exists({ file })")).toBe("bucket.exists({ file })");
    expect(rewrite("fs.exists(a, b)")).toBe("fs.exists(a, b)");
  });

  it("rewrites nested calls and lists calls it can't rewrite", () => {
    expect(
      rewrite(
        "db.a.deleteMany({ where: { id: await db.b.findMany({ limit: 1 }) } })",
      ),
    ).toBe("db.a.delete({ where: { id: await db.b.list({ limit: 1 }) } })");

    const result = rewriteDataContract("\ndb.notes.updateMany(args)");
    expect(result.text).toBe("\ndb.notes.updateMany(args)");
    expect(result.review).toEqual([
      { line: 2, message: expect.stringContaining("by hand") },
    ]);
  });

  it("leaves comments and strings alone unless raw", () => {
    const source = "// db.notes.findMany()\nconst s = 'x.findMany()';";

    expect(rewrite(source)).toBe(source);
    expect(rewriteDataContract(source, { raw: true }).text).toBe(
      "// db.notes.list()\nconst s = 'x.list()';",
    );
  });
});
