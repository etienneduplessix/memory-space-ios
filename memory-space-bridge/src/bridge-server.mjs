import crypto from "node:crypto";
import fs from "node:fs/promises";
import http from "node:http";
import os from "node:os";
import path from "node:path";

const port = Number.parseInt(process.env.MEMORY_SPACE_BRIDGE_PORT ?? "8787", 10);
const storeDirectory = process.env.MEMORY_SPACE_BRIDGE_DIR
  ?? path.join(os.homedir(), "Library", "Application Support", "MemorySpaceBridge");
const configurationPath = path.join(storeDirectory, "configuration.json");
const snapshotPath = path.join(storeDirectory, "memory-space.json");
const attachmentsDirectory = path.join(storeDirectory, "attachments");
const maximumPayloadBytes = 40 * 1024 * 1024;

await fs.mkdir(attachmentsDirectory, { recursive: true });
const configuration = await loadOrCreateConfiguration();

const server = http.createServer(async (request, response) => {
  try {
    const url = new URL(request.url ?? "/", `http://${request.headers.host ?? "localhost"}`);

    if (request.method === "GET" && url.pathname === "/v1/health") {
      return sendJSON(response, 200, { status: "ok", service: "Memory Space Bridge" });
    }

    if (request.method === "POST" && url.pathname === "/v1/sync") {
      if (!isAuthorized(request)) {
        return sendJSON(response, 401, { error: "The pairing token is not valid." });
      }

      const payload = await readJSONBody(request);
      if (!Array.isArray(payload.captures)) {
        return sendJSON(response, 400, { error: "The sync payload must include a captures array." });
      }

      const snapshot = await writeSnapshot(payload);
      return sendJSON(response, 200, {
        receivedCaptures: snapshot.captures.length,
        updatedAt: snapshot.updatedAt
      });
    }

    return sendJSON(response, 404, { error: "Not found." });
  } catch (error) {
    console.error(error);
    return sendJSON(response, 500, { error: "Memory Space Bridge could not process the request." });
  }
});

server.listen(port, "0.0.0.0", () => {
  console.log("Memory Space Bridge is ready.");
  console.log("On your iPhone, open Memory Space → Privacy → Sync to Mac.");
  for (const address of localAddresses()) {
    console.log(`Mac address: http://${address}:${port}`);
  }
  console.log(`Pairing token: ${configuration.pairingToken}`);
  console.log("Use only on a trusted private Wi-Fi network.");
});

async function loadOrCreateConfiguration() {
  try {
    return JSON.parse(await fs.readFile(configurationPath, "utf8"));
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
    const newConfiguration = {
      pairingToken: crypto.randomBytes(24).toString("base64url"),
      createdAt: new Date().toISOString()
    };
    await writeJSON(configurationPath, newConfiguration);
    return newConfiguration;
  }
}

function isAuthorized(request) {
  const candidate = request.headers.authorization?.replace(/^Bearer\s+/i, "") ?? "";
  const expectedBuffer = Buffer.from(configuration.pairingToken);
  const candidateBuffer = Buffer.from(candidate);
  return candidateBuffer.length === expectedBuffer.length
    && crypto.timingSafeEqual(candidateBuffer, expectedBuffer);
}

async function readJSONBody(request) {
  const chunks = [];
  let length = 0;

  for await (const chunk of request) {
    length += chunk.length;
    if (length > maximumPayloadBytes) {
      const error = new Error("The sync payload is too large.");
      error.statusCode = 413;
      throw error;
    }
    chunks.push(chunk);
  }

  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

async function writeSnapshot(payload) {
  const captures = [];
  for (const capture of payload.captures) {
    if (!isValidCapture(capture)) continue;

    const storedCapture = {
      id: capture.id,
      createdAt: capture.createdAt,
      kind: capture.kind,
      title: capture.title ?? "Untitled capture",
      bodyText: capture.bodyText ?? "",
      tagsText: capture.tagsText ?? "",
      collectionName: capture.collectionName ?? "Inbox",
      parentCaptureID: capture.parentCaptureID ?? null,
      durationSeconds: Number(capture.durationSeconds ?? 0),
      isProcessing: Boolean(capture.isProcessing),
      transcriptionNotice: capture.transcriptionNotice ?? null,
      imagePath: null
    };

    if (typeof capture.imageBase64 === "string" && capture.imageBase64.length > 0) {
      const imageData = Buffer.from(capture.imageBase64, "base64");
      if (imageData.length > 0 && imageData.length <= 8 * 1024 * 1024) {
        const fileName = `${capture.id}.jpg`;
        await fs.writeFile(path.join(attachmentsDirectory, fileName), imageData);
        storedCapture.imagePath = path.join("attachments", fileName);
      }
    }

    captures.push(storedCapture);
  }

  const snapshot = {
    schemaVersion: 1,
    deviceName: typeof payload.deviceName === "string" ? payload.deviceName : "iPhone",
    updatedAt: new Date().toISOString(),
    captures,
    customBlocks: decodeCustomBlocks(payload.customBlocksData)
  };
  await writeJSON(snapshotPath, snapshot);
  return snapshot;
}

function isValidCapture(capture) {
  return capture
    && typeof capture.id === "string"
    && typeof capture.createdAt === "string"
    && typeof capture.kind === "string";
}

function decodeCustomBlocks(encodedBlocks) {
  if (typeof encodedBlocks !== "string" || encodedBlocks.length === 0) return [];
  try {
    const decoded = Buffer.from(encodedBlocks, "base64").toString("utf8");
    const blocks = JSON.parse(decoded);
    if (!Array.isArray(blocks)) return [];
    return blocks
      .filter((block) => typeof block?.id === "string" && typeof block?.title === "string")
      .map((block) => ({
        id: block.id,
        title: block.title,
        keywordsText: typeof block.keywordsText === "string" ? block.keywordsText : "",
        createdAt: block.createdAt ?? null
      }));
  } catch {
    return [];
  }
}

async function writeJSON(filePath, value) {
  const temporaryPath = `${filePath}.tmp`;
  await fs.writeFile(temporaryPath, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 });
  await fs.rename(temporaryPath, filePath);
}

function localAddresses() {
  const addresses = [];
  for (const entries of Object.values(os.networkInterfaces())) {
    for (const entry of entries ?? []) {
      if (entry.family === "IPv4" && !entry.internal) addresses.push(entry.address);
    }
  }
  return addresses.length > 0 ? addresses : ["127.0.0.1"];
}

function sendJSON(response, statusCode, body) {
  response.writeHead(statusCode, { "Content-Type": "application/json; charset=utf-8" });
  response.end(JSON.stringify(body));
}
