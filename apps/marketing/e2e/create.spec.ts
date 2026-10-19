import { AxeBuilder } from "@axe-core/playwright";
import { expect, type Page, test } from "@playwright/test";
import { decodePreset, encodeDesign } from "better-supabase/preset";

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
  "Primitives",
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

  const design = await encodeDesign({
    appTables: { projects: { columns: { name: { type: "text" } } } },
  });

  const designed = await request.get(
    `/create/prompt.md?preset=saas&design=${design}`,
  );

  expect(designed.status()).toBe(200);
  expect(await designed.text()).toContain(`&design=${design}`);

  const damaged = await request.get("/create/prompt.md?design=nope");
  expect(damaged.status()).toBe(400);
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
    await expect(block(page, name)).toHaveAccessibleDescription(
      /^Required by .*comments$/u,
    );
  }

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
    `pnpm dlx better-supabase apply --preset ${code} --package apps/web`,
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
  await expect(dialog.getByTestId("screens-command")).toHaveText(
    "pnpm dlx better-supabase scaffold screens items",
  );
  await dialog.getByRole("tab", { name: "AI instructions" }).click();
  await expect(dialog.getByTestId("create-prompt-text")).toContainText(
    "&design=0",
  );
});

test("a column picked from the grouped type list keeps its kind", async ({
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
  await inspector.getByRole("textbox", { name: "Add a column" }).fill("status");
  await inspector.getByRole("combobox", { name: "Column type" }).click();
  await expect(page.getByRole("group", { name: "Choice" })).toBeVisible();
  await page.getByRole("option", { name: "Single select" }).click();
  await inspector.getByRole("button", { name: "Add", exact: true }).click();

  await expect(
    inspector.getByRole("button", { name: "Remove option Option A" }),
  ).toBeVisible();
  await inspector.getByRole("textbox", { name: "Options" }).fill("Done");
  await inspector.getByRole("textbox", { name: "Options" }).press("Enter");
  await expect(
    inspector.getByRole("button", { name: "Remove option Done" }),
  ).toBeVisible();

  const node = page.locator(".react-flow__node-table", { hasText: "items" });
  await expect(node.getByText("select?", { exact: true })).toBeVisible();

  await inspector.getByRole("tab", { name: "Options" }).click();
  await inspector.getByRole("button", { name: "Add unique key" }).click();
  await expect(
    inspector.getByRole("combobox", { name: "Unique key 1" }),
  ).toBeVisible();

  await page.reload();
  await expect(
    page
      .locator(".react-flow__node-table", { hasText: "items" })
      .getByText("select?", { exact: true }),
  ).toBeVisible();
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

/** The canvas rectangle of every table node, keyed by id. */
async function tableBoxes(page: Page) {
  return page.locator(".react-flow__node-table").evaluateAll((nodes) =>
    nodes.map((node) => {
      const rect = node.getBoundingClientRect();

      return {
        id: node.dataset["id"] ?? "",
        left: rect.left,
        top: rect.top,
        right: rect.right,
        bottom: rect.bottom,
      };
    }),
  );
}

/** The tables the table `id` covers, once it has settled. */
async function expectClearOfOthers(page: Page, id: string) {
  await expect(
    page.locator(`.react-flow__node[data-id="${id}"]`),
  ).toBeVisible();

  await expect
    .poll(async () => {
      const boxes = await tableBoxes(page);
      const own = boxes.find((box) => box.id === id);

      return boxes
        .filter(
          (box) =>
            box.id !== id &&
            own !== undefined &&
            box.left < own.right &&
            own.left < box.right &&
            box.top < own.bottom &&
            own.top < box.bottom,
        )
        .map((box) => box.id);
    })
    .toEqual([]);
}

/** An empty point on the canvas just above a table, where a new table would cover it. */
async function paneAbove(page: Page, id: string) {
  const point = await page.evaluate((tableId) => {
    const table = document.querySelector(
      `.react-flow__node[data-id="${tableId}"]`,
    );

    const rect = table?.getBoundingClientRect();

    if (rect === undefined) {
      return null;
    }

    for (let dy = 30; dy < 200; dy += 6) {
      for (let dx = 0; dx < rect.width; dx += 12) {
        const x = rect.left + dx;
        const y = rect.top - dy;

        if (document.elementFromPoint(x, y)?.matches(".react-flow__pane")) {
          return { x, y };
        }
      }
    }

    return null;
  }, id);

  expect(point).not.toBeNull();

  return point ?? { x: 0, y: 0 };
}

test("many-to-many adds a junction table and a tree references itself", async ({
  page,
}) => {
  await page.goto("/create?preset=saas");
  await expect(page.locator(".react-flow__node-table").first()).toBeVisible();

  await page
    .getByRole("toolbar", { name: "Schema tools" })
    .getByRole("button", { name: "Add table" })
    .click();
  await page.keyboard.press("Escape");

  const items = page.locator('.react-flow__node[data-id="public.items"]');
  await items.click({ position: { x: 120, y: 18 }, button: "right" });
  await page.getByRole("menuitem", { name: "Add many-to-many with…" }).click();
  await page
    .getByRole("menuitem", { name: "invitations", exact: true })
    .click();
  await expect(page.getByText("Added items_invitations.")).toBeVisible();

  const junction = page.locator(
    '.react-flow__node[data-id="public.items_invitations"]',
  );

  await expect(junction).toContainText("item_id");
  await expect(junction).toContainText("invitation_id");

  const point = await paneAbove(page, "better_supabase.organizations");
  await page.mouse.click(point.x, point.y, { button: "right" });
  await page.getByRole("menuitem", { name: "Add tree here" }).click();
  await page.keyboard.press("Escape");
  await expect(
    page.locator('.react-flow__node[data-id="public.categories"]'),
  ).toContainText("parent_id");
});

test("record features make a table a subject and show on its node", async ({
  page,
}) => {
  await page.goto("/create?preset=saas");
  await expect(page.locator(".react-flow__node-table").first()).toBeVisible();

  await page
    .getByRole("toolbar", { name: "Schema tools" })
    .getByRole("button", { name: "Add table" })
    .click();

  const inspector = page.getByRole("dialog");

  await inspector.getByRole("tab", { name: "Features" }).click();
  await inspector.getByRole("switch", { name: "Comments" }).click();
  await inspector.getByRole("switch", { name: "Manual order" }).click();

  await expect(
    inspector.getByRole("switch", {
      name: "Rows are records other blocks can reach",
    }),
  ).toBeChecked();
  await expect(
    inspector.getByRole("textbox", { name: "Subject type" }),
  ).toHaveValue("item");
  await page.keyboard.press("Escape");

  const items = page.locator('.react-flow__node[data-id="public.items"]');

  await expect(
    items.getByRole("list", { name: "items features" }),
  ).toContainText("Comments");
  await expect(items).toContainText("Manual order");
  await expect(items).toContainText("rank");
});

test("Add table here on the canvas menu adds a table that covers no other", async ({
  page,
}) => {
  await page.goto("/create?preset=saas");

  const organizations = page.locator(
    '.react-flow__node[data-id="better_supabase.organizations"]',
  );

  await expect(organizations).toBeVisible();

  // Close above a table, so the new table has to move aside.
  const point = await paneAbove(page, "better_supabase.organizations");
  await page.mouse.click(point.x, point.y, { button: "right" });

  const menu = page.getByRole("menu");
  await expect(
    menu.getByRole("menuitem", { name: "Zoom to fit" }),
  ).toBeVisible();
  await menu.getByRole("menuitem", { name: "Add table here" }).click();

  await expect(page.getByRole("dialog", { name: "items" })).toBeVisible();
  await page.keyboard.press("Escape");

  const items = page.locator('.react-flow__node[data-id="public.items"]');
  await expectClearOfOthers(page, "public.items");

  await expect(items).toBeFocused();
  await page.keyboard.press("ControlOrMeta+z");
  await expect(items).toHaveCount(0);
});

test("Add connection to on a table's menu adds a foreign key", async ({
  page,
}) => {
  await page.goto("/create?preset=saas");
  await expect(page.locator(".react-flow__node-table").first()).toBeVisible();

  await page
    .getByRole("toolbar", { name: "Schema tools" })
    .getByRole("button", { name: "Add table" })
    .click();
  await page.keyboard.press("Escape");

  const items = page.locator('.react-flow__node[data-id="public.items"]');
  await items.click({ position: { x: 120, y: 18 }, button: "right" });
  await page.getByRole("menuitem", { name: "Add connection to…" }).click();

  // A target the key can't point at says why instead of failing on click.
  await expect(
    page.getByRole("menuitem", { name: /organizations.*already references/u }),
  ).toHaveAttribute("aria-disabled", "true");

  await page
    .getByRole("menuitem", { name: "invitations", exact: true })
    .click();
  await expect(page.getByText("Added invitation_id to items.")).toBeVisible();
  await expect(items).toContainText("invitation_id");

  // A block table's menu explains why it can't hold the key.
  const invitations = page.locator(
    '.react-flow__node[data-id="better_supabase.invitations"]',
  );

  await invitations.focus();
  await page.keyboard.press("Shift+F10");
  await expect(
    page.getByRole("menuitem", { name: /Add connection to/u }),
  ).toHaveAttribute("aria-disabled", "true");
  await page.keyboard.press("Escape");
  await expect(page.getByRole("menu")).toHaveCount(0);

  await page.keyboard.press("ControlOrMeta+z");
  await expect(items).not.toContainText("invitation_id");
});

test("dragging the Table primitive onto the canvas adds a table there", async ({
  page,
}) => {
  await page.goto("/create?preset=saas");
  await expect(page.locator(".react-flow__node-table").first()).toBeVisible();
  await category(page, "Primitives").click();

  const pane = page.locator(".react-flow__pane");
  const target = { x: 640, y: 320 };

  await options(page)
    .getByRole("button", { name: /^Table/u })
    .dragTo(pane, { targetPosition: target });

  await expect(page.getByRole("dialog", { name: "items" })).toBeVisible();
  await page.keyboard.press("Escape");
  await expectClearOfOthers(page, "public.items");

  // Enter on a primitive adds it in the middle of the view.
  await options(page)
    .getByRole("button", { name: /^Lookup table/u })
    .press("Enter");
  await expect(page.getByRole("dialog", { name: "lookups" })).toBeVisible();
  await page.keyboard.press("Escape");
  await expectClearOfOthers(page, "public.lookups");
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

interface AxeFinding {
  readonly id: string;
  readonly targets: readonly string[];
}

for (const colorScheme of ["light", "dark"] as const) {
  test(`an app table's inspector has no WCAG 2.2 AA violations in the ${colorScheme} theme`, async ({
    page,
  }) => {
    await page.emulateMedia({ colorScheme });
    await page.goto("/create?preset=saas");
    await expect(page.locator(".react-flow__node-table").first()).toBeVisible();

    await page
      .getByRole("toolbar", { name: "Schema tools" })
      .getByRole("button", { name: "Add table" })
      .click();
    const inspector = page.getByRole("dialog", { name: "items" });
    await inspector.getByRole("tab", { name: "Overview" }).click();
    const remove = inspector.getByRole("button", { name: "Delete table" });
    await expect(remove).toBeVisible();

    const audit = async (): Promise<readonly AxeFinding[]> => {
      const { violations } = await new AxeBuilder({ page })
        .include('[role="dialog"]')
        .withTags(WCAG)
        .analyze();

      return violations.map((violation) => ({
        id: violation.id,
        targets: violation.nodes.map((node) => node.target.join(" ")),
      }));
    };

    expect(await audit()).toEqual([]);

    // The hover tint is darker, so the button's contrast is checked there too,
    // once its color transition has finished.
    await remove.hover();
    await remove.evaluate(async (element) => {
      await Promise.all(
        element.getAnimations().map(async (animation) => animation.finished),
      );
    });
    expect(await audit()).toEqual([]);
  });
}

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

test("the Changes tab compares the design with the one in the link", async ({
  page,
}) => {
  const design = await encodeDesign({
    appTables: {
      articles: {
        columns: { title: { type: "text" }, pinned: { type: "boolean" } },
      },
    },
  });

  await page.goto(`/create?preset=saas&design=${design}`);
  const articles = page.locator('.react-flow__node[data-id="public.articles"]');
  await expect(articles).toBeVisible();

  let dialog = await openCode(page);
  await dialog.getByRole("tab", { name: "Changes" }).click();
  await expect(dialog.getByText("No changes yet")).toBeVisible();
  await dialog.getByRole("button", { name: "Edit the canvas" }).click();
  await expect(dialog).toBeHidden();

  await articles.focus();
  await page.keyboard.press("Enter");
  const inspector = page.getByRole("dialog", { name: "articles" });
  await inspector.getByRole("tab", { name: "Columns" }).click();
  await inspector.getByRole("button", { name: "Delete pinned" }).click();
  await page.keyboard.press("Escape");
  await expect(inspector).toBeHidden();

  dialog = await openCode(page);
  await dialog.getByRole("tab", { name: "Changes" }).click();
  const changes = dialog.getByRole("list", { name: "Changes" });
  await expect(changes.getByRole("listitem").first()).toContainText(
    "BreakingDrops articles.pinned and its values.",
  );
  await expect(
    dialog.getByRole("list", {
      name: "Steps for: Drops articles.pinned and its values.",
    }),
  ).toBeVisible();
  await expect(dialog.getByText("1 breaking change")).toBeVisible();

  const { violations } = await new AxeBuilder({ page })
    .include('[role="dialog"]')
    .withTags(WCAG)
    .analyze();

  expect(violations.map((violation) => violation.id)).toEqual([]);
});

test("a template draws its tables, and the Data tab shows sample rows", async ({
  page,
}) => {
  await page.goto("/create?preset=saas");
  await page.getByRole("button", { name: "Start from a template" }).click();
  const picker = page.getByRole("dialog", { name: "Start from a template" });
  await picker.getByRole("button", { name: /^Projects and tasks/u }).click();
  await expect(picker).toBeHidden();
  await expect(page).toHaveURL(/&design=0[\w-]+$/u);

  const tasks = page.locator('.react-flow__node[data-id="public.tasks"]');
  await expect(tasks).toBeVisible();

  await tasks.click({ position: { x: 120, y: 18 } });
  const inspector = page.getByRole("dialog", { name: "tasks" });
  await inspector.getByRole("tab", { name: "Data" }).click();
  await expect(inspector.getByRole("cell", { name: "Task 1" })).toBeVisible();

  await page.keyboard.press("Escape");
  await page.getByRole("button", { name: "Undo" }).first().click();
  await expect(tasks).toHaveCount(0);
});

test("a rollup added in the inspector shows as a computed row on the table", async ({
  page,
}) => {
  await page.goto("/create?preset=saas");
  await page.getByRole("button", { name: "Start from a template" }).click();
  const picker = page.getByRole("dialog", { name: "Start from a template" });
  await picker.getByRole("button", { name: /^Projects and tasks/u }).click();
  await expect(picker).toBeHidden();

  const projects = page.locator('.react-flow__node[data-id="public.projects"]');
  await projects.click({ position: { x: 120, y: 18 } });
  const inspector = page.getByRole("dialog", { name: "projects" });
  await inspector.getByRole("tab", { name: "Columns" }).click();

  const computed = inspector.getByRole("region", { name: "Computed" });
  await expect(computed.getByText("No computed columns yet")).toBeVisible();
  const before = page.url();
  await computed.getByRole("button", { name: "Add rollup" }).click();

  const list = computed.getByRole("list", {
    name: "projects computed columns",
  });

  await expect(
    list.getByRole("textbox", { name: "tasks_count name" }),
  ).toHaveValue("tasks_count");
  await expect.poll(() => page.url()).not.toBe(before);

  const { violations } = await new AxeBuilder({ page })
    .include('[role="dialog"]')
    .withTags(WCAG)
    .analyze();

  expect(violations.map((violation) => violation.id)).toEqual([]);

  await page.keyboard.press("Escape");
  await expect(inspector).toBeHidden();
  await expect(projects.getByText("tasks_count")).toBeVisible();
  await expect(
    projects.getByRole("listitem").filter({ hasText: "tasks_count" }),
  ).toHaveAttribute("title", /count of tasks/u);
});
