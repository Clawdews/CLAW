import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const sessionArgument = process.argv[2];
if (!sessionArgument) {
  console.error("Usage: node scripts/analyze-recorder.mjs <CLAW_RECORDER/session-folder>");
  process.exit(1);
}

const root = process.cwd();
const sessionDir = path.resolve(sessionArgument);
const database = JSON.parse(await readFile(path.join(root, "data", "lycoris-timings.json"), "utf8"));
let catalogExport = null;
try {
  catalogExport = JSON.parse(await readFile(path.join(sessionDir, "catalog.json"), "utf8"));
} catch {
  // Raw chunks are sufficient for legacy or interrupted sessions.
}
const knownProfiles = new Map();
for (const profiles of Object.values(database.timings ?? {})) {
  for (const profile of profiles) knownProfiles.set(String(profile.id), profile);
}

const names = (await readdir(sessionDir))
  .filter((name) => /^events_\d+\.json$/.test(name) || name === "events_live.json")
  .sort((left, right) => left.localeCompare(right, undefined, { numeric: true }));

const eventsBySequence = new Map();
for (const name of names) {
  const chunk = JSON.parse(await readFile(path.join(sessionDir, name), "utf8"));
  for (const event of chunk.events ?? []) {
    const key = Number.isFinite(event.seq) ? `seq:${event.seq}` : `${name}:${eventsBySequence.size}`;
    eventsBySequence.set(key, event);
  }
}
const events = [...eventsBySequence.values()].sort((left, right) => (left.t ?? 0) - (right.t ?? 0));
const duration = Math.max(
  Number(catalogExport?.session?.duration) || 0,
  events.reduce((maximum, event) => Math.max(maximum, Number(event.t) || 0), 0),
);

function increment(map, key, amount = 1) {
  map.set(key, (map.get(key) ?? 0) + amount);
}

function median(values) {
  if (values.length === 0) return null;
  const sorted = [...values].sort((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle];
}

function fixed(value, places = 3) {
  return value == null || !Number.isFinite(Number(value)) ? null : Number(Number(value).toFixed(places));
}

function profileName(id) {
  return knownProfiles.get(String(id))?.name ?? "UNKNOWN";
}

const eventTypes = new Map();
const sourceCounts = new Map();
const animationGroups = new Map();
const starts = [];
for (const event of events) {
  increment(eventTypes, event.type ?? "unknown");
  if (event.type !== "animation_start") continue;
  starts.push(event);
  const id = String(event.animation?.id ?? "unknown");
  const source = String(event.entity?.sourceId ?? `${event.entity?.kind ?? "unknown"}:${event.entity?.label ?? "unknown"}`);
  increment(sourceCounts, source);
  const key = `${source}|${id}`;
  let group = animationGroups.get(key);
  if (!group) {
    group = {
      source,
      kind: event.entity?.kind ?? "unknown",
      label: event.entity?.label ?? "unknown",
      id,
      priority: event.animation?.priority ?? "Unknown",
      times: [],
    };
    animationGroups.set(key, group);
  }
  group.times.push(Number(event.t) || 0);
}

// A breaker cluster is source-scoped: at least five Action IDs each repeating at
// least once every two seconds across the observed session. A lone aggressive M1
// is therefore not classified as a breaker merely for being frequent.
const candidateGroupsBySource = new Map();
for (const group of animationGroups.values()) {
  if (!String(group.priority).startsWith("Action") || duration <= 0 || group.times.length / duration < 0.5) continue;
  const list = candidateGroupsBySource.get(group.source) ?? [];
  list.push(group);
  candidateGroupsBySource.set(group.source, list);
}
const breakerIds = new Set();
const breakerGroups = [];
for (const groups of candidateGroupsBySource.values()) {
  if (groups.length < 5) continue;
  for (const group of groups) {
    breakerIds.add(group.id);
    breakerGroups.push(group);
  }
}
for (const animations of Object.values(catalogExport?.suspiciousAnimations ?? {})) {
  for (const [id, suspicious] of Object.entries(animations ?? {})) {
    if (suspicious) breakerIds.add(String(id));
  }
}

function rankedCandidates(event) {
  const candidates = Array.isArray(event.candidates) ? event.candidates : [];
  return candidates.map((candidate, index) => ({ ...candidate, rank: index + 1 }));
}

function cleanCandidate(event) {
  const candidates = rankedCandidates(event);
  return candidates.find(
    (candidate) => !breakerIds.has(String(candidate.animationId)) && String(candidate.priority ?? "").startsWith("Action"),
  ) ?? candidates.find((candidate) => !breakerIds.has(String(candidate.animationId))) ?? null;
}

const outcomes = events.filter((event) => event.type === "outcome");
const offenseOutcomes = events.filter((event) => event.type === "offense_outcome");
const localStarts = events.filter((event) => event.type === "local_animation_start");
const effectAdds = events.filter((event) => event.type === "effect_added");
const outcomeCounts = new Map();
const effectCounts = new Map();
for (const outcome of outcomes) increment(outcomeCounts, outcome.kind ?? "unknown");
for (const effect of effectAdds) increment(effectCounts, effect.class ?? "unknown");

const attempts = outcomes.filter((event) => event.kind === "parry_attempt");
const confirmedSuccesses = effectAdds.filter((event) => event.class === "ParrySuccess");
const pairedAttemptSequences = new Set();
const successPairs = [];
for (const success of confirmedSuccesses) {
  let best = null;
  for (let index = attempts.length - 1; index >= 0; index -= 1) {
    const attempt = attempts[index];
    const delta = Number(success.t) - Number(attempt.t);
    if (delta < 0) continue;
    if (delta > 0.75) break;
    best = attempt;
    break;
  }
  if (!best) continue;
  pairedAttemptSequences.add(best.seq);
  successPairs.push({ success, attempt: best, candidate: cleanCandidate(best) });
}

const resultGroups = new Map();
function resultFor(id) {
  const key = String(id ?? "unlinked");
  let result = resultGroups.get(key);
  if (!result) {
    result = {
      id: key,
      name: profileName(key),
      attempts: 0,
      successes: 0,
      damageTicks: 0,
      damages: [],
      attemptDelays: [],
      successDelays: [],
      failedDelays: [],
      hitDelays: [],
      ranks: [],
    };
    resultGroups.set(key, result);
  }
  return result;
}
for (const attempt of attempts) {
  const candidate = cleanCandidate(attempt);
  if (!candidate) continue;
  const result = resultFor(candidate.animationId);
  result.attempts += 1;
  result.attemptDelays.push(Number(candidate.delay));
  result.ranks.push(Number(candidate.rank));
  if (pairedAttemptSequences.has(attempt.seq)) {
    result.successes += 1;
    result.successDelays.push(Number(candidate.delay));
  } else {
    result.failedDelays.push(Number(candidate.delay));
  }
}
for (const hit of outcomes.filter((event) => event.kind === "health_hit")) {
  const candidate = cleanCandidate(hit);
  if (!candidate) continue;
  const result = resultFor(candidate.animationId);
  result.damageTicks += 1;
  result.damages.push(Number(hit.detail?.damage) || 0);
  result.hitDelays.push(Number(candidate.delay));
  result.ranks.push(Number(candidate.rank));
}

const sourceRows = [...sourceCounts.entries()]
  .map(([source, count]) => ({ source, animations: count }))
  .sort((left, right) => right.animations - left.animations);
const breakerRows = breakerGroups
  .map((group) => {
    const intervals = group.times.slice(1).map((time, index) => time - group.times[index]);
    return {
      source: group.source,
      id: group.id,
      name: profileName(group.id),
      starts: group.times.length,
      rate: fixed(group.times.length / Math.max(duration, 0.001), 2),
      medianInterval: fixed(median(intervals)),
    };
  })
  .sort((left, right) => right.starts - left.starts);
const representedBreakerIds = new Set(breakerRows.map((row) => row.id));
for (const id of breakerIds) {
  if (representedBreakerIds.has(id)) continue;
  const catalog = catalogExport?.catalog?.[id];
  const sources = Object.entries(catalog?.sources ?? {});
  if (sources.length === 0) {
    breakerRows.push({ source: "catalog", id, name: profileName(id), starts: catalog?.observations ?? 0, rate: null, medianInterval: null });
    continue;
  }
  for (const [source, detail] of sources) {
    breakerRows.push({
      source,
      id,
      name: profileName(id),
      starts: detail.observations ?? 0,
      rate: fixed((detail.observations ?? 0) / Math.max(duration, 0.001), 2),
      medianInterval: null,
    });
  }
}
breakerRows.sort((left, right) => right.starts - left.starts);
const resultRows = [...resultGroups.values()]
  .map((result) => ({
    id: result.id,
    name: result.name,
    attempts: result.attempts,
    successes: result.successes,
    damageTicks: result.damageTicks,
    totalDamage: fixed(result.damages.reduce((sum, value) => sum + value, 0), 1),
    damageMedian: fixed(median(result.damages), 2),
    attemptMedian: fixed(median(result.attemptDelays)),
    successMedian: fixed(median(result.successDelays)),
    failedMedian: fixed(median(result.failedDelays)),
    hitMedian: fixed(median(result.hitDelays)),
    candidateRankMedian: fixed(median(result.ranks), 1),
  }))
  .filter((result) => result.attempts > 0 || result.damageTicks > 0)
  .sort((left, right) => (right.attempts + right.damageTicks) - (left.attempts + left.damageTicks));

const offenseGroups = new Map();
function offenseFor(id) {
  const key = String(id ?? "unlinked");
  let result = offenseGroups.get(key);
  if (!result) {
    result = {
      id: key,
      name: profileName(key),
      observations: Number(catalogExport?.offenseCatalog?.[key]?.observations) || 0,
      parried: 0,
      landed: 0,
      parriedDelays: [],
      landedDelays: [],
    };
    offenseGroups.set(key, result);
  }
  return result;
}
for (const [id, detail] of Object.entries(catalogExport?.offenseCatalog ?? {})) {
  const result = offenseFor(id);
  result.observations = Number(detail?.observations) || 0;
}
for (const outcome of offenseOutcomes) {
  const match = outcome.match ?? cleanCandidate(outcome);
  if (!match) continue;
  const result = offenseFor(match.animationId);
  if (outcome.kind === "local_attack_parried") {
    result.parried += 1;
    result.parriedDelays.push(Number(match.delay));
  } else if (outcome.kind === "local_attack_landed") {
    result.landed += 1;
    result.landedDelays.push(Number(match.delay));
  }
}
const offenseRows = [...offenseGroups.values()]
  .map((result) => ({
    id: result.id,
    name: result.name,
    observations: result.observations,
    parried: result.parried,
    landed: result.landed,
    parriedMedian: fixed(median(result.parriedDelays)),
    landedMedian: fixed(median(result.landedDelays)),
  }))
  .filter((result) => result.observations > 0 || result.parried > 0 || result.landed > 0)
  .sort((left, right) => (right.parried + right.landed + right.observations) - (left.parried + left.landed + left.observations));

console.log(`Session: ${path.basename(sessionDir)}`);
console.log(`Duration: ${fixed(duration, 1)}s | event files: ${names.length} | retained events: ${events.length}`);
console.log(`Animations: ${starts.length} | sources: ${sourceRows.length} | outcomes: ${outcomes.length}`);
console.log(`Parry attempts: ${attempts.length} | confirmed ParrySuccess: ${confirmedSuccesses.length} | paired: ${successPairs.length}`);
console.log(`Health-loss ticks: ${outcomeCounts.get("health_hit") ?? 0}`);
console.log(`Local offensive mirror: ${catalogExport?.session?.localAnimations ?? localStarts.length} animations | ${offenseOutcomes.length} replies`);
console.log("\nSources");
console.table(sourceRows);
console.log("\nDetected breaker cluster");
if (breakerRows.length > 0) console.table(breakerRows);
else console.log("none");
console.log("\nRecovered combat associations (breaker IDs excluded)");
console.table(resultRows.slice(0, 40));
console.log("\nOpponent responses to local attacks");
if (offenseRows.length > 0) console.table(offenseRows.slice(0, 40));
else console.log("not recorded (requires CLAW Recorder v0.3+)");
console.log("\nOutcome counts");
console.table([...outcomeCounts.entries()].map(([kind, count]) => ({ kind, count })).sort((a, b) => b.count - a.count));
console.log("\nSelected effect counts");
const selectedEffects = ["ParryCool", "ParrySuccess", "Parry", "Parried", "Blocking", "Dodge", "Stun", "Knocked"];
console.table(selectedEffects.map((name) => ({ name, count: effectCounts.get(name) ?? 0 })));
