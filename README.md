# Memory Space

An iPhone-only, local-first personal capture app.

It currently supports local voice recordings, photo capture/import, on-device OCR text extraction, on-device speech transcription when the selected system language supports it, an inbox, Timeline, Smart Blocks, collections, and search.

## Screenshot shortcut

To make the Action Button capture the current screen, create a shortcut containing **Take Screenshot**, **Save to Photo Album**, and **Finish Screenshot Capture**, then assign that shortcut in **Settings → Action Button → Shortcut**. No variables are needed. The app imports the newest screenshot locally, extracts its text, and opens Quick Capture for an additional note or voice recording. On first use, grant Memory Space **Full Access** to Photos so it can read the screenshot that you explicitly saved.

## Open and run

Open `MemorySpace.xcodeproj` in Xcode, select your iPhone, select your Personal Team under **Signing & Capabilities**, then press Run.

## Optional local nearby Mac sync and MCP

The preferred companion is [memory-space-nearby-bridge/README.md](memory-space-nearby-bridge/README.md). It transfers a local mirror directly to a nearby Mac with Wi-Fi and Bluetooth radios, but without joining a Wi-Fi network or using the internet. On the iPhone, open **Memory Space → Privacy → Sync to Mac**, enter the pairing token once, then select the nearby Mac and tap **Sync**.

[memory-space-bridge/README.md](memory-space-bridge/README.md) remains available as a same-Wi-Fi fallback using an IP address.

The bridge exposes read-only MCP tools to a local agent on the same Mac. The app has no cloud service, analytics SDK, or remote backend.
