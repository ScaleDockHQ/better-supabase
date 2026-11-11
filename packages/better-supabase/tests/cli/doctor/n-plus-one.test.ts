import { describe, expect, it } from "vitest";

import type { DoctorContext, TextFile } from "../../../src/cli/doctor/rules.ts";

import { N_PLUS_ONE_RULES } from "../../../src/cli/doctor/n-plus-one.ts";

const relationships = [
  {
    foreign_key_name: "orders_customer_id_fkey",
    schema: "public",
    relation: "orders",
    columns: ["customer_id"],
    is_one_to_one: false,
    referenced_schema: "public",
    referenced_relation: "customers",
    referenced_columns: ["id"],
  },
  {
    foreign_key_name: "notes_customer_id_fkey",
    schema: "public",
    relation: "notes",
    columns: ["customer_id", "organization_id"],
    is_one_to_one: false,
    referenced_schema: "public",
    referenced_relation: "customers",
    referenced_columns: ["id", "organization_id"],
  },
];

function check(
  code: "BS634" | "BS635",
  text: string,
): readonly { message: string; location?: { line: number } }[] {
  const rule = N_PLUS_ONE_RULES.find((candidate) => candidate.code === code);
  const sources: TextFile[] = [{ path: "src/lib/data.ts", text }];

  // SAFETY: both rules read only `sources` and the snapshot's relationships.
  const findings = rule?.check({
    sources,
    snapshot: { generator: { relationships } },
  } as unknown as DoctorContext);

  if (!Array.isArray(findings)) {
    throw new TypeError(`${code} runs synchronously`);
  }

  return findings;
}

const lines = (...body: string[]): string => body.join("\n");

describe("BS634", () => {
  it("finds a read per item in Promise.all over map", () => {
    const findings = check(
      "BS634",
      lines(
        "export async function load(db: Db, ids: string[]) {",
        "  return Promise.all(",
        "    ids.map(async (id) => await db.customers.get(id)),",
        "  );",
        "}",
      ),
    );

    expect(findings).toHaveLength(1);
    expect(findings[0]?.location?.line).toBe(3);
    expect(findings[0]?.message).toContain(
      "db.customers.get once per item of `ids`",
    );
    expect(findings[0]?.message).toContain(
      "db.customers.list({ where: { id: { in: ids } } })",
    );
  });

  it("suggests an include when the outer rows come from a related read", () => {
    const findings = check(
      "BS634",
      lines(
        "export async function load(db: Db) {",
        "  const orders = await db.orders.list().orThrow();",
        "  for (const order of orders) {",
        "    const customer = await db.customers.get(order.customerId);",
        "  }",
        "}",
      ),
    );

    expect(findings).toHaveLength(1);
    expect(findings[0]?.message).toContain(
      "add `include: { customer: true }` to db.orders.list at line 2",
    );
  });

  it("suggests _count for a count per row of a to-many relation", () => {
    const findings = check(
      "BS634",
      lines(
        "export async function load(db: Db) {",
        "  const customers = await db.customers.list().orThrow();",
        "  return customers.map((customer) =>",
        "    db.notes.count({ where: { customerId: customer.id } }),",
        "  );",
        "}",
      ),
    );

    expect(findings[0]?.message).toContain(
      "include: { _count: { notes: true } }",
    );
  });

  it("counts RPCs, block calls, supabase-js selects, local readers and services", () => {
    const findings = check(
      "BS634",
      lines(
        "const loadOne = async (db: Db, id: string) => db.customers.get(id);",
        "export async function load(db: Db, supabase: Client, ids: string[]) {",
        "  const services = createCustomerServices(ctx);",
        "  for (const id of ids) {",
        '    await db.$rpc("week_summary", { p_id: id });',
        "    await db.$blocks.invoices.approvalStatus(id);",
        '    await supabase.from("customers").select("*").eq("id", id);',
        "    await loadOne(db, id);",
        "    await services.getCustomer(id);",
        "  }",
        "}",
      ),
    );

    expect(findings.map((finding) => finding.location?.line)).toEqual([
      5, 6, 7, 8, 9,
    ]);
    expect(findings[3]?.message).toContain(
      "loadOne (which calls db.customers.get)",
    );
  });

  it("stays quiet for batched reads, writes, fixed lists and other calls", () => {
    expect(
      check(
        "BS634",
        lines(
          "export async function save(db: Db, rows: Row[], ids: string[], chunks: string[][]) {",
          "  await db.customers.list({ where: { id: { in: ids } } });",
          "  for (const chunk of chunks) {",
          "    await db.customers.list({ where: { id: { in: chunk } } });",
          "  }",
          "  for (const row of rows) {",
          "    await db.customers.update(row.id, { name: row.name });",
          "  }",
          "  for (const row of rows) {",
          "    const current = await db.customers.get(row.id);",
          '    await db.$rpc("archive_customer", { p_id: row.id });',
          "  }",
          '  for (const kind of ["a", "b"]) {',
          "    await db.customers.count({ where: { kind } });",
          "  }",
          "  await Promise.all(ids.map((id) => fetch(url + id)));",
          "  const byId = new Map(rows.map((row) => [row.id, row]));",
          "  ids.forEach((id) => byId.get(id));",
          "  const customers = await db.customers.list({",
          "    include: { orders: true },",
          "  });",
          "  for (const id of ids) {",
          "    await db.customers.list({ where: { organizationId } });",
          "  }",
          "}",
        ),
      ),
    ).toEqual([]);
  });

  it("follows readers, callback forms and skips loops that write", () => {
    const findings = check(
      "BS634",
      lines(
        "const one = (db: Db, id: string) => db.customers.get(id);",
        "const viaOne = async (db: Db, id: string) => await one(db, id);",
        "async function saveOne(db: Db, id: string) {",
        "  await db.customers.get(id);",
        "  await db.customers.update(id, {});",
        "}",
        "const mixed = async (db: Db, id: string) => {",
        "  await db.customers.get(id);",
        "  await db.orders.delete(id);",
        "};",
        "const later = async (db: Db, id: string) => await mixed(db, id);",
        "export async function load(db: Db, rows: Row[], ids: string[], name: string) {",
        "  const services = createCustomerServices(ctx);",
        "  rows.filter((row) => row.active).map(function (row) {",
        "    return viaOne(db, row.id);",
        "  });",
        "  ids.forEach(id => db.order_lines.list({ where: { orderId: id } }));",
        "  rows.map(({ id, kind = 1 }: Row) => {",
        "    const key = id;",
        "    return db.$rpc(name, { p_id: key });",
        "  });",
        "  for (const id of ids) await db.customers.count({ where: { id } });",
        "  for (let index = 0; index < ids.length; index += 1) {",
        "    await db.customers.get(ids[index]);",
        "  }",
        "  ids.map(toKey);",
        "  for (const id of ids) {",
        "    await cache.getCustomer(id);",
        "    await later(db, id);",
        "  }",
        "  for (const id of ids) {",
        "    await db.customers.get(id);",
        "    await db.$blocks.invoices.markPaid(id);",
        "  }",
        "  for (const id of ids) {",
        "    await db.customers.get(id);",
        "    await services.updateCustomer(id);",
        "  }",
        "}",
      ),
    );

    expect(findings.map((finding) => finding.location?.line)).toEqual([
      15, 17, 20, 22,
    ]);
    expect(findings[0]?.message).toContain(
      "viaOne (which calls db.customers.get) once per item of `rows.filter((row) => row.active)`",
    );
  });

  it("skips files without database calls", () => {
    expect(check("BS634", "export const a = [1].map((x) => x);")).toEqual([]);
    expect(check("BS634", "export const db = 1;")).toEqual([]);
  });
});

describe("BS635", () => {
  it("finds a dependent read of a related table", () => {
    const findings = check(
      "BS635",
      lines(
        "export async function load(db: Db) {",
        "  const ordersResult = await db.orders.list({ limit: 20 });",
        "  const orders = ordersResult.orThrow();",
        "  const customerIds = orders.map((order) => order.customerId);",
        "  const customers = await db.customers.list({",
        "    where: { id: { in: customerIds } },",
        "  });",
        "}",
      ),
    );

    expect(findings).toHaveLength(1);
    expect(findings[0]?.location?.line).toBe(5);
    expect(findings[0]?.message).toContain(
      "waits for db.orders.list at line 2, then reads db.customers.list",
    );
    expect(findings[0]?.message).toContain("include: { customer: true }");
  });

  it("follows Promise.all destructuring and composite foreign keys", () => {
    const findings = check(
      "BS635",
      lines(
        "export async function load(db: Db, id: string) {",
        "  const [customer, other] = await Promise.all([",
        "    db.customers.get(id),",
        "    fetchOther(),",
        "  ]);",
        "  await db.notes.list({ where: { customerId: customer.id } });",
        "}",
      ),
    );

    expect(findings[0]?.message).toContain("include: { notes: true }");
  });

  it("leaves out self relations, non-table reads and snake_case tables", () => {
    const findings = check(
      "BS635",
      lines(
        "export async function load(db: Db, supabase: Client) {",
        "  const [customer, week] = await Promise.all([",
        "    db.customers.get(id),",
        '    db.$rpc("week", {}),',
        "  ]);",
        "  await db.customers.list({ where: { id: customer.id } });",
        "  await db.notes.list({ where: { customerId: week.id } });",
        '  const { data: orders } = await supabase.from("orders").select("*");',
        '  await supabase.from("customers").select("*").in("id", orders.map((o) => o.customer_id));',
        "  await db.order_lines.list({ where: { order_id: orders[0].id } });",
        "}",
      ),
    );

    expect(findings.map((finding) => finding.location?.line)).toEqual([9]);
  });

  it("stays quiet for unrelated tables, other filters and other scopes", () => {
    expect(
      check(
        "BS635",
        lines(
          "export async function a(db: Db) {",
          "  const orders = await db.orders.list();",
          "  await db.products.list({ where: { id: { in: orders.map((o) => o.productId) } } });",
          "  await db.customers.list({ where: { name: orders[0].label } });",
          "}",
          "export async function b(db: Db, orders: Order[]) {",
          "  await db.customers.list({ where: { id: { in: orders.map((o) => o.customerId) } } });",
          "}",
        ),
      ),
    ).toEqual([]);
  });
});
