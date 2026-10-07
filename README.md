# Sight Words (iOS)

A reading app for two young readers, from zero reading comprehension (letter sounds, digraphs) up to
whole paragraphs. SwiftUI, iOS 17+, with on-device AI via Apple's Foundation Models framework on iOS 26+.

## What's in it

| Feature | How |
|---|---|
| 8-stage curriculum | Letter sounds → digraphs → CVC words → digraph words → Dolch sight words (×2) → sentences → stories (`Curriculum.swift`) |
| Works with no reading ability | "Listen and tap" and "build the word from tiles" activities come first; reading aloud is unlocked only after repeated success |
| Spaced repetition | SM-2 tuned for young kids: hour/day-scale first intervals, gentle lapse penalty, "mastered" at a 21-day interval (`SRS.swift`) |
| Text-to-speech | `AVSpeechSynthesizer`, on-device voices. Speaker button on every screen, letter sounds via IPA, "sound it out" mode, word-by-word highlight when reading stories |
| On-device speech check | `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`; falls back to ✓ / ✗ buttons |
| Apple Foundation Models | Story Maker (stories built from words the child has learned, validated against their vocabulary, retried, then falls back to the library) and a parent Coach (`AIService.swift`). Availability is always checked |
| Multiple children | One parent login, a profile per reader |
| Custom words | Parents add names/words that join the SRS queue |
| Grown-up gate | Settings, account, and add-reader sit behind a multiplication question |
| Offline-first | Everything saves locally first and syncs to NCB when online |

## Backend: NoCodeBackend

Database `53722_zossoz_sight_words` (tables: `children`, `item_progress`, `review_log`, `custom_words`,
`passage_attempts`, plus NCB's auth tables). Full OpenAPI spec: `Docs/ncb-swagger.json`.

**There is no secret key in the app.** NCB's data API accepts the signed-in user's session token as a
Bearer token and applies row-level security by `user_id` on the server, so a parent can only touch their own
rows. (Verified against the live API: create, read, update, delete, filtered reads, cascade delete.)
Keep the database's `NCB_SECRET_KEY` out of this repo; the app does not need it.

Sync (`AppStore.swift`): children are pushed first (other rows reference their server id), then progress,
custom words, and append-only review logs / passage attempts in bulk. A pull merges server rows; local unsynced
edits win until pushed.

## Build

Requires Xcode 26 on a Mac (the Foundation Models framework ships in the iOS 26 SDK).

```sh
brew install xcodegen
cd ios
xcodegen            # generates SightWords.xcodeproj from project.yml
open SightWords.xcodeproj
```

Set your signing team, then run on a **real device** for the best experience:

- Foundation Models needs an Apple Intelligence device with Apple Intelligence enabled.
- The simulator's speech voices and on-device recognition are limited.

Tip: download an *Enhanced* or *Premium* voice in Settings → Accessibility → Spoken Content → Voices.
The reader's voice and speed can be set per child in the Grown-ups area.

## Status

The code was written without access to a Swift toolchain, so it has **not been compiled**. Expect to fix a
few compile errors on first build. Not yet done: app icon artwork, unit tests, password reset in-app
(use the NCB dashboard for now), and syncing AI-written stories (they are stored on-device only).

## Decisions worth revisiting

- Public sign-up is still enabled on the NCB database. Once both parents have accounts, turn it off in the NCB
  dashboard.
- Child data is treated as sensitive: no analytics, no third-party SDKs, speech recognition is forced on-device.
