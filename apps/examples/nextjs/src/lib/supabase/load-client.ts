import type { bsb } from "./client";

/**
 * The browser client, loaded on first use. A form that calls Auth from the
 * browser (sign-up) awaits it on submit, so its route ships no data engine.
 */
export async function loadBrowserClient(): Promise<typeof bsb> {
  const { bsb: client } = await import("./client");

  return client;
}
