import { expect, test } from "@playwright/test";

// Stark's marketing site: a static site for an iOS app with no accounts. These checks pin what
// the port from the old Bun site must keep (App Store link, contact address, icons, screenshots,
// the trailing-slash redirect, a phone-width layout) and that no page leads to the starter's /app/.

const pages = ["/", "/faq", "/privacy", "/terms", "/support"];

test("home page names the app, links the App Store and shows the plan screenshot", async ({ page }) => {
  await page.goto("/");
  await expect(page).toHaveTitle(/\bStark\b/);
  const badge = page.getByRole("link", { name: "Download on the App Store" });
  await expect(badge).toHaveAttribute("href", "https://apps.apple.com/app/id6772774783");
  await expect(page.getByRole("heading", { name: "Plan your day" })).toBeVisible();
  const shots = page.locator(".screenshots img");
  await expect(shots).toHaveCount(7);
  await expect(shots.nth(1)).toHaveAttribute("src", "/static/screenshots/02-plan.png");
  for (const img of await shots.all()) {
    // naturalWidth is 0 for an image that failed to load
    await expect.poll(() => img.evaluate((el: HTMLImageElement) => el.complete && el.naturalWidth)).toBeGreaterThan(0);
  }
});

test("every page has icons, the support address and no link into /app/", async ({ page, request }) => {
  for (const path of pages) {
    await page.goto(path);
    const hrefs = await page.locator("a[href]").evaluateAll((as) => as.map((a) => a.getAttribute("href") ?? ""));
    expect(hrefs.filter((h) => h === "/app" || h.startsWith("/app/")), path).toEqual([]);
    const html = await page.content();
    expect(html, path).not.toContain("eladio@caritos.com");
    const icons = await page.locator('link[rel="icon"], link[rel="apple-touch-icon"]').evaluateAll((ls) =>
      ls.map((l) => l.getAttribute("href") ?? ""),
    );
    expect(icons.length, path).toBe(4);
    for (const href of icons) {
      expect((await request.get(href)).status(), href).toBe(200);
    }
  }
  for (const path of ["/support", "/privacy", "/terms"]) {
    await page.goto(path);
    await expect(page.locator('a[href="mailto:support@caritos.com"]'), path).toHaveCount(1);
  }
});

test("a page asked for with a trailing slash redirects to the slash-free page", async ({ page, request }) => {
  const res = await request.get("/terms/", { maxRedirects: 0 });
  expect(res.status()).toBe(301);
  expect(res.headers()["location"]).toBe("/terms");
  await page.goto("/faq/");
  await expect(page).toHaveURL(/\/faq$/);
  await expect(page.getByRole("heading", { name: "Frequently Asked Questions" })).toBeVisible();
});

test("at phone width no page scrolls sideways; the screenshot strip scrolls inside itself", async ({ browser, baseURL }) => {
  const context = await browser.newContext({ baseURL, viewport: { width: 390, height: 844 } });
  const page = await context.newPage();
  for (const path of pages) {
    await page.goto(path);
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    expect(overflow, path).toBeLessThanOrEqual(0);
  }
  await page.goto("/");
  const strip = page.locator(".screenshots");
  const [scrollW, clientW] = await strip.evaluate((el) => [el.scrollWidth, el.clientWidth]);
  expect(scrollW).toBeGreaterThan(clientW);
  await context.close();
});
