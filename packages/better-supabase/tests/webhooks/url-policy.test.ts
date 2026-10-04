import { describe, expect, it, vi } from "vitest";

import { isPublicAddress, publicUrl } from "../../src/webhooks/index.ts";

describe("isPublicAddress", () => {
  it.each([
    "8.8.8.8",
    "1.1.1.1",
    "2606:4700:4700::1111",
    "[2606:4700:4700::1111]",
    "::ffff:8.8.8.8",
    "64:ff9b::808:808",
  ])("accepts %s", (address) => {
    expect(isPublicAddress(address)).toBe(true);
  });

  it.each([
    "0.0.0.0",
    "10.1.2.3",
    "100.64.0.1",
    "127.0.0.1",
    "169.254.169.254",
    "172.16.0.1",
    "172.31.255.255",
    "192.0.0.8",
    "192.0.2.1",
    "192.168.1.1",
    "198.18.0.1",
    "224.0.0.1",
    "255.255.255.255",
    "::",
    "::1",
    "::ffff:127.0.0.1",
    "::ffff:7f00:1",
    "64:ff9b::a00:1",
    "fc00::1",
    "fd12:3456::1",
    "fe80::1%en0",
    "ff02::1",
    "2001:db8::1",
    "100::1",
    "example.com",
    "1.2.3",
    "256.1.1.1",
    "1:2:3:4:5:6:7:8:9",
    "1::2::3",
    "::ffff:1.2.3",
  ])("rejects %s", (address) => {
    expect(isPublicAddress(address)).toBe(false);
  });
});

describe("publicUrl", () => {
  const dns: Record<string, readonly string[]> = {
    "hooks.example.com": [
      "93.184.215.14",
      "2606:2800:21f:cb07:6820:80da:af6b:8b2c",
    ],
    "rebind.example.com": ["93.184.215.14", "10.0.0.5"],
    "empty.example.com": [],
  };
  const allow = publicUrl({ resolve: async (host) => dns[host] ?? [] });
  const check = (url: string) => allow(new URL(url));

  it("allows HTTPS hosts that resolve only to public addresses", async () => {
    expect(await check("https://hooks.example.com/in")).toBe(true);
    expect(await check("https://8.8.8.8/in")).toBe(true);
  });

  it("rejects private, local and unresolvable targets", async () => {
    expect(await check("https://rebind.example.com/in")).toBe(false);
    expect(await check("https://empty.example.com/in")).toBe(false);
    expect(await check("https://127.0.0.1/in")).toBe(false);
    expect(await check("https://[::1]/in")).toBe(false);
    expect(await check("https://localhost/in")).toBe(false);
    expect(await check("https://db.internal/in")).toBe(false);
    expect(await check("https://intranet/in")).toBe(false);
  });

  it("rejects plain HTTP and credentials in the URL", async () => {
    expect(await check("http://hooks.example.com/in")).toBe(false);
    expect(await check("https://user:pass@hooks.example.com/in")).toBe(false);
    const http = publicUrl({
      resolve: async (host) => dns[host] ?? [],
      allowHttp: true,
    });
    expect(await http(new URL("http://hooks.example.com/in"))).toBe(true);
    expect(await http(new URL("ftp://hooks.example.com/in"))).toBe(false);
  });

  it("trusts allowHosts without any check", async () => {
    const trusted = publicUrl({
      resolve: false,
      allowHosts: ["Receiver.Internal"],
    });
    expect(await trusted(new URL("http://receiver.internal:8080/in"))).toBe(
      true,
    );
    expect(await trusted(new URL("https://unknown.example.com/in"))).toBe(true);
    expect(await trusted(new URL("https://localhost/in"))).toBe(false);
  });

  it("uses node:dns by default", async () => {
    await expect(
      publicUrl()(new URL("https://hooks.example.invalid/in")),
    ).rejects.toThrow(/ENOTFOUND|EAI_AGAIN|getaddrinfo/);
    expect(await publicUrl()(new URL("https://127.0.0.1/in"))).toBe(false);
  });

  it("needs a resolver on runtimes without node:dns", () => {
    const builtin = vi
      .spyOn(process, "getBuiltinModule")
      .mockImplementation(() => undefined);
    try {
      expect(() => publicUrl()).toThrow("needs a resolve option");
      expect(publicUrl({ resolve: false })).toBeTypeOf("function");
    } finally {
      builtin.mockRestore();
    }
  });
});
