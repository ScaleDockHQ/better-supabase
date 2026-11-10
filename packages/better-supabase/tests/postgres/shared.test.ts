import { beforeEach, describe, expect, it, vi } from "vitest";

const pools = vi.hoisted(() => ({ options: [] as Record<string, unknown>[] }));

vi.mock(
  import("pg"),
  () =>
    ({
      Pool: class {
        constructor(options: Record<string, unknown>) {
          pools.options.push(options);
        }

        on(): this {
          return this;
        }

        end(): Promise<void> {
          return Promise.resolve();
        }
      },
    }) as never,
);

const { createPostgres } = await import("../../src/postgres/pool.ts");
const { sharedPostgres } = await import("../../src/postgres/shared.ts");

const URL_A = "postgresql://u@host-a/db";

beforeEach(() => {
  pools.options.length = 0;
});

describe("sharedPostgres", () => {
  it("returns one pool per connection string until it ends", async () => {
    const first = sharedPostgres({ connectionString: URL_A });
    const again = sharedPostgres({ connectionString: URL_A });

    const other = sharedPostgres({
      connectionString: "postgresql://u@host-b/db",
    });

    expect(again).toBe(first);
    expect(other).not.toBe(first);
    expect(pools.options).toHaveLength(2);

    await first.end();
    expect(sharedPostgres({ connectionString: URL_A })).not.toBe(first);
    expect(pools.options).toHaveLength(3);
  });

  it("does not share a call that brings its own pool", () => {
    const pool = { connect: vi.fn(), end: vi.fn() };

    expect(sharedPostgres({ pool })).not.toBe(sharedPostgres({ pool }));
  });
});

describe("ssl option", () => {
  it("verifies the certificate with true or an object", () => {
    createPostgres({ connectionString: URL_A, ssl: true });
    createPostgres({ connectionString: URL_A, ssl: { ca: ["pem"] } });
    createPostgres({ connectionString: URL_A, ssl: false });
    createPostgres({ connectionString: URL_A });

    expect(pools.options.map((options) => options["ssl"])).toEqual([
      { rejectUnauthorized: true },
      { rejectUnauthorized: true, ca: ["pem"] },
      false,
      undefined,
    ]);
  });
});
