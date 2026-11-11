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
  ...[
    ["quote_tasks", "task_id", "public", "tasks"],
    ["invoice_tasks", "task_id", "public", "tasks"],
    ["quote_tasks", "organization_id", "public", "organizations"],
    ["invoice_tasks", "organization_id", "public", "organizations"],
    ["members", "user_id", "auth", "users"],
    ["profiles", "id", "auth", "users"],
  ].map(([relation, column, schema, referenced]) => ({
    foreign_key_name: `${relation!}_${column!}_fkey`,
    schema: "public",
    relation: relation!,
    columns: [column!],
    is_one_to_one: false,
    referenced_schema: schema!,
    referenced_relation: referenced!,
    referenced_columns: ["id"],
  })),
];

function check(
  code: "BS634" | "BS635",
  text: string,
): readonly {
  message: string;
  target?: string;
  severity?: string;
  location?: { line: number };
}[] {
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

describe("BS634 writes and side effects", () => {
  it("skips a loop that decides through a service or notifies per item", () => {
    expect(
      check(
        "BS634",
        lines(
          "export async function decide(ctx: Ctx, ids: string[], rows: Row[]) {",
          "  const timeOff = createTimeOffService(ctx);",
          "  const services = createFeatureServices(ctx);",
          "  for (const id of ids) {",
          "    await timeOff.decideRequest(id);",
          "    await timeOff.getRequest(id);",
          "  }",
          "  await Promise.all(",
          "    rows.map(async (row) => {",
          "      const item = await services.agenda.getAgendaItem(row.id);",
          "      await notifyAgendaUpdated({ item });",
          "    }),",
          "  );",
          "  for (const id of ids) {",
          "    const request = await services.getRequest(id);",
          "    await events.publish(request);",
          "  }",
          "  for (const row of rows) {",
          "    await services.getRequest(row.id);",
          "    await services.agenda.assignTask(row.id);",
          "  }",
          "}",
        ),
      ),
    ).toEqual([]);
  });

  it("still reports a read loop beside a side effect outside it", () => {
    const findings = check(
      "BS634",
      lines(
        "export async function load(ctx: Ctx, ids: string[]) {",
        "  const services = createFeatureServices(ctx);",
        "  const rows = await Promise.all(ids.map((id) => services.getRequest(id)));",
        "  await notifyLoaded(rows);",
        "}",
      ),
    );

    expect(findings.map((finding) => finding.location?.line)).toEqual([3]);
  });
});

describe("BS634 hints", () => {
  it("names an OR or an array RPC for a search term or a JSON value", () => {
    const findings = check(
      "BS634",
      lines(
        "export async function search(db: Db, terms: string[], ids: string[], products: ProductsService) {",
        "  await Promise.all(terms.map((needle) =>",
        "    db.products.list({ where: { OR: [{ name: { contains: needle } }] } }),",
        "  ));",
        "  await Promise.all(ids.map((endpointId) =>",
        "    db.workflows.list({ where: { graph: { contains: { nodes: [{ config: { endpointId } }] } } } }),",
        "  ));",
        "  await Promise.all(terms.map((keyword) => products.listProducts({ q: keyword })));",
        '  await Promise.all(terms.map((term) => supabase.from("notes").select("id").ilike("body", term)));',
        "  await Promise.all(ids.map((id) => db.notes.list({ where: { customerId: id } })));",
        "}",
      ),
    );

    expect(findings.map((finding) => finding.location?.line)).toEqual([
      3, 6, 8, 9, 10,
    ]);
    expect(findings[0]?.message).toContain(
      "`needle` is a search term, and an `in` filter only matches whole values.",
    );
    expect(findings[1]?.message).toContain(
      "matches `endpointId` inside a JSON column with `contains`",
    );
    expect(findings[2]?.message).toContain("`keyword` is a search term");
    expect(findings[3]?.message).toContain("`term` is a search term");
    expect(findings[4]?.message).toContain("with an `in` filter");
  });
});

describe("BS634 per-item callbacks of helpers", () => {
  it("finds a read per item in a chunk helper or a per-item helper callback", () => {
    const findings = check(
      "BS634",
      lines(
        "export async function labels(customers: CustomersService, ids: string[]) {",
        "  await mapInChunks(ids, 20, async (customerId) => {",
        "    await customers.getCustomer(customerId);",
        "  });",
        "  await mapInChunks(ids, async (chunk) =>",
        "    Promise.all(chunk.map((id) => customers.getCustomer(id))),",
        "  );",
        "}",
      ),
    );

    expect(findings.map((finding) => finding.location?.line)).toEqual([3, 6]);
    expect(findings[1]?.message).toContain("once per item of `chunk`");
  });

  it("stays quiet for whole chunks and for helpers that aren't loops", () => {
    expect(
      check(
        "BS634",
        lines(
          "export async function labels(customers: CustomersService, ids: string[]) {",
          "  await mapInChunks(ids, 20, async (chunk) => customers.listByIds(chunk));",
          "  for (const ids of chunks) await customers.listByIds(ids);",
          "  const byId = new Map(ids.map((id) => [id, id]));",
          "  await withRetry(ids, () => customers.getCustomer(ids[0]));",
          "  await limit((id) => customers.getCustomer(id));",
          "}",
        ),
      ),
    ).toEqual([]);
  });
});

describe("target keys", () => {
  it("names the function and the callee, numbered per function", () => {
    const findings = check(
      "BS634",
      lines(
        "export const reorder = tenantAction(schema, async (input) => {",
        "  await Promise.all(input.ids.map((id) => db.tasks.get(id)));",
        "  await Promise.all(input.ids.map((id) => db.tasks.get(id)));",
        "});",
        "export async function load(db: Db, ids: string[]): Promise<{ rows: Row[] }> {",
        "  return { rows: await Promise.all(ids.map((id) => db.tasks.get(id))) };",
        "}",
        "const service = {",
        "  async read(ids: string[]) {",
        "    for (const id of ids) await db.notes.get(id);",
        "  },",
        "};",
        "for (const id of ids) await db.notes.get(id);",
      ),
    );

    expect(findings.map((finding) => finding.target)).toEqual([
      "src/lib/data.ts#reorder:db.tasks.get",
      "src/lib/data.ts#reorder:db.tasks.get#2",
      "src/lib/data.ts#load:db.tasks.get",
      "src/lib/data.ts#read:db.notes.get",
      "src/lib/data.ts#<module>:db.notes.get",
    ]);
  });

  it("keeps a target when lines are added above it", () => {
    const body = [
      "export async function load(db: Db, ids: string[]) {",
      "  return Promise.all(ids.map((id) => db.tasks.get(id)));",
      "}",
    ];

    const [before] = check("BS634", lines(...body));
    const [after] = check("BS634", lines("import a from 'a';", "", ...body));

    expect(after?.target).toBe(before?.target);
    expect(after?.location?.line).toBe(4);
  });
});

describe("BS635 waves and chains", () => {
  it("lowers a dependent read in a Promise.all of reads on the same rows to info", () => {
    const findings = check(
      "BS635",
      lines(
        "export async function load(db: Db, id: string) {",
        "  const order = await db.orders.get(id);",
        "  const [customer, lines] = await Promise.all([",
        "    db.customers.list({ where: { id: order.customerId } }),",
        "    db.orderLines.list({ where: { orderId: order.id } }),",
        "  ]);",
        "  const [other] = await Promise.all([",
        "    db.customers.list({ where: { id: order.customerId } }),",
        "    fetchOther(),",
        "  ]);",
        "}",
      ),
    );

    expect(
      findings.map((finding) => [finding.location?.line, finding.severity]),
    ).toEqual([
      [4, "info"],
      [8, undefined],
    ]);
    expect(findings[0]?.message).toContain(
      "An include saves a request, not a wait",
    );
  });

  it("names a nested include through a table both reference", () => {
    const findings = check(
      "BS635",
      lines(
        "export async function load(db: Db, quoteId: string) {",
        "  const links = await db.quoteTasks.list({ where: { quoteId } });",
        "  const taskIds = links.map((row) => row.taskId);",
        "  await db.invoiceTasks.list({ where: { organizationId, taskId: { in: taskIds } } });",
        "  const members = await db.members.list();",
        "  await db.profiles.list({ where: { id: { in: members.map((m) => m.userId) } } });",
        "  await db.invoiceTasks.list({ where: { organizationId: links[0].organizationId } });",
        "}",
      ),
    );

    expect(findings.map((finding) => finding.location?.line)).toEqual([4]);
    expect(findings[0]?.message).toContain(
      "include: { task: { include: { invoiceTasks: true } } }",
    );
  });
});
