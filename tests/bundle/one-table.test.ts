import { mkdir, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { rolldown } from "rolldown";
import { describe, expect, it } from "vitest";

const WORK = resolve(import.meta.dirname, "tmp/one-table");

describe("one table on the client", () => {
  it("leaves the other tables out of a page that imports one module", async () => {
    await mkdir(WORK, { recursive: true });
    await writeFile(
      join(WORK, "customers.ts"),
      `export const customersTable = { name: "customers", marker: "ONLY_CUSTOMERS" };\n`,
    );
    await writeFile(
      join(WORK, "orders.ts"),
      `export const ordersTable = { name: "orders", marker: "ONLY_ORDERS" };\n`,
    );
    await writeFile(
      join(WORK, "page.ts"),
      `import { customersTable } from "./customers.ts";\nexport const page = customersTable;\n`,
    );
    await writeFile(
      join(WORK, "barrel.ts"),
      `import { customersTable } from "./customers.ts";\nimport { ordersTable } from "./orders.ts";\nexport const all = [customersTable, ordersTable];\n`,
    );

    const text = async (entry: string): Promise<string> => {
      const bundle = await rolldown({
        input: join(WORK, entry),
        platform: "neutral",
        logLevel: "silent",
      });

      const { output } = await bundle.generate({ format: "esm", minify: true });

      await bundle.close();

      return output
        .flatMap((item) => (item.type === "chunk" ? [item.code] : []))
        .join("\n");
    };

    const page = await text("page.ts");
    const barrel = await text("barrel.ts");

    expect(page).toContain("ONLY_CUSTOMERS");
    expect(page).not.toContain("ONLY_ORDERS");
    expect(barrel).toContain("ONLY_CUSTOMERS");
    expect(barrel).toContain("ONLY_ORDERS");
  });
});
