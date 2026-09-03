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
const dynamicWeaponSource = sources.get("src/Combat/DynamicWeaponResolver.lua");
const timingResolverSource = sources.get("src/Combat/TimingResolver.lua");
const defenseSource = sources.get("src/Combat/DefenseEngine.lua");
const schedulerSource = sources.get("src/Combat/Scheduler.lua");
const threatSource = sources.get("src/Combat/ThreatArbiter.lua");
const nativeBridgeSource = sources.get("src/Combat/NativeInputBridge.lua");
const fallbackSource = sources.get("src/Combat/FallbackResolver.lua");
const validationSource = sources.get("src/Combat/ValidationEngine.lua");
const stateMonitorSource = sources.get("src/Combat/StateMonitor.lua");
const actionExecutorSource = sources.get("src/Combat/ActionExecutor.lua");
const diagnosticsSource = sources.get("src/Combat/Diagnostics.lua");
const presetSource = sources.get("src/Combat/PresetManager.lua");
const detectorHubSource = sources.get("src/Combat/Detection/DetectorHub.lua");
const clientEffectSource = sources.get("src/Combat/Detection/ClientEffectDetector.lua");
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
check(entry.includes("Main.Active = false"), "main window background can sink game input");
check(!/UIS\.MouseBehavior\s*=|UIS\.MouseIconEnabled\s*=/.test(entry), "UI mutates global Roblox mouse state");
check(!/name\s*=\s*"(?:Critical|Flourish)"[\s\S]{0,80}?enabled\s*=\s*true/.test(entry), "a built-in burst rule starts enabled");
check(settingsSource.includes("function Settings:safeStart()"), "safe-start settings reset is missing");
check(combatSource.includes("Settings.new(savedSettings):safeStart()"), "saved active switches can bypass safe start");
check(inputSource.includes("string.byte(string.upper(name))"), "executor virtual-key conversion is missing");
check(nativeInputSource.includes('self:_remote("Block")'), "native block remote bridge is missing");
check(!nativeInputSource.includes("self.InputData = self:_scanInputData()"), "native bridge can retain the game's private input state");
check(
  nativeInputSource.includes("self.InputData.f = true") && nativeInputSource.includes("self.InputData.f = false"),
  "native block input-state mirroring is missing",
);
check(dynamicWeaponSource.includes("WeaponTest = \"M1\""), "dynamic M1 weapon resolver is missing");
check(dynamicWeaponSource.includes("WeaponFlourishTest = \"Flourish\""), "dynamic flourish resolver is missing");
check(dynamicWeaponSource.includes("function DynamicWeaponResolver.weaponInfo"), "unknown weapon inspection is missing");
check(dynamicWeaponSource.includes("function DynamicWeaponResolver.resolveProfile"), "live weapon builder profile resolution is missing");
check(dynamicWeaponSource.includes("resolved.forceFacingTarget = true"), "weapon builders omit forced-facing hitbox semantics");
check(dynamicWeaponSource.includes("resolved.preferBlockFallback = true"), "weapon builders omit weapon-specific fallback policy");
check(dynamicWeaponSource.includes("action.metadata.preserveDelay"), "unknown weapon delay preservation is missing");
check(!/delay\s*=\s*delay\s*\/\s*math\.abs\(speed\)/.test(timingResolverSource), "static timing delays are being divided by animation speed");
check(/local scheduled\s+scheduled\s*=\s*self\.Scheduler:schedule/.test(defenseSource), "scheduled defense callback does not capture a predeclared task handle");
check(schedulerSource.includes('self.state:increment("Failed")'), "scheduler failures are not counted");
check(schedulerSource.includes("self.state.LastFailure"), "scheduler failures are not exposed to diagnostics");
check(nativeBridgeSource.includes("self.BlockRetryCount < 1"), "native block retries are not bounded");
check(nativeBridgeSource.includes("not self.ReleaseSent"), "native unblock is not edge-triggered");
check(nativeBridgeSource.includes('self:_hasEffect("ParryCool")'), "native parry cooldown state is not consulted");
check(nativeBridgeSource.includes('self:_remote("Dodge")'), "native dodge remote bridge is missing");
check(nativeBridgeSource.includes('self:_remote("StopDodge")'), "native dodge cancel remote bridge is missing");
check(fallbackSource.includes('self.Settings:get("Defense.DodgeFallback")'), "dodge fallback is not explicitly gated");
check(fallbackSource.includes('reason == "parry-cooldown"'), "replicated parry cooldown does not select a fallback");
check(validationSource.includes("native:canParry()"), "validation ignores replicated parry readiness");
check(validationSource.includes("native:canDodge()"), "validation ignores replicated dodge readiness");
check(inputSource.includes("self.Native:isDodging()"), "roll cancel does not wait for native dodge state");
check(actionExecutorSource.includes("self.Input:scheduleDodgeCancel"), "action execution bypasses state-aware roll cancel");
check(inputSource.includes("DodgeCancelGeneration"), "stale dodge-cancel jobs are not generation guarded");
check(inputSource.includes("dodge cancel skipped: roll not observed"), "roll cancellation can fire without observing a dodge");
check(nativeBridgeSource.includes("function NativeInputBridge:releaseAll"), "native safe-reset release is missing");
check(validationSource.includes("options.skipTransient"), "planning cannot defer volatile readiness checks");
check(defenseSource.includes('scheduled.identifier .. ":" .. tostring(scheduled.id)'), "hitbox waits are not plan-unique");
check(defenseSource.includes('return self:_reject("defense disabled before execution")'), "disabled defense can execute pending plans");
check(diagnosticsSource.includes("function Diagnostics:report"), "shareable diagnostic reporting is missing");
check(presetSource.includes("Stable ="), "known-good Stable preset is missing");
check(presetSource.includes("merge(current, PRESET_BASE)"), "presets can inherit stale optional toggles");
check(entry.includes("LOGGER: OFF") && entry.includes("CONFIG.LoggingEnabled = not CONFIG.LoggingEnabled"), "logger has no usable UI switch");
check(entry.includes("TimingBrowser.search") && entry.includes("TimingBrowser.pageSize"), "timing browser search or paging is missing");
check(entry.includes("PANIC / ALL OFF"), "panic recovery control is missing");
check(detectorHubSource.includes('settings:get("Detection.UnknownAnimations")'), "unknown-animation defense is not explicitly gated");
check(defenseSource.includes("native:isBusy()"), "generic defense does not guard the active native-input window");
check(defenseSource.includes("generic defense rearm"), "generic defense has no post-detection rearm guard");
check(defenseSource.includes('sourceModule = weapon and "WeaponTest"'), "unknown weapon animations do not use the dynamic hitbox resolver");
check(schedulerSource.includes("scheduled.detail = detail"), "scheduled validation failure detail is discarded");
check(threatSource.includes('event.detector == "animation" and pendingPlans >= maximum'), "animation plans can consume an unbounded per-source budget");
check(threatSource.includes('record.noisyUntil'), "source-scoped animation quarantine is missing");
check(threatSource.includes('ThreatCoalesced'), "overlapping threat plans are not coalesced");
check(threatSource.includes('ThreatPromoted'), "stronger evidence cannot supersede an animation plan");
check(defenseSource.includes('self.Threats:claim'), "defense scheduling bypasses threat arbitration");
check(entry.includes('"THREAT GUARD", "ThreatGuard.Enabled"'), "threat guard has no visible control");
check(clientEffectSource.includes("ClientEffectLarge") && clientEffectSource.includes("ClientEffectDirect"), "three-channel client-effect detection is incomplete");
check(clientEffectSource.includes("inspected >= 32") && clientEffectSource.includes("depth > 2"), "client-effect owner traversal is not bounded");
check(clientEffectSource.includes('previous.channel ~= channel'), "cross-channel client-effect deduplication is missing");
check(detectorHubSource.includes("ClientEffectDetector.new"), "client-effect detector is not connected to the detector hub");
check(validationSource.includes("profile and profile.useHitboxCFrame"), "hitbox-CFrame profiles still prefer the owner root");
check(validationSource.includes("profile.forceFacingTarget"), "forced-facing builder hitboxes are not validated");
check(stateMonitorSource.includes('instance:IsA("ValueBase")'), "replicated state values are not watched for changes");
check(stateMonitorSource.includes("CharacterRemoving"), "character removal does not quiesce replicated state");
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

const runtimeCandidates = process.platform === "win32"
  ? [path.join(root, ".tools", "luau", "bin", "luau.exe")]
  : [path.join(root, ".tools", "luau", "bin", "luau")];
for (const runtimePath of runtimeCandidates) {
  try {
    await access(runtimePath);
  } catch {
    continue;
  }
  const scenarios = spawnSync(runtimePath, [path.join(root, "tests", "ThreatArbiter.spec.luau")], {
    cwd: root,
    encoding: "utf8",
  });
  const detail = `${scenarios.stdout ?? ""}${scenarios.stderr ?? ""}`.trim();
  check(scenarios.status === 0, `ThreatArbiter scenarios failed${detail ? `: ${detail}` : ""}`);
  if (scenarios.status === 0) console.log(detail || "ThreatArbiter scenarios passed.");
  break;
}

if (failures.length > 0) {
  console.error(`CLAW verification failed:\n- ${failures.join("\n- ")}`);
  process.exit(1);
}
console.log(`CLAW verification passed (${manifest.modules.length} modules, ${bundle.length} bundle chars).`);
