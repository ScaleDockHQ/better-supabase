import { Client } from "pg";

export interface PgConnection {
  readonly queryable: {
    query(text: string): Promise<{ rows: Record<string, unknown>[] }>;
  };
  close(): Promise<void>;
}

/** A `pg` connection to the local stack, or undefined when it is not running. */
export async function openPg(url: string): Promise<PgConnection | undefined> {
  const client = new Client({ connectionString: url });
  try {
    await client.connect();
    await client.query("select 1");
  } catch {
    await client.end().catch(() => undefined);
    return undefined;
  }
  return { queryable: client, close: () => client.end() };
}
