import { readFile, readdir, writeFile, mkdir } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

class MessagePackReader {
  constructor(buffer) {
    this.buffer = buffer;
    this.offset = 0;
  }

  bytes(length) {
    const value = this.buffer.subarray(this.offset, this.offset + length);
    this.offset += length;
    return value;
  }

  string(length) {
    return this.bytes(length).toString("utf8");
  }

  array(length) {
    return Array.from({ length }, () => this.read());
  }

  map(length) {
    const result = {};
    for (let index = 0; index < length; index += 1) {
      result[String(this.read())] = this.read();
    }
    return result;
  }

  number(method, size) {
    const value = this.buffer[method](this.offset);
    this.offset += size;
    return typeof value === "bigint" ? Number(value) : value;
  }

  read() {
    const prefix = this.number("readUInt8", 1);
    if (prefix <= 0x7f) return prefix;
    if (prefix >= 0xe0) return prefix - 0x100;
    if (prefix >= 0x80 && prefix <= 0x8f) return this.map(prefix & 0x0f);
    if (prefix >= 0x90 && prefix <= 0x9f) return this.array(prefix & 0x0f);
    if (prefix >= 0xa0 && prefix <= 0xbf) return this.string(prefix & 0x1f);

    switch (prefix) {
      case 0xc0: return null;
      case 0xc2: return false;
      case 0xc3: return true;
      case 0xc4: return this.bytes(this.number("readUInt8", 1));
      case 0xc5: return this.bytes(this.number("readUInt16BE", 2));
      case 0xc6: return this.bytes(this.number("readUInt32BE", 4));
      case 0xca: return this.number("readFloatBE", 4);
      case 0xcb: return this.number("readDoubleBE", 8);
      case 0xcc: return this.number("readUInt8", 1);
      case 0xcd: return this.number("readUInt16BE", 2);
      case 0xce: return this.number("readUInt32BE", 4);
      case 0xcf: return this.number("readBigUInt64BE", 8);
      case 0xd0: return this.number("readInt8", 1);
      case 0xd1: return this.number("readInt16BE", 2);
      case 0xd2: return this.number("readInt32BE", 4);
      case 0xd3: return this.number("readBigInt64BE", 8);
      case 0xd9: return this.string(this.number("readUInt8", 1));
      case 0xda: return this.string(this.number("readUInt16BE", 2));
      case 0xdb: return this.string(this.number("readUInt32BE", 4));
      case 0xdc: return this.array(this.number("readUInt16BE", 2));
      case 0xdd: return this.array(this.number("readUInt32BE", 4));
      case 0xde: return this.map(this.number("readUInt16BE", 2));
      case 0xdf: return this.map(this.number("readUInt32BE", 4));
      default: throw new Error(`Unsupported MessagePack prefix 0x${prefix.toString(16)}`);
    }
  }
}

function decodeMessagePack(buffer) {
  const reader = new MessagePackReader(buffer);
  const value = reader.read();
  if (reader.offset !== buffer.length) {
    throw new Error(`MessagePack has ${buffer.length - reader.offset} trailing byte(s)`);
  }
  return value;
}

function timingKey(timing, category) {
  if (category === "part") return timing.pname ?? timing.name;
  if (category === "effect") return timing.ename ?? timing._id ?? timing.name;
  return timing._id ?? timing.name;
}

function applyPatch(database, patch) {
  for (const [category, changes] of Object.entries(patch.diff ?? {})) {
    database[category] ??= [];
    for (const [key, change] of Object.entries(changes)) {
      const index = database[category].findIndex((timing) => timingKey(timing, category) === key);
      if (change.status === "removed") {
        if (index >= 0) database[category].splice(index, 1);
      } else if (change.status === "added") {
        if (index >= 0) database[category][index] = structuredClone(change.data);
        else database[category].push(structuredClone(change.data));
      } else if (change.status === "modified" && index >= 0) {
        const wildcard = change.changes?.["*"]?.to;
        if (wildcard) {
          database[category][index] = structuredClone(wildcard);
        } else {
          for (const [field, values] of Object.entries(change.changes ?? {})) {
            database[category][index][field] = structuredClone(values.to);
          }
        }
      }
    }
  }
}

function vector(value) {
  return {
    X: Number(value?.X) || 0,
    Y: Number(value?.Y) || 0,
    Z: Number(value?.Z) || 0,
  };
}

function cleanAssetId(value) {
  return String(value ?? "").match(/\d+/)?.[0] ?? String(value ?? "");
}

const ACTION_KIND = {
  Parry: "Parry",
  Dodge: "Dodge",
  "Forced Full Dodge": "FullDodge",
  Jump: "Jump",
  "Start Block": "Block",
  "Start Slide": "Slide",
  "Start Crouch": "Crouch",
  "Teleport Up": "Teleport",
};

function convertActions(sourceActions) {
  const actions = [];
  for (let index = 0; index < (sourceActions ?? []).length; index += 1) {
    const source = sourceActions[index];
    const kind = ACTION_KIND[source._type];
    if (!kind) continue;
    const startMs = Number(source.when) || 0;
    let duration = 0;
    if (source._type.startsWith("Start ")) {
      const endType = source._type.replace("Start ", "End ");
      const ending = sourceActions.slice(index + 1).find((candidate) => candidate._type === endType);
      if (ending) duration = Math.max(0, ((Number(ending.when) || startMs) - startMs) / 1000);
    }
    actions.push({
      kind,
      name: String(source.name || source._type || kind),
      delay: Math.max(0, startMs / 1000),
      duration,
      hitbox: vector(source.hitbox),
      ignoreHitbox: source.ihbc === true,
      chance: 100,
      metadata: { importedType: String(source._type ?? kind) },
    });
  }
  return actions;
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

async function extractModuleActions(modulesDirectory, moduleName) {
  if (!moduleName || moduleName === "N/A") return [];
  let source;
  try {
    source = await readFile(path.join(modulesDirectory, `${moduleName}.lua`), "utf8");
  } catch {
    return [];
  }

  const declarations = [...source.matchAll(/\b(?:local\s+)?([A-Za-z_]\w*)\s*=\s*Action\.new\s*\(\s*\)/g)];
  const actions = [];
  for (let index = 0; index < declarations.length; index += 1) {
    const declaration = declarations[index];
    const variable = escapeRegExp(declaration[1]);
    const end = declarations[index + 1]?.index ?? source.length;
    const block = source.slice(declaration.index, end);
    const type = block.match(new RegExp(`\\b${variable}\\._type\\s*=\\s*["']([^"']+)["']`))?.[1];
    const when = Number(block.match(new RegExp(`\\b${variable}\\._when\\s*=\\s*(-?\\d+(?:\\.\\d+)?)`))?.[1]);
    if (!type || !Number.isFinite(when)) continue;
    const hitboxMatch = block.match(new RegExp(
      `\\b${variable}\\.hitbox\\s*=\\s*Vector3\\.new\\s*\\(\\s*(-?\\d+(?:\\.\\d+)?)\\s*,\\s*(-?\\d+(?:\\.\\d+)?)\\s*,\\s*(-?\\d+(?:\\.\\d+)?)\\s*\\)`,
    ));
    const name = block.match(new RegExp(`\\b${variable}\\.name\\s*=\\s*["']([^"']+)["']`))?.[1];
    const ignoreHitbox = block.match(new RegExp(`\\b${variable}\\.ihbc\\s*=\\s*(true|false)`))?.[1] === "true";
    actions.push({
      _type: type,
      when,
      name: name || `${moduleName} ${actions.length + 1}`,
      hitbox: hitboxMatch
        ? { X: Number(hitboxMatch[1]), Y: Number(hitboxMatch[2]), Z: Number(hitboxMatch[3]) }
        : { X: 0, Y: 0, Z: 0 },
      ihbc: ignoreHitbox,
    });
  }
  return actions;
}

function convertTiming(source, category, moduleActions) {
  const rawId = category === "part"
    ? source.pname
    : category === "effect"
      ? source.ename ?? source._id
      : source._id;
  const id = category === "animation" || category === "sound"
    ? cleanAssetId(rawId)
    : String(rawId ?? source.name ?? "");
  return {
    id,
    name: String(source.name || id),
    detector: category,
    tag: String(source.tag || "Undefined"),
    minDistance: Math.max(0, Number(source.imdd) || 0),
    maxDistance: Math.max(0, Number(source.imxd) || 0),
    hitbox: vector(source.hitbox),
    hitboxOffset: Number(source.hso) || 0,
    delayUntilHitbox: source.duih === true,
    punishableWindow: Math.max(0, Number(source.punishable) || 0),
    afterWindow: Math.max(0, Number(source.after) || 0),
    repeatStartDelay: Math.max(0, (Number(source.rsd) || 0) / 1000),
    repeatDelay: Math.max(0, (Number(source.rpd) || 0) / 1000),
    preferRepeat: source.rpue === true,
    allowAttacking: source.aatk === true,
    facingHitbox: source.fhb !== false,
    noDodgeFallback: source.ndfb === true,
    noBlockFallback: source.nbfb === true,
    noVentFallback: source.nvfb === true,
    blockFallbackHold: Math.max(0, Number(source.bfht) || 0.3),
    preferBlockFallback: source.pbfb === true,
    sourceModule: source.umoa === true ? String(source.smod || "") : "",
    preferModule: source.umoa === true,
    ignoreAnimationEnd: source.iae === true,
    ignoreEarlyAnimationEnd: source.ieae === true,
    maxAnimationTime: Math.max(0, (Number(source.mat) || 0) / 1000),
    pastHitbox: source.phd === true,
    predictFacing: source.pfh === true,
    historySeconds: Math.max(0, Number(source.phds) || 0),
    predictionSeconds: Math.max(0, Number(source.pfht) || 0),
    disablePrediction: source.dp === true,
    useHitboxCFrame: source.uhc === true,
    allowLocalPlayer: source.alp === true,
    ignoreLocalPlayer: source.ilp === true,
    forceLocalPlayer: source.flp === true,
    probability: {},
    actions: convertActions(source.actions?.length ? source.actions : moduleActions),
  };
}

const timingDirectory = process.argv[2];
const outputPath = process.argv[3];
if (!timingDirectory || !outputPath) {
  console.error("Usage: node scripts/convert-lycoris-timings.mjs <Lycoris Timings dir> <output.json>");
  process.exit(2);
}

const basePath = path.join(timingDirectory, "base.txt");
const database = decodeMessagePack(await readFile(basePath));
const modulesDirectory = path.resolve(timingDirectory, "..", "Modules");
const patchFiles = (await readdir(timingDirectory))
  .filter((name) => /^patch_.*\.json$/i.test(name));
const patches = [];
for (const name of patchFiles) {
  const data = JSON.parse(await readFile(path.join(timingDirectory, name), "utf8"));
  patches.push({ name, timestamp: String(data.timestamp ?? ""), data });
}
patches.sort((first, second) => first.timestamp.localeCompare(second.timestamp) || first.name.localeCompare(second.name));
for (const patch of patches) applyPatch(database, patch.data);

const moduleNames = new Set(
  ["animation", "sound", "part", "effect"]
    .flatMap((category) => database[category] ?? [])
    .filter((timing) => timing.umoa === true)
    .map((timing) => String(timing.smod || ""))
    .filter(Boolean),
);
const moduleActionMap = new Map();
for (const moduleName of moduleNames) {
  moduleActionMap.set(moduleName, await extractModuleActions(modulesDirectory, moduleName));
}

const timings = {};
for (const category of ["animation", "sound", "part", "effect"]) {
  const byId = new Map();
  for (const source of database[category] ?? []) {
    const converted = convertTiming(source, category, moduleActionMap.get(String(source.smod || "")) ?? []);
    if (converted.id) byId.set(converted.id, converted);
  }
  timings[category] = [...byId.values()].sort((first, second) => first.name.localeCompare(second.name));
}

const output = {
  version: 1,
  provenance: {
    format: "CLAW MARK timing database",
    source: "user-supplied Lycoris timing tree",
    patchesApplied: patches.length,
    staticModuleTemplates: [...moduleActionMap.values()].filter((actions) => actions.length > 0).length,
  },
  timings,
};
await mkdir(path.dirname(path.resolve(outputPath)), { recursive: true });
await writeFile(outputPath, `${JSON.stringify(output, null, 2)}\n`, "utf8");
const count = Object.values(timings).reduce((total, profiles) => total + profiles.length, 0);
console.log(`Converted ${count} timing profiles with ${patches.length} patch(es) -> ${outputPath}`);
