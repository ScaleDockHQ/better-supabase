import { describe, expect, it, vi } from "vitest";

import { refreshSession } from "../../src/auth/refresh.ts";

const answer = (token: string) =>
  Response.json({
    access_token: `a-${token}`,
    refresh_token: `r-${token}`,
    expires_in: 3600,
  });

describe("refreshSession", () => {
  it("keeps refreshes of the same token apart per project", async () => {
    const fetch = vi.fn<typeof globalThis.fetch>(async () => answer("1"));
    const options = { publishableKey: "pk", fetch };
    await refreshSession("same-token", { ...options, url: "https://a.test" });
    await refreshSession("same-token", { ...options, url: "https://b.test" });
    expect(fetch).toHaveBeenCalledTimes(2);
    const again = await refreshSession("same-token", {
      ...options,
      url: "https://a.test",
    });
    expect(again).toMatchObject({ ok: true, shared: true });
    expect(fetch).toHaveBeenCalledTimes(2);
  });

  it("reuses a slow refresh for the whole window after it finishes", async () => {
    let clock = 1_000_000;
    const fetch = vi.fn<typeof globalThis.fetch>(async () => {
      clock += 8000;
      return answer("slow");
    });
    const options = {
      url: "https://slow.test",
      publishableKey: "pk",
      fetch,
      now: () => clock,
    };
    await refreshSession("slow-token", options);
    clock += 5000;
    expect(await refreshSession("slow-token", options)).toMatchObject({
      shared: true,
    });
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it("drops the oldest reused refresh past its cap", async () => {
    const fetch = vi.fn<typeof globalThis.fetch>(async () => answer("n"));
    const options = { url: "https://cap.test", publishableKey: "pk", fetch };
    for (let index = 0; index <= 1000; index++)
      await refreshSession(`cap-${String(index)}`, options);
    expect(fetch).toHaveBeenCalledTimes(1001);
    await refreshSession("cap-1000", options);
    expect(fetch).toHaveBeenCalledTimes(1001);
    await refreshSession("cap-0", options);
    expect(fetch).toHaveBeenCalledTimes(1002);
  });
});
