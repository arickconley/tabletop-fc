import { build } from "vite";
import { createHash } from "node:crypto";
import { copyFile, mkdir, readFile, readdir, writeFile } from "node:fs/promises";

await build();
for (const file of ["vendor/three/LICENSE", "vendor/fonts/barlow-condensed/OFL.txt"]) {
  await mkdir(`dist/${file.slice(0, file.lastIndexOf("/"))}`, { recursive: true });
  await copyFile(file, `dist/${file}`);
}
// The reference PDF is local-only; the published game includes its own rules.
const html = (await readFile("dist/index.html", "utf8"))
  .replace(/\s*<script type="importmap">[\s\S]*?<\/script>/, "")
  .replace(/\s*<a\s[^>]*class="button secondary rulebook-link"[\s\S]*?<\/a\s*>/, "");
await writeFile("dist/index.html", html);

const files = (await readdir("dist", { recursive: true, withFileTypes: true }))
  .filter((entry) => entry.isFile())
  .map((entry) => `${entry.parentPath}/${entry.name}`.replace(/^dist\//, ""))
  .sort();
const template = await readFile("src/service-worker.js", "utf8");
const hash = createHash("sha256").update(template);
for (const file of files) hash.update(file).update(await readFile(`dist/${file}`));
const worker = template
  .replace("__BUILD_VERSION__", hash.digest("hex").slice(0, 16))
  .replace("__PRECACHE_ASSETS__", JSON.stringify(files));
await writeFile("dist/sw.js", worker);
console.log(`Offline cache includes all ${files.length} build files.`);
