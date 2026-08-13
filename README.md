# Memory Space

An iPhone-only, local-first personal capture app.

It currently supports local voice recordings, photo capture/import, on-device OCR text extraction, on-device speech transcription when the selected system language supports it, an inbox, collections, and search.

## Screenshot shortcut

To make the Action Button capture the current screen, create a shortcut containing **Take Screenshot**, **Save to Photo Album**, and **Finish Screenshot Capture**, then assign that shortcut in **Settings → Action Button → Shortcut**. No variables are needed. The app imports the newest screenshot locally, extracts its text, and opens Quick Capture for an additional note or voice recording. On first use, grant Memory Space **Full Access** to Photos so it can read the screenshot that you explicitly saved.

## Open and run

Open `MemorySpace.xcodeproj` in Xcode, select your iPhone, select your Personal Team under **Signing & Capabilities**, then press Run.

No server, analytics SDK, or cloud account is part of this project.
