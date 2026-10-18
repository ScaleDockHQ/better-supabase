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
  await expect(page.locator(".react-flow__node-table").first()).toBeVisible();
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

  await expect(page.locator(".react-flow__node-table").first()).toBeVisible();
  await expect(
    page.getByRole("heading", {
      name: /^Tables in this schema: \d+ tables, \d+ relations$/u,
    }),
  ).toBeAttached();

  await page.goto("/create?preset=minimal");
  await category(page, "Blocks").click();
  await block(page, "profiles").uncheck();

  await expect(page.getByText("Pick a block")).toBeVisible();
  await page
    .getByRole("button", { name: "Start from the SaaS preset" })
    .click();
  await expect(page.locator(".react-flow__node-table").first()).toBeVisible();
});

test("a table drawn on the canvas travels in the design code", async ({
  page,
}) => {
  await page.goto("/create?preset=saas");
  await expect(page.locator(".react-flow__node-table").first()).toBeVisible();

  await page
    .getByRole("toolbar", { name: "Schema tools" })
    .getByRole("button", { name: "Add table" })
    .click();
  const inspector = page.getByRole("dialog", { name: "items" });
  await inspector.getByRole("tab", { name: "Columns" }).click();
  await inspector.getByRole("textbox", { name: "Add a column" }).fill("title");
  await inspector.getByRole("button", { name: "Add", exact: true }).click();
  await expect(page).toHaveURL(/&design=0[\w-]+$/u);

  const { violations } = await new AxeBuilder({ page })
    .withTags(WCAG)
    .analyze();

  expect(violations.map((violation) => violation.id)).toEqual([]);

  // The link alone restores the table.
  await page.reload();
  await expect(
    page.locator(".react-flow__node-table", { hasText: "items" }),
  ).toBeVisible();

  const dialog = await openCode(page);
  await expect(dialog.getByTestId("install-command")).toHaveText(
    /^pnpm dlx better-supabase init --preset "https:\/\/bettersupabase\.com\/create\?preset=\w+&design=0[\w-]+"$/u,
  );
  await expect(dialog.getByText("appTables").first()).toBeVisible();
  await dialog.getByRole("tab", { name: "AI instructions" }).click();
  await expect(dialog.getByTestId("create-prompt-text")).toContainText(
    "&design=0",
  );
});

test("a click on a table opens the inspector, and a drag doesn't", async ({
  page,
}) => {
  await page.goto("/create?preset=saas");

  const table = page.locator(
    '.react-flow__node[data-id="better_supabase.organizations"]',
  );

  await expect(table).toBeVisible();

  await table.click({ position: { x: 120, y: 18 } });
  const inspector = page.getByRole("dialog", { name: "organizations" });
  await expect(inspector).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(inspector).toBeHidden();

  const box = await table.boundingBox();
  expect(box).not.toBeNull();
  const start = { x: (box?.x ?? 0) + 120, y: (box?.y ?? 0) + 18 };
  await page.mouse.move(start.x, start.y);
  await page.mouse.down();
  await page.mouse.move(start.x + 60, start.y + 40, { steps: 8 });
  await page.mouse.up();
  await expect(page.getByRole("dialog")).toHaveCount(0);

  await table.focus();
  await page.keyboard.press("Enter");
  await expect(inspector).toBeVisible();
});

test("dragging a group moves its tables, and Undo moves them back", async ({
  page,
}) => {
  await page.goto("/create?preset=saas");

  const group = page.locator(
    '.react-flow__node[data-id="group:organizations"]',
  );

  const member = page.locator(
    '.react-flow__node[data-id="better_supabase.organizations"]',
  );

  await expect(member).toBeVisible();

  const before = await member.boundingBox();
  const box = await group.boundingBox();
  expect(box).not.toBeNull();

  const start = {
    x: (box?.x ?? 0) + (box?.width ?? 0) - 30,
    y: (box?.y ?? 0) + 12,
  };

  await page.mouse.move(start.x, start.y);
  await page.mouse.down();
  await page.mouse.move(start.x + 100, start.y + 60, { steps: 10 });
  await page.mouse.up();

  await expect
    .poll(async () => (await member.boundingBox())?.x)
    .toBeGreaterThan((before?.x ?? 0) + 50);
  await expect(page.getByRole("dialog")).toHaveCount(0);

  await page.keyboard.press("ControlOrMeta+z");
  await expect
    .poll(async () => (await member.boundingBox())?.x)
    .toBeCloseTo(before?.x ?? 0, 0);
});

test("dropping a block on the canvas switches it on, once", async ({
  page,
}) => {
  await page.goto("/create?preset=saas");
  await expect(page.locator(".react-flow__node-table").first()).toBeVisible();
  await category(page, "Blocks").click();
  // A category with an installed block starts open.
  const collaboration = category(page, "Collaboration");

  if ((await collaboration.getAttribute("aria-expanded")) !== "true") {
    await collaboration.click();
  }

  const row = options(page).locator(
    'label:has(input[name="block"][value="comments"])',
  );

  await expect(block(page, "comments")).not.toBeChecked();
  await row.dragTo(page.locator(".react-flow__pane"), {
    targetPosition: { x: 600, y: 300 },
  });

  await expect(block(page, "comments")).toBeChecked();
  await expect(
    page.locator('.react-flow__node[data-id="better_supabase.comments"]'),
  ).toBeVisible();

  await row.dragTo(page.locator(".react-flow__pane"), {
    targetPosition: { x: 400, y: 200 },
  });
  await expect(
    page.getByText("The comments block is already on the canvas."),
  ).toBeVisible();
});

test("soft references are drawn by default", async ({ page }) => {
  await page.goto("/create?preset=saas");
  await expect(page.locator(".react-flow__node-table").first()).toBeVisible();

  const toggle = page
    .getByRole("toolbar", { name: "Schema tools" })
    .getByRole("button", { name: "Hide soft references" });

  await expect(toggle).toHaveAttribute("aria-pressed", "false");

  const soft = page.locator(
    '.react-flow__edge path[class*="stroke-dasharray"]',
  );

  await expect(soft.first()).toBeAttached();

  await toggle.click();
  await expect(soft).toHaveCount(0);
});

test.describe("on a phone", () => {
  test.use({
    viewport: { width: 390, height: 844 },
    hasTouch: true,
    isMobile: true,
  });

  test("the toolbar collapses and the inspector takes the full width", async ({
    page,
  }) => {
    await page.goto("/create?preset=saas");
    await expect(page.locator(".react-flow__node-table").first()).toBeVisible();

    const toolbar = page.getByRole("toolbar", { name: "Schema tools" });
    await expect(toolbar.getByRole("group", { name: "View" })).toBeHidden();
    await toolbar.getByRole("button", { name: "More tools" }).click();
    await expect(
      page.getByRole("menuitem", { name: "Tidy layout" }),
    ).toBeVisible();
    await page.keyboard.press("Escape");

    await toolbar.getByRole("button", { name: "Add table" }).click();
    const inspector = page.getByRole("dialog", { name: "items" });
    await expect(inspector).toBeVisible();

    await expect
      .poll(async () => (await inspector.boundingBox())?.width)
      .toBe(390);
  });

  test("the code panels stay inside the code dialog", async ({ page }) => {
    await page.goto("/create?preset=saas");
    await page.getByRole("button", { name: "Get code" }).click();

    const dialog = page.getByRole("dialog", { name: "Get the code" });

    const panel = dialog.getByRole("region", {
      name: "better-supabase.config.ts",
    });

    await expect(panel).toBeVisible();

    const outer = await dialog.boundingBox();
    const inner = await panel.boundingBox();
    expect(inner?.x ?? 0).toBeGreaterThanOrEqual(outer?.x ?? 0);
    expect((inner?.x ?? 0) + (inner?.width ?? 0)).toBeLessThanOrEqual(
      (outer?.x ?? 0) + (outer?.width ?? 0),
    );
  });
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
