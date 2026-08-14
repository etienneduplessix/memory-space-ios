import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const storeDirectory = process.env.MEMORY_SPACE_BRIDGE_DIR
  ?? path.join(os.homedir(), "Library", "Application Support", "MemorySpaceBridge");
const snapshotPath = path.join(storeDirectory, "memory-space.json");

const server = new McpServer({
  name: "memory-space",
  version: "0.1.0"
});

server.registerTool(
  "recent_captures",
  {
    title: "Recent Memory Space captures",
    description: "List recent screenshot groups, notes, and voice transcripts synced from the paired iPhone.",
    inputSchema: {
      limit: z.number().int().min(1).max(50).optional().default(15)
    }
  },
  async ({ limit }) => {
    const snapshot = await readSnapshot();
    const captures = rootCaptures(snapshot)
      .sort((left, right) => new Date(right.createdAt) - new Date(left.createdAt))
      .slice(0, limit)
      .map((capture) => captureWithLinks(snapshot, capture));
    return jsonResult(captures);
  }
);

server.registerTool(
  "search_memory",
  {
    title: "Search Memory Space",
    description: "Search screenshot text, notes, voice transcripts, tags, and titles from the paired iPhone.",
    inputSchema: {
      query: z.string().min(1).describe("Words or a phrase to find."),
      limit: z.number().int().min(1).max(50).optional().default(20)
    }
  },
  async ({ query, limit }) => {
    const snapshot = await readSnapshot();
    const normalizedQuery = query.toLowerCase();
    const captures = rootCaptures(snapshot)
      .filter((capture) => searchableText(snapshot, capture).includes(normalizedQuery))
      .sort((left, right) => new Date(right.createdAt) - new Date(left.createdAt))
      .slice(0, limit)
      .map((capture) => captureWithLinks(snapshot, capture));
    return jsonResult(captures);
  }
);

server.registerTool(
  "list_memory_blocks",
  {
    title: "List Memory Space blocks",
    description: "List custom Smart Blocks created on the paired iPhone, including the current matching captures."
  },
  async () => {
    const snapshot = await readSnapshot();
    const blocks = (snapshot.customBlocks ?? []).map((block) => ({
      ...block,
      captures: rootCaptures(snapshot)
        .filter((capture) => blockMatches(snapshot, block, capture))
        .map((capture) => captureWithLinks(snapshot, capture))
    }));
    return jsonResult(blocks);
  }
);

server.registerTool(
  "get_capture",
  {
    title: "Get a Memory Space capture",
    description: "Get the complete local text, linked notes, transcripts, and an optional local screenshot path for one capture.",
    inputSchema: {
      id: z.string().describe("The capture ID returned by recent_captures or search_memory.")
    }
  },
  async ({ id }) => {
    const snapshot = await readSnapshot();
    const capture = snapshot.captures?.find((item) => item.id === id);
    if (!capture) {
      return {
        content: [{ type: "text", text: `No synced capture exists with ID ${id}.` }],
        isError: true
      };
    }
    return jsonResult(captureWithLinks(snapshot, capture));
  }
);

await server.connect(new StdioServerTransport());
console.error("Memory Space MCP server connected over stdio.");

async function readSnapshot() {
  try {
    return JSON.parse(await fs.readFile(snapshotPath, "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") {
      throw new Error("No Memory Space data is synced yet. Start Memory Space Bridge and tap Sync to Mac on the iPhone.");
    }
    throw error;
  }
}

function rootCaptures(snapshot) {
  return (snapshot.captures ?? []).filter((capture) => !capture.parentCaptureID);
}

function linkedCaptures(snapshot, capture) {
  return (snapshot.captures ?? []).filter((item) => item.parentCaptureID === capture.id);
}

function captureWithLinks(snapshot, capture) {
  const linkedItems = linkedCaptures(snapshot, capture).map((item) => captureWithLinks(snapshot, item));
  return {
    ...capture,
    imagePath: capture.imagePath ? path.join(storeDirectory, capture.imagePath) : null,
    linkedItems
  };
}

function searchableText(snapshot, capture) {
  return [capture.title, capture.bodyText, capture.tagsText, ...linkedCaptures(snapshot, capture).flatMap((item) => [item.title, item.bodyText, item.tagsText])]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();
}

function blockMatches(snapshot, block, capture) {
  const terms = [
    ...String(block.title ?? "").split(/[^\p{L}\p{N}]+/u),
    ...String(block.keywordsText ?? "").split(/[\n,]+/)
  ]
    .map((term) => term.trim().toLowerCase())
    .filter((term) => term.length > 2);
  return terms.some((term) => searchableText(snapshot, capture).includes(term));
}

function jsonResult(value) {
  return {
    content: [{ type: "text", text: JSON.stringify(value, null, 2) }]
  };
}
