# Memory Space Nearby Bridge

This native Mac receiver lets Memory Space sync directly to a nearby Mac. It uses Apple peer-to-peer Wi-Fi discovery and transfer, so neither device needs to join a normal Wi-Fi network or use the internet.

Both devices must have Wi-Fi and Bluetooth turned on and be close together.

## Start the nearby receiver

```sh
cd /Users/etienneduplessix/Developement/perso/memory-space-ios/memory-space-nearby-bridge
swift run MemorySpaceNearbyBridge
```

Keep this Terminal window open. It prints a pairing token. The token is used to encrypt and authenticate every nearby transfer.

On the iPhone, open **Memory Space → Privacy → Sync to Mac**, enter the token once, select the discovered Mac, and tap **Sync**.

The receiver writes the synced local mirror to the same location used by the MCP server:

```text
~/Library/Application Support/MemorySpaceBridge
```

## MCP access

The existing Node MCP server reads that mirror. Install its dependencies once, then configure your agent to launch:

```sh
cd /Users/etienneduplessix/Developement/perso/memory-space-ios/memory-space-bridge
npm install
node src/mcp-server.mjs
```

The nearby receiver and the MCP server do not require a home Wi-Fi connection or internet access.
