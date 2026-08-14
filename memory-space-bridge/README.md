# Memory Space Bridge

This is the Mac-side companion for the Memory Space iPhone app. It keeps a local mirror of your synced captures and exposes read-only MCP tools to an agent on the same Mac.

## Start the local bridge

```sh
cd memory-space-bridge
npm install
npm run bridge
```

The bridge prints a Mac address and pairing token. On the iPhone, open **Memory Space → Privacy → Sync to Mac**, enter both values, tap **Test connection**, then **Sync to Mac now**.

Only use the first version on a trusted private Wi-Fi network. It uses a pairing token but does not yet provide TLS or automatic background syncing.

The local mirror is stored in:

```text
~/Library/Application Support/MemorySpaceBridge
```

It contains capture text, Smart Blocks, and compressed screenshot/image copies. Voice recordings remain only on the iPhone; their local transcripts sync.

## Run the MCP server

After the first sync, configure your local MCP host to launch:

```sh
node /Users/etienneduplessix/Developement/perso/memory-space-ios/memory-space-bridge/src/mcp-server.mjs
```

It communicates through standard input/output and provides these read-only tools:

- `recent_captures`
- `search_memory`
- `list_memory_blocks`
- `get_capture`
