import { readFile, access } from "node:fs/promises";
import { spawnSync } from "node:child_process";
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
const entry = sources.get(manifest.entry);
const settingsSource = sources.get("src/Combat/Settings.lua");
const combatSource = sources.get("src/Combat/init.lua");
const inputSource = sources.get("src/Combat/InputAdapter.lua");
const nativeInputSource = sources.get("src/Combat/NativeInputBridge.lua");
const bundle = await readFile(path.join(root, manifest.output), "utf8");
const timingDatabase = JSON.parse(await readFile(path.join(root, "data", "lycoris-timings.json"), "utf8"));
const timingProfiles = Object.values(timingDatabase.timings ?? {}).flat();
const timingActions = timingProfiles.flatMap((profile) => profile.actions ?? []);
const validActionKinds = new Set(["Parry", "Block", "Dodge", "FullDodge", "Jump", "Slide", "Crouch", "Teleport", "Feint", "M1", "Custom"]);

check(!/Animation Lab/i.test(combined), "visible legacy Animation Lab branding remains");
check(!/project_rain_with_loot|references[\\/]lycoris-rewrite/i.test(bundle), "private local source leaked into bundle");
check(!/(?:ghp_|github_pat_)[A-Za-z0-9_]+/.test(combined), "GitHub credential-like token found");
check(!/https:\/\/(?:canary\.|ptb\.)?discord(?:app)?\.com\/api\/webhooks\//i.test(combined), "Discord webhook URL found");
check(combined.includes('environment.CLAW.Version = "' + packageJson.version + '"'), "runtime/package versions differ");
check(/BursterMaster\s*=\s*false/.test(entry), "Burster must start disabled");
check(/LoggingEnabled\s*=\s*false/.test(entry), "animation logging must start disabled");
check(!/name\s*=\s*"(?:Critical|Flourish)"[\s\S]{0,80}?enabled\s*=\s*true/.test(entry), "a built-in burst rule starts enabled");
check(settingsSource.includes("function Settings:safeStart()"), "safe-start settings reset is missing");
check(combatSource.includes("Settings.new(savedSettings):safeStart()"), "saved active switches can bypass safe start");
check(inputSource.includes("string.byte(string.upper(name))"), "executor virtual-key conversion is missing");
check(nativeInputSource.includes('self:_remote("Block")'), "native block remote bridge is missing");
check(nativeInputSource.includes("self.InputData.f = active"), "native block input-state mirroring is missing");
check(timingDatabase.version === 1, "timing database version is invalid");
check(timingProfiles.length >= 800, "attributed timing database is incomplete");
check(timingActions.length >= 1000, "attributed timing actions are incomplete");
check(timingActions.every((action) => validActionKinds.has(action.kind)), "timing database contains an unsupported action kind");
check(timingDatabase.provenance?.sourceRepository === "https://git.blastbrean.com/lycoris/deepwoken-rewrite", "timing attribution source is missing");
check(/^[a-f0-9]{40}$/.test(timingDatabase.provenance?.sourceCommit ?? ""), "timing source commit is not pinned");
check(bundle.includes(`-- BEGIN ENTRY: ${manifest.entry}`), "bundle entry marker is missing");
const colorBlock = entry.match(/local COLORS\s*=\s*\{([\s\S]*?)\n\}/)?.[1] ?? "";
const definedColors = new Set([...colorBlock.matchAll(/^\s*([A-Z][A-Z0-9_]*)\s*=/gm)].map((match) => match[1]));
const usedColors = new Set([...entry.matchAll(/COLORS\.([A-Z][A-Z0-9_]*)/g)].map((match) => match[1]));
for (const color of usedColors) {
  check(definedColors.has(color), `undefined UI palette key: COLORS.${color}`);
}
for (const modulePath of manifest.modules) {
  check(bundle.includes(`-- BEGIN MODULE: ${modulePath}`), `bundle marker missing: ${modulePath}`);
}

const compilerCandidates = process.platform === "win32"
  ? [path.join(root, ".tools", "luau", "bin", "luau-compile.exe")]
  : [path.join(root, ".tools", "luau", "bin", "luau-compile")];
let compilerPath;
for (const candidate of compilerCandidates) {
  try {
    await access(candidate);
    compilerPath = candidate;
    break;
  } catch {
    // The official compiler is an optional local quality gate.
  }
}
if (compilerPath) {
  const compile = spawnSync(compilerPath, ["--null", path.join(root, manifest.output)], {
    cwd: root,
    encoding: "utf8",
  });
  const detail = `${compile.stdout ?? ""}${compile.stderr ?? ""}`.trim();
  check(compile.status === 0, `Luau compilation failed${detail ? `: ${detail}` : ""}`);
  if (compile.status === 0) console.log("Official Luau compile check passed.");
}

if (failures.length > 0) {
  console.error(`CLAW verification failed:\n- ${failures.join("\n- ")}`);
  process.exit(1);
}
console.log(`CLAW verification passed (${manifest.modules.length} modules, ${bundle.length} bundle chars).`);
