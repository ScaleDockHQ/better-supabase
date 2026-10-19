import { AxeBuilder } from "@axe-core/playwright";
import { expect, type Page, test } from "@playwright/test";

const WCAG = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"];

const REF = "abcdefghijklmnopqrst";

const project = {
  id: REF,
  ref: REF,
  name: "acme-prod",
  organization_slug: "acme",
  region: "eu-central-1",
  status: "ACTIVE_HEALTHY",
};

async function openDeploy(page: Page) {
  await page.goto("/create");
  await page
    .getByLabel("Options", { exact: true })
    .getByRole("button", { name: "Deploy to Supabase" })
    .click();

  return page.getByRole("dialog", { name: "Deploy to Supabase" });
}

test("without a session the dialog asks to connect Supabase", async ({
  page,
}) => {
  await page.route("**/create/supabase/projects", (route) =>
    route.fulfill({
      status: 401,
      json: { error: "connect", message: "Connect Supabase first." },
    }),
  );

  const dialog = await openDeploy(page);
  const connect = dialog.getByRole("button", { name: "Connect Supabase" });

  await expect(connect).toBeVisible();
  await expect(dialog.locator('input[name="return"]')).toHaveValue(
    /^\/create\?/u,
  );

  const results = await new AxeBuilder({ page })
    .include('[role="dialog"]')
    .withTags(WCAG)
    .analyze();

  expect(results.violations).toEqual([]);
});

test("deploys into an existing project after the confirm", async ({ page }) => {
  let deployed: unknown;

  await page.route("**/create/supabase/projects", (route) =>
    route.fulfill({
      json: {
        organizations: [{ id: "1", slug: "acme", name: "Acme" }],
        projects: [project],
      },
    }),
  );
  await page.route(`**/create/supabase/projects/${REF}`, (route) =>
    route.fulfill({ json: { project, ready: true, publicTables: 2 } }),
  );
  await page.route("**/create/supabase/deploy", (route) => {
    deployed = route.request().postDataJSON();

    return route.fulfill({
      json: {
        ref: REF,
        migration: "better_supabase_blocks",
        lints: [
          {
            name: "function_search_path_mutable",
            title: "Function Search Path Mutable",
            level: "WARN",
          },
        ],
      },
    });
  });

  const dialog = await openDeploy(page);

  await dialog.getByRole("combobox", { name: "Project" }).click();
  await page.getByRole("option", { name: "acme-prod" }).click();

  await expect(
    dialog.getByText("The public schema has 2 tables"),
  ).toBeVisible();

  const deploy = dialog.getByRole("button", { name: "Deploy", exact: true });

  await expect(deploy).toBeDisabled();
  await dialog
    .getByRole("checkbox", { name: "Deploy into this project anyway" })
    .check();
  await deploy.click();

  await expect(dialog.getByText(`Deployed to ${REF}`)).toBeVisible();
  await expect(dialog.getByText("Function Search Path Mutable")).toBeVisible();
  await expect(dialog.getByTestId("deploy-install")).toBeVisible();
  expect(deployed).toMatchObject({ ref: REF, confirm: true });

  const results = await new AxeBuilder({ page })
    .include('[role="dialog"]')
    .withTags(WCAG)
    .analyze();

  expect(results.violations).toEqual([]);
});
