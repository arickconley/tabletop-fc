import assert from "node:assert/strict";
import { createServer } from "node:http";
import { readFile, readdir, mkdir, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { chromium } from "playwright";
import * as Game from "../src/game.js";

const files = new Map();
for (const entry of await readdir("dist", { recursive: true, withFileTypes: true })) {
  if (entry.isFile()) {
    const path = `${entry.parentPath}/${entry.name}`;
    files.set(path.replace(/^dist\//, ""), await readFile(path));
  }
}
const types = { html: "text/html", js: "text/javascript", css: "text/css", webmanifest: "application/manifest+json", png: "image/png", svg: "image/svg+xml", ttf: "font/ttf", txt: "text/plain" };
let online = true;
let revision = 1;
const server = createServer((request, response) => {
  if (!online) return request.socket.destroy();
  const pathname = new URL(request.url, "http://localhost").pathname;
  const file = pathname.replace(/^\/(?:tabletop-fc\/)?/, "") || "index.html";
  let content = files.get(file);
  if (!content) return response.writeHead(404).end("Not found");
  if (revision === 2 && file === "sw.js") {
    content = content.toString().replace(/CACHE_PREFIX \+ "[a-f0-9]+"/, 'CACHE_PREFIX + "test-update"');
  }
  if (revision === 2 && file === "index.html") {
    content = content.toString().replace("<head>", '<head><meta name="test-version" content="2">');
  }
  response.writeHead(200, { "Content-Type": types[file.split(".").pop()] || "text/plain", "Cache-Control": "no-store" });
  response.end(content);
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
const profile = await mkdtemp(join(tmpdir(), "tabletop-fc-pwa-"));
const launch = () => chromium.launchPersistentContext(profile, {
  executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE,
  headless: true,
  args: ["--no-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"],
  viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, reducedMotion: "reduce",
});
let context;
try {
  context = await launch();
  let page = await context.newPage();
  const errors = [];
  const observe = (tab) => tab.on("pageerror", (error) => errors.push(error.message));
  observe(page);
  const url = `${origin}/tabletop-fc/`;
  await page.goto(`${url}?qa`);
  await page.waitForFunction(() => !!window.tabletopFC && !!navigator.serviceWorker.controller);
  await page.waitForFunction(() => document.getElementById("offline-status").textContent.includes("Ready to play offline"));

  const manifestURL = await page.locator('link[rel="manifest"]').getAttribute("href");
  const manifest = await (await context.request.get(new URL(manifestURL, url).href)).json();
  assert.equal(new URL(manifest.start_url, url).href, url);
  assert.equal(new URL(manifest.scope, url).href, url);
  assert.equal(manifest.display, "standalone");
  for (const [file, size] of [["apple-touch-icon", 180], ["icon-192", 192], ["icon-512", 512]]) {
    const png = files.get(`icons/${file}.png`);
    assert.equal(png.readUInt32BE(16), size);
    assert.equal(png.readUInt32BE(20), size);
  }
  assert.equal(await page.locator(".rulebook-link").count(), 0);
  for (const href of await page.locator('a[href]').evaluateAll((links) => links.map((link) => link.href))) {
    if (href.startsWith(origin)) assert.equal((await context.request.get(href)).status(), 200, href);
  }
  // Every emitted file, including the background AI worker, must survive offline.
  const cached = await page.evaluate(async () => {
    const names = await caches.keys();
    const cache = await caches.open(names.find((name) => name.includes("/tabletop-fc/")));
    return (await cache.keys()).map((request) => new URL(request.url).pathname);
  });
  for (const file of files.keys()) {
    if (file !== "sw.js") assert.ok(cached.includes(`/tabletop-fc/${file}`), `${file} is precached`);
  }
  assert.ok(cached.some((path) => /ai-worker.*\.js$/.test(path)));
  console.log("PWA install and asset checks passed; checking phone layouts.");
  await mkdir("test-results", { recursive: true });
  await page.screenshot({ path: "test-results/pwa-iphone-home.png" });
  await page.locator("#start-local").click();
  const saved = await page.evaluate(() => localStorage.getItem("tabletop-fc-match-v2"));
  assert.ok(saved);

  // Simulate the notch/home indicator because desktop mobile emulation has zero insets.
  await page.addStyleTag({ content: (await readFile("src/style.css", "utf8")).replaceAll("env(safe-area-inset-top)", "59px").replaceAll("env(safe-area-inset-bottom)", "34px").replaceAll("env(safe-area-inset-left)", "0px").replaceAll("env(safe-area-inset-right)", "0px") });
  async function checkInsets(left, top, right, bottom) {
    await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    const rects = await page.locator("#hud-header, #turn-dock").evaluateAll((elements) => elements.map((element) => {
      const rect = element.getBoundingClientRect();
      return { left: rect.left, top: rect.top, right: innerWidth - rect.right, bottom: innerHeight - rect.bottom };
    }));
    assert.ok(rects[0].top >= top);
    assert.ok(rects[1].bottom >= bottom);
    for (const rect of rects) {
      assert.ok(rect.left >= left - 1 && rect.right >= right - 1, JSON.stringify(rect));
    }
    const pitchFits = await page.evaluate(({ left, right, bottom }) =>
      [[0, 0], [9, 0], [0, 5], [9, 5], [-1, 2], [10, 3]].every(([x, y]) => {
        const point = window.tabletopFC.screenPosition(x, y);
        return point.x >= left && point.x <= innerWidth - right &&
          point.y >= 0 && point.y <= innerHeight - bottom &&
          document.elementFromPoint(point.x, point.y)?.tagName === "CANVAS";
      }), { left, right, bottom });
    assert.ok(pitchFits, "Pitch corners and goals stay visible and tappable inside safe areas");
  }
  await checkInsets(0, 59, 0, 34);
  await page.screenshot({ path: "test-results/pwa-iphone-portrait.png" });
  await page.setViewportSize({ width: 844, height: 390 });
  await page.addStyleTag({ content: (await readFile("src/style.css", "utf8")).replaceAll("env(safe-area-inset-top)", "0px").replaceAll("env(safe-area-inset-bottom)", "21px").replaceAll("env(safe-area-inset-left)", "59px").replaceAll("env(safe-area-inset-right)", "59px") });
  await checkInsets(59, 0, 59, 21);
  await page.screenshot({ path: "test-results/pwa-iphone-landscape.png" });

  online = false;
  console.log("Checking offline launch, saved match, and AI turn.");
  await page.reload();
  await page.waitForFunction(() => !!window.tabletopFC);
  assert.equal(await page.evaluate(() => localStorage.getItem("tabletop-fc-match-v2")), saved);
  await page.locator("#continue-match").click();
  assert.ok(await page.locator("#viewport canvas").isVisible());
  // Resume an actual AI turn while the server is completely unreachable.
  const state = Game.kickoff(Game.createGame(), 1, 3);
  Object.assign(state, { phase: "roll", opening: false, kickoffKind: null, team: "red", ball: { x: 5, y: 3 }, selected: null, used: [], remaining: 0, roll: 0 });
  await page.evaluate((state) => localStorage.setItem("tabletop-fc-match-v2", JSON.stringify({ version: 2, state, baseline: state, history: [], opponent: "computer" })), state);
  await page.reload();
  await page.locator("#continue-match").click();
  await page.waitForFunction(() => {
    const state = window.tabletopFC?.getState();
    return state?.rolls.red === 1 && (state.team === "blue" || state.phase === "goal");
  });
  const afterAI = await page.evaluate(() => localStorage.getItem("tabletop-fc-match-v2"));
  await page.close();
  page = await context.newPage();
  observe(page);
  await page.goto(`${url}index.html?qa`);
  await page.waitForFunction(() => !!window.tabletopFC);
  assert.equal(await page.evaluate(() => localStorage.getItem("tabletop-fc-match-v2")), afterAI);

  // A second version waits while the game is open, then activates after it closes.
  online = true;
  console.log("Checking deferred update activation and saved-match preservation.");
  revision = 2;
  await page.evaluate(async () => (await navigator.serviceWorker.getRegistration()).update());
  await page.waitForFunction(async () => !!(await navigator.serviceWorker.getRegistration()).waiting);
  assert.equal(await page.locator('meta[name="test-version"]').count(), 0);
  assert.equal(await page.evaluate(() => localStorage.getItem("tabletop-fc-match-v2")), afterAI);
  await page.waitForFunction(() => document.getElementById("offline-status").textContent.includes("Update downloaded"));
  // Cold launch with the same profile verifies that offline files and saves survive app exit.
  await context.close();
  context = await launch();
  const observer = await context.newPage();
  await observer.goto(`${origin}/observer`);
  await observer.waitForFunction(async () => {
    const registration = await navigator.serviceWorker.getRegistration("/tabletop-fc/");
    const names = (await caches.keys()).filter((name) => name.includes("/tabletop-fc/"));
    return registration?.active?.state === "activated" && !registration.waiting &&
      names.length === 1 && names[0].endsWith(":test-update");
  });
  page = await context.newPage();
  observe(page);
  online = false;
  await page.goto(`${url}?qa`);
  await page.waitForFunction(() => !!window.tabletopFC);
  assert.equal(await page.evaluate(() => document.querySelector('meta[name="test-version"]')?.content), "2");
  assert.equal(await page.evaluate(() => localStorage.getItem("tabletop-fc-match-v2")), afterAI);
  assert.equal((await page.evaluate(() => caches.keys())).filter((name) => name.includes("/tabletop-fc/")).length, 1);
  assert.deepEqual(errors, []);
  console.log("PWA checks passed: scoped install, all assets cached, iPhone safe areas, offline launch/resume/AI, and deferred updates preserve saves.");
} finally {
  await context?.close();
  await new Promise((resolve) => server.close(resolve));
  await rm(profile, { recursive: true, force: true });
}
