import { AxeBuilder } from "@axe-core/playwright";
import { expect, type Page, test } from "@playwright/test";
import { decodePreset } from "better-supabase/preset";

const WCAG = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"];

function block(page: Page, name: string) {
  return page
    .getByLabel("Options", { exact: true })
    .locator(`input[name="block"][value="${name}"]`);
}

async function openCode(page: Page) {
  await page
    .getByLabel("Options", { exact: true })
    .getByRole("button", { name: "Get code" })
    .click();

  return page.getByRole("dialog", { name: "Get the code" });
}

test("ticking comments switches on tenant and access, and the URL keeps the selection", async ({
  page,
}) => {
  await page.goto("/create?preset=minimal");

  await expect(block(page, "comments")).not.toBeChecked();
  await expect(block(page, "tenant")).not.toBeChecked();

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
  await expect(block(page, "comments")).toBeChecked();
  await expect(block(page, "access")).toBeDisabled();
});

test("the monorepo option keeps the package in the URL and the commands", async ({
  page,
}) => {
  await page.goto("/create?preset=saas");

  await page.getByLabel("Options", { exact: true }).getByRole("switch").click();
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
  await expect(
    page.getByLabel("Options", { exact: true }).getByRole("switch"),
  ).toBeChecked();
  await expect(
    page.getByLabel("Options", { exact: true }).getByLabel("Package directory"),
  ).toHaveValue("apps/web");
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
