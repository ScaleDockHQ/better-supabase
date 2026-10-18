import { AxeBuilder } from "@axe-core/playwright";
import { expect, type Page, test } from "@playwright/test";
import { decodePreset } from "better-supabase/preset";

const WCAG = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"];

function block(page: Page, name: string) {
  return page
    .getByLabel("Options", { exact: true })
    .locator(`input[name="block"][value="${name}"]`);
}

function options(page: Page) {
  return page.getByLabel("Options", { exact: true });
}

/** A collapsible in the options panel: a section like Stack, or a block category. */
function category(page: Page, name: string) {
  return options(page).getByRole("button", {
    name: new RegExp(`^${name}`, "u"),
  });
}

async function openCode(page: Page) {
  await page
    .getByLabel("Options", { exact: true })
    .getByRole("button", { name: "Get code" })
    .click();

  return page.getByRole("dialog", { name: "Get the code" });
}

const SECTIONS = [
  "Stack",
  "Auth and permissions",
  "Conventions",
  "Integrations",
  "Blocks",
] as const;

test("the page opens on SaaS with only the preset section open", async ({
  page,
}) => {
  await page.goto("/create");

  await expect(
    options(page).getByRole("combobox", { name: "Preset" }),
  ).toContainText("SaaS");
  await expect(category(page, "Preset")).toHaveAttribute(
    "aria-expanded",
    "true",
  );
  await expect(category(page, "Preset")).toContainText("SaaS");
  await expect(category(page, "Stack")).toContainText("Next.js, web");
  await expect(category(page, "Blocks")).toContainText(/\d+ installed/u);
  await expect(
    options(page).getByRole("button", { name: "Copy AI instructions" }),
  ).toBeVisible();

  for (const name of SECTIONS) {
    const trigger = category(page, name);
    await expect(trigger).toHaveAttribute("aria-expanded", "false");
    await trigger.click();
    await expect(trigger).toHaveAttribute("aria-expanded", "true");
    await trigger.click();
    await expect(trigger).toHaveAttribute("aria-expanded", "false");
  }

  await category(page, "Preset").click();
  await expect(category(page, "Preset")).toHaveAttribute(
    "aria-expanded",
    "false",
  );
});

test("the AI instructions add the UI when Include UI is on", async ({
  page,
}) => {
  await page.goto("/create?preset=saas");
  const dialog = await openCode(page);
  await dialog.getByRole("tab", { name: "AI instructions" }).click();

  const prompt = dialog.getByTestId("create-prompt-text");
  await expect(prompt).toContainText("# Install better-supabase");
  await expect(prompt).not.toContainText("/recipes/");

  await dialog.getByRole("switch", { name: "Include UI" }).click();
  await expect(prompt).toContainText("## UI");
  await expect(prompt).toContainText(/\/recipes\/[a-z-]+\.md/u);
});

test("/create/prompt.md returns the AI instructions as Markdown", async ({
  request,
}) => {
  const response = await request.get("/create/prompt.md?preset=saas&ui=1");
  expect(response.status()).toBe(200);
  expect(response.headers()["content-type"]).toBe(
    "text/markdown; charset=utf-8",
  );
  const text = await response.text();
  expect(text).toMatch(/^# Install better-supabase: \d+ blocks on Next\.js/u);
  expect(text).toMatch(/\/recipes\/[a-z-]+\.md/u);

  const bad = await request.get("/create/prompt.md?manager=deno");
  expect(bad.status()).toBe(400);
});

test("ticking comments switches on tenant and access, and the URL keeps the selection", async ({
  page,
}) => {
  await page.goto("/create?preset=minimal");

  await category(page, "Blocks").click();
  await expect(block(page, "comments")).not.toBeChecked();
  await expect(block(page, "tenant")).not.toBeChecked();

  // Each category is a collapsible; one with nothing selected starts closed.
  await expect(category(page, "Collaboration")).toHaveAttribute(
    "aria-expanded",
    "false",
  );
  await expect(category(page, "Collaboration")).toContainText(/0 of \d+/u);
  await category(page, "Collaboration").click();
  await block(page, "comments").check();

  await expect(block(page, "comments")).toBeChecked();

  for (const name of ["tenant", "access"]) {
    await expect(block(page, name)).toBeChecked();
    await expect(block(page, name)).toBeDisabled();
  }

  await expect(page.getByText("Required by comments").first()).toBeVisible();
  await expect(page).toHaveURL(/\/create\?preset=[1-9A-Z][0-9A-Za-z]+$/u);
  const code = new URL(page.url()).searchParams.get("preset") ?? "";

  const dialog = await openCode(page);
  await expect(dialog.getByTestId("install-command")).toHaveText(
    `pnpm dlx better-supabase init --preset ${code}`,
  );

  await dialog.getByRole("button", { name: "npm", exact: true }).click();
  await expect(dialog.getByTestId("install-command")).toHaveText(
    `npx better-supabase init --preset ${code}`,
  );

  await dialog.getByRole("tab", { name: "Existing project" }).click();
  await expect(dialog.getByTestId("apply-command")).toHaveText(
    `npx better-supabase apply --preset ${code}`,
  );

  expect(decodePreset(code).preset.blocks.toSorted()).toEqual([
    "comments",
    "profiles",
  ]);

  // The code alone restores the same selection.
  await page.goto(`/create?preset=${code}`);
  await category(page, "Blocks").click();
  await expect(block(page, "comments")).toBeChecked();
  await expect(block(page, "access")).toBeDisabled();
});

test("the monorepo option keeps the package in the URL and the commands", async ({
  page,
}) => {
  await page.goto("/create?preset=saas");

  await options(page).getByRole("button", { name: "Conventions" }).click();
  await options(page).getByRole("switch").click();
  await expect(page).toHaveURL(/&package=apps\/web$/u);
  const code = new URL(page.url()).searchParams.get("preset") ?? "";

  const dialog = await openCode(page);
  await expect(dialog.getByTestId("install-command")).toHaveText(
    `pnpm dlx better-supabase init --preset ${code} --package apps/web`,
  );
  await expect(
    dialog.getByText("apps/web/better-supabase.config.ts").first(),
  ).toBeVisible();

  await dialog.getByRole("tab", { name: "Existing project" }).click();
  await expect(dialog.getByTestId("apply-command")).toHaveText(
    `pnpm dlx better-supabase apply --preset ${code} --config apps/web/better-supabase.config.ts`,
  );

  // A reload restores the package from the URL.
  await page.reload();
  await options(page).getByRole("button", { name: "Conventions" }).click();
  await expect(
    page.getByLabel("Options", { exact: true }).getByRole("switch"),
  ).toBeChecked();
  await expect(
    page.getByLabel("Options", { exact: true }).getByLabel("Package directory"),
  ).toHaveValue("apps/web");
});

test("a framework turns off the platforms it can't build", async ({ page }) => {
  await page.goto("/create?preset=saas");
  await category(page, "Stack").click();

  const platforms = options(page).getByRole("group", { name: "Platforms" });
  await expect(
    platforms.getByRole("button", { name: "Native", exact: true }),
  ).toBeDisabled();

  await options(page).getByLabel("Framework").click();
  await page.getByRole("option", { name: "Expo" }).click();

  await expect(
    platforms.getByRole("button", { name: "Web", exact: true }),
  ).toBeDisabled();
  await expect(
    platforms.getByRole("button", { name: "Native", exact: true }),
  ).toHaveAttribute("aria-pressed", "true");
  await expect(
    options(page).getByText("These choices conflict"),
  ).not.toBeAttached();
});

test("the framework's own integration is checked and locked", async ({
  page,
}) => {
  await page.goto("/create?preset=saas");
  await options(page).getByRole("button", { name: "Integrations" }).click();

  const next = options(page).getByRole("checkbox", { name: /^Next\.js/u });
  await expect(next).toBeChecked();
  await expect(next).toBeDisabled();
  await expect(options(page).getByText("Added for Next.js")).toBeVisible();
  await expect(options(page).getByText("Needed by Next.js")).toBeVisible();

  const hono = options(page).getByRole("checkbox", { name: /^Hono/u });
  await expect(hono).not.toBeChecked();
  await hono.click();
  await expect(hono).toBeChecked();
});

test("the preset select applies a preset and shows Custom after a change", async ({
  page,
}) => {
  await page.goto("/create?preset=saas");

  const preset = options(page).getByRole("combobox", { name: "Preset" });
  await expect(preset).toContainText("SaaS");

  await preset.click();
  await page.getByRole("option", { name: /^CRM/u }).click();
  await expect(preset).toContainText("CRM");
  await expect(category(page, "Preset")).toContainText("CRM");
  await category(page, "Blocks").click();
  await expect(block(page, "pipelines")).toBeChecked();

  await category(page, "Scheduling").click();
  await block(page, "bookings").check();
  await expect(preset).toContainText("Custom");
});

test("PermDock is an optional auth choice kept in the URL", async ({
  page,
}) => {
  await page.goto("/create?preset=saas");
  await category(page, "Auth and permissions").click();

  await options(page)
    .getByRole("radio", { name: /^PermDock/u })
    .click();
  await expect(category(page, "Auth and permissions")).toContainText(
    "PermDock",
  );
  await expect(page).toHaveURL(/&authz=permdock$/u);
  await expect(page.getByText(/^\d+ tables, \d+ relations$/u)).toBeVisible();
  await expect(page.getByText("Placeholder access functions")).toBeVisible();

  const dialog = await openCode(page);
  await dialog.getByRole("tab", { name: "Migrations" }).click();
  await expect(dialog.getByText("Placeholder access functions")).toBeVisible();
  await dialog.getByRole("tab", { name: "Config" }).click();
  await expect(dialog.getByTestId("permdock-install")).toHaveText(
    "pnpm add permdock",
  );
  await expect(
    dialog.getByText("authorization: authorizationProvider({"),
  ).toBeVisible();

  await page.reload();
  await category(page, "Auth and permissions").click();
  await expect(
    options(page).getByRole("radio", { name: /^PermDock/u }),
  ).toBeChecked();

  await options(page)
    .getByRole("radio", { name: /^Built-in roles/u })
    .click();
  await expect(page).not.toHaveURL(/authz=/u);
});

test("the diagram lists the tables and asks for a block when there are none", async ({
  page,
}) => {
  await page.goto("/create?preset=saas");

  await expect(page.getByText(/^\d+ tables, \d+ relations$/u)).toBeVisible();
  await expect(page.locator(".react-flow__node-table").first()).toBeVisible();
  await expect(
    page.getByRole("heading", { name: "Tables in this schema" }),
  ).toBeAttached();

  await page.goto("/create?preset=minimal");
  await category(page, "Blocks").click();
  await block(page, "profiles").uncheck();

  await expect(page.getByText("Pick a block")).toBeVisible();
  await page
    .getByRole("button", { name: "Start from the SaaS preset" })
    .click();
  await expect(page.getByText(/^\d+ tables, \d+ relations$/u)).toBeVisible();
});

test("the code dialog has no WCAG 2.2 AA violations", async ({ page }) => {
  await page.goto("/create?preset=saas");
  await openCode(page);

  const { violations } = await new AxeBuilder({ page })
    .withTags(WCAG)
    .analyze();

  expect(
    violations.map((violation) => ({
      id: violation.id,
      targets: violation.nodes.map((node) => node.target.join(" ")),
    })),
  ).toEqual([]);
});
