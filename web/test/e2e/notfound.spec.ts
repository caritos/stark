import { expect, test } from "@playwright/test";

test("unknown URL shows 404 page", async ({ page }) => {
  const res = await page.request.get("/nope");
  expect(res.status()).toBe(404);
  expect(res.headers()["content-type"]).toContain("text/html");
  expect(await res.text()).toContain("Page not found");

  const nav = await page.goto("/nope");
  expect(nav?.status()).toBe(404);
  await expect(page.getByText("Page not found").first()).toBeVisible();
});

test("public pages are served", async ({ request }) => {
  for (const path of ["/", "/faq", "/privacy", "/terms", "/support"]) {
    const res = await request.get(path);
    expect(res.status(), path).toBe(200);
    expect(res.headers()["content-type"], path).toContain("text/html");
    expect((await res.text()).replace(/<[^>]*>/g, "").trim().length, path).toBeGreaterThan(50);
  }
});
