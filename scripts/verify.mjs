import { readFile, access } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const root = process.cwd();
const manifest = JSON.parse(await readFile(path.join(root, "claw.manifest.json"), "utf8"));
const packageJson = JSON.parse(await readFile(path.join(root, "package.json"), "utf8"));
const failures = [];

function check(condition, message) {
  if (!condition) failures.push(message);
}

const paths = [manifest.entry, manifest.output, ...manifest.modules];
check(new Set(manifest.modules).size === manifest.modules.length, "manifest contains duplicate modules");
for (const relativePath of paths) {
  try {
    await access(path.join(root, relativePath));
  } catch {
    failures.push(`missing manifest file: ${relativePath}`);
  }
}

const sources = new Map();
for (const relativePath of [manifest.entry, "loader.lua", ...manifest.modules]) {
  if (sources.has(relativePath)) continue;
  sources.set(relativePath, await readFile(path.join(root, relativePath), "utf8"));
}
const combined = [...sources.values()].join("\n");
const bundle = await readFile(path.join(root, manifest.output), "utf8");

check(!/Animation Lab/i.test(combined), "visible legacy Animation Lab branding remains");
check(!/project_rain_with_loot|references[\\/]lycoris-rewrite/i.test(bundle), "private local source leaked into bundle");
check(!/(?:ghp_|github_pat_)[A-Za-z0-9_]+/.test(combined), "GitHub credential-like token found");
check(!/https:\/\/(?:canary\.|ptb\.)?discord(?:app)?\.com\/api\/webhooks\//i.test(combined), "Discord webhook URL found");
check(combined.includes('environment.CLAW.Version = "' + packageJson.version + '"'), "runtime/package versions differ");
check(bundle.includes(`-- BEGIN ENTRY: ${manifest.entry}`), "bundle entry marker is missing");
for (const modulePath of manifest.modules) {
  check(bundle.includes(`-- BEGIN MODULE: ${modulePath}`), `bundle marker missing: ${modulePath}`);
}

if (failures.length > 0) {
  console.error(`CLAW verification failed:\n- ${failures.join("\n- ")}`);
  process.exit(1);
}
console.log(`CLAW verification passed (${manifest.modules.length} modules, ${bundle.length} bundle chars).`);
