# First-Sync Date Cutoff for Dive Computer Downloads

**Date:** 2026-08-04
**Status:** Approved

## Problem

A user who imports their dive history from another logbook (e.g., Subsurface
UDDF/XML export) and then connects their dive computer gets a full download of
every dive on the device. The incremental-download mechanism relies on
`lastDiveFingerprint` — opaque device-native bytes captured from a previously
*downloaded* dive — which a file import cannot provide. libdivecomputer has no
"download since date" concept; the fingerprint is the only stop mechanism.

Today the consequences are:

- The first connect transfers every dive on the device (slow over BLE for
  hundreds of dives).
- The review step lists hundreds of matched duplicates.
- If the user cancels at the download step out of confusion, the fingerprint is
  never persisted, and the full download recurs on every connect.

Duplicate protection already works: the download matcher
(`findMatchingDiveWithScore`, SQL ±5 min gate) matches downloaded dives against
imported ones and the wizard defaults them to skip/consolidate. On normal
wizard completion the fingerprint is advanced from **all** downloaded dives
(`dive_computer_adapter.dart`, `_updateComputerAfterImport`), so the flow
self-heals after one full run-through. The problem is the cost and confusion of
that first run.

## Goals

- After a file import, the first computer connect should download only recent
  dives, not the whole device.
- Seed the fingerprint from that short download so all later syncs are
  incremental.
- No changes to the vendored libdivecomputer fork or native protocol request
  order (hard lesson from issue #621: a protocol-order change broke all real
  Shearwater downloads).

## Non-Goals

- Native/manifest-level skipping of old records (rejected: protocol-order risk,
  needs per-family hardware validation).
- Changing duplicate-matching or consolidation behavior.
- Importing fingerprints from Subsurface data (not present in its exports).

## Design Overview

Two tiers, sharing one cutoff concept:

- **Tier 1 (all backends):** an import-stage date filter. The full download
  still runs, but dives at-or-before the cutoff are auto-marked skip and
  collapsed in the review list.
- **Tier 2 (newest-first backends; `shearwater_petrel` family initially):**
  app-side early-stop. Dives stream newest-first; when a delivered dive's start
  time is at-or-before the cutoff, the transfer is stopped and treated as a
  successful completion. The stopped prefix is a true newest high-water mark,
  so the existing fingerprint persistence makes future syncs incremental.

### Cutoff semantics

- Active only when the selected computer has **no** `lastDiveFingerprint`, the
  active diver's log has at least one dive, and "New dives only" is on.
- Default: start time of the newest dive in the active diver's log
  (diverId-scoped). Editable via a date picker on the download step.
- Stop/skip condition: `dive.startTime <= cutoff`.
- The boundary dive that triggers the stop (the "sentinel") is deliberately
  downloaded. It is usually the device's copy of the newest logged dive: the
  duplicate matcher absorbs it (skip/consolidate), and it guarantees at least
  one fingerprinted dive even when the device holds zero new dives.
- Timestamp fuzz between the imported copy and the device copy is absorbed by
  the ±5 min matcher; the stop condition needs no extra tolerance.

## UX

**Download step** (`DownloadStepWidget` / `dc_adapter_steps.dart`):

- No-fingerprint case with non-empty log: the "New dives only" toggle gains a
  subtitle row — "Only download dives after 12 Jun 2026" — tappable to open a
  date picker. Wizard-local edit overrides the default.
- Fingerprint present, or empty log: no cutoff row; behavior unchanged.
- "Download all" chosen: cutoff ignored entirely.
- Early stop is presented as success: "Stopped — remaining dives are already in
  your log", not an error or cancellation.

**Review step:** dives at-or-before the cutoff are auto-marked skip and
collapsed into one expandable summary row: "N older dives skipped — already in
your log". Only genuinely new dives are listed individually.

**Recovery path:** the existing "Download all" toggle remains the way to fetch
older dives later.

## Components

### `DownloadState` / `DownloadNotifier` (`download_providers.dart`)

- New fields: `sinceCutoff: DateTime?`, `earlyStopReason` (enum:
  `none | cutoffReached`). `startDownload` accepts the cutoff (null =
  inactive). `earlyStopReason` resets on every `startDownload`.
- In the `DiveDownloadedEvent` case: if a cutoff is active, the backend is in
  the newest-first capability set, and the ordering guard holds, a dive with
  `startTime <= cutoff` sets `earlyStopReason = cutoffReached` and then calls
  `_service.cancelDownload()`. When the native cancellation event arrives, the
  flag maps it to `DownloadPhase.complete` instead of `cancelled` — reusing the
  entire downstream complete path (wizard advance, fingerprint persistence,
  device-info write).
- **Ordering guard:** track the previously delivered `startTime`; if any dive
  arrives newer than its predecessor, permanently disable early-stop for the
  session and log it. The download runs to natural completion and tier 1
  filtering applies. A wrong capability-set entry degrades to today's
  behavior; it cannot lose dives.
- If `cancelDownload()` throws, log and let the download continue to
  completion (degrades to tier 1).

### Backend capability set (new file under `dive_computer/domain/`)

A const set / pure function keyed on the libdivecomputer descriptor family,
initially containing only the `shearwater_petrel` family (Teric, Perdix,
Petrel, Peregrine, …). Deliberately conservative: unlisted backends get
tier 1 only.

### Cutoff default provider

A provider returning the newest dive `startTime` for the active diver
(diverId-scoped; watch the orphan-scoping trap). Feeds the download step's
default; user edits live in wizard-local state.

### `DiveComputerAdapter` (`dive_computer_adapter.dart`)

- Receives the cutoff. Unmatched dives with `startTime <= cutoff` default to
  `DuplicateAction.skip`; matched dives keep their existing defaults.
- The early-stopped path arrives marked complete, so the existing
  `wasCancelled ? processedDives : _downloadedDives` logic advances the
  fingerprint from all downloaded dives — a true high-water mark because
  delivery was verified newest-first. No change to fingerprint persistence
  code.
- User-cancel semantics untouched.

### Unchanged

Vendored fork, native download loop, `selectNewestFingerprint`, the ±5 min
matcher, consolidation.

## Edge Cases

- Empty log or fingerprint present: no cutoff row, identical to today.
- Cutoff edited to a future date: first delivered dive is the sentinel; one
  dive downloaded, fingerprint seeded. "Download all" recovers skipped dives.
- Out-of-order delivery detected: early-stop disabled mid-flight; full
  download completes; tier 1 filter still applies. No data loss possible.
- Dives with null fingerprints: `selectNewestFingerprint` already skips them.
- User cancel during an early-stop-armed download: still a cancel; fingerprint
  advances only through processed dives.

## Testing

Follow existing patterns (mock repos for adapter tests, no real DB):

- **Unit:** ordering guard (in-order, out-of-order, equal timestamps); stop
  condition boundary (`<=`); capability-set membership; cutoff provider
  diverId scoping.
- **Notifier:** early-stop maps native cancellation to `complete`; user cancel
  still maps to `cancelled`; `earlyStopReason` reset between downloads;
  `cancelDownload()` failure degrades to full download.
- **Adapter:** auto-skip marking at/below cutoff; fingerprint advanced from
  the full downloaded set on early-stop; skipped-count reporting.
- **Widget:** cutoff row visibility rules; date picker roundtrip; review
  summary row collapse/expand.
- **l10n:** new keys translated in all 11 locales.

Hardware smoke on a real Shearwater before release, per the #621 convention:
early-stop only issues a cancel — a request pattern every client already
issues — but the complete-vs-cancelled mapping deserves an on-device check.
