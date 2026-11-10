# YT + YT Music Clone (Flutter) — Endpoint Hit-List & Implementation Plan

Research date: **2026-10-31** (rev 4: + SourecResource stream/lyrics engine 6.2; rev 3: YouPipe Music 6.1; video target 1080p). Targets: **Android + Windows/macOS/Linux**. Core: **pure Dart**. State: **Riverpod**. DB: **Drift**. No backend, no Google login, every request goes from the user's device on the user's own IP.

> Status legend: ✅ = verified in current source of an actively maintained project (yt-dlp 2026-10-29, NewPipeExtractor 2026-10-26, Metrolist/innertubex 2026-10-22/25, ytmusicapi 2026-10-12). 🧪 = must pass `tool/probe.dart` (section 15) on your machine. I could NOT run live calls (my sandbox blocks youtube.com), so every 🧪 item is unconfirmed until you run the probe.

---

## 0. Verdict (read first)

| Question | Answer |
|---|---|
| Can one pub package do everything? | **No.** |
| `youtube_explode_dart` 3.1.0 (2026-05-09) | Good for metadata/search/captions/comments, but **stream extraction is the weak point**. Default client = `androidSdkless` (ANDROID). In Oct 2026 Metrolist marks ANDROID as "SABR-only, no direct URLs" and yt-dlp no longer uses it. Open issue #386 (2026-07-31): "Video and audio streams return 403". Its JS solver ships for **Deno only** (no Deno on Android). It sends `X-Youtube-Client-Name` as a string (yt-dlp sends the numeric id) and attaches `visitorData` only for IOS. → **Don't use it for stream URLs.** It's an optional fallback/reference. |
| `kmep` 0.3.0 (2026-09-10, 1 version, 217 downloads, GPL-3) | Clients: ANDROID_VR 1.65.10 / IOS / WEB / WEB_SAFARI / TV. **No visionOS.** yt-dlp says ANDROID_VR returns 403 on every format since 2026-08-17. It also has a `backend/` remote-config server, which conflicts with your no-central-server rule. → Reference only. Its `flutter_integration/flutter_js_runtime.dart` is useful for the JS-solver design (QuickJS needs a 32 MB stack; run it off the UI isolate). |
| `dart_ytmusic_api` / `ytmusicapi_dart` | Small and partial, with known broken methods. → Use **ytmusicapi (Python)** as the reference spec and port the request/parse logic yourself. |
| NewPipeExtractor | Java. Android-only through a platform channel, ruled out. Use it as a **reference spec** (its current stream client is visionOS). |
| **YouPipe** 1.0.6 (2026-10-06) + **YouPipe Music** (2026-10-12) — live Flutter apps | **Android only.** Browse/search/home use pure-Dart InnerTube (WEB / WEB_REMIX). **Streams use NewPipeExtractor v0.26.5 (Kotlin platform channel)**, played by ExoPlayer via `video_player` from a locally built DASH MPD. That's the path you ruled out ("pure Dart"), and it can't run on desktop. Playback Auto ≤1080p (VP9 up to 4K only with a HW decoder). **Downloads ≤1080p** (H.264+AAC muxed with Android `MediaMuxer`), same as your 1080p target. **No LICENSE file**, so it's all-rights-reserved: read it, don't copy code. Full findings in **0.1**. |
| **Decision** | Write your own thin **InnerTube layer in Dart** (`dio`), porting **NewPipeExtractor master's** stream request (VISIONOS only since 2026-08). Endpoints and constants below come from yt-dlp, NewPipeExtractor, Metrolist/innertubex, ytmusicapi and YouPipe docs. Android-only fallback if the Dart port fails the probe on a device: the YouPipe pattern (NewPipeExtractor bridge). Then desktop has no streams. |

**Stream URL primary client (Oct 2026): `VISIONOS`.** yt-dlp uses it as its default and only JS-less client (`_DEFAULT_JSLESS_CLIENTS = ('visionos',)`), NewPipeExtractor's stream extractor uses it, and Metrolist's Oct 2026 device benchmark found it the fastest. It needs **no PO token and no JS**, but it requires `visitorData`. It **can't play** "made for kids" or age-restricted videos.

---

## 0.1 YouPipe / YouPipe Music findings (from their repos + docs, tested on a device 2026-09-29…10-12)

| # | Finding (their docs) | Action in this plan |
|---|---|---|
| F1 | Own InnerTube `/player` with **IOS/ANDROID** + visitorData: **googlevideo serves only the first ~1 MB**, then 403. ANDROID_VR/ANDROID_MUSIC → `LOGIN_REQUIRED`. TVHTML5_SIMPLY "no longer supported". They never tested VISIONOS directly | Matches section 3. The probe's **5–6 MiB range row** decides it. Use VISIONOS only, never ANDROID/IOS |
| F2 | NewPipeExtractor **v0.26.5** = ANDROID `reel/reel_item_watch` + VISIONOS. DASH streams come from VISIONOS (`c=VISIONOS`), muxed 360p from ANDROID. **NewPipe master** (commit `9ed62db3`, "Remove usage of ANDROID, IOS and WEB_EMBEDDED_PLAYER clients", merged after v0.26.5) is now **VISIONOS-only, v1.04** | Port **master's** flow (section 4.3 constants). No muxed-ANDROID path. The muxed 360p itag 18 probably disappears → always use separate video+audio |
| F3 | **Bot check:** after heavy use, ANDROID gets `LOGIN_REQUIRED` "confirm you're not a bot". It's **per IP and per address family** (IPv6 blocked while IPv4 was fine). Fix: flip DNS order IPv4⇄IPv6, evict connections, retry once. Remember the choice | Add an **address-family switcher** to the Dart HTTP layer (8.3). Apply it to extraction, relay and downloads alike |
| F4 | googlevideo URLs carry **`ip=`** and **`c=`**. They play only from the same IP, with the **User-Agent of client `c=`**. A UA mismatch caused 403s (2/20) | One UA per stream source (VISIONOS UA). **Run the probe on the device that plays.** URLs from your PC fail on your phone |
| F5 | Even with the right UA, **VISIONOS DASH occasionally 403s** (~1 in 25, not repeatable) | Auto re-resolve + resume, **max 3 in a row**. The budget resets after 60 s of clean playback. Offline: retry at 5/15/30 s then every minute for ~5 min |
| F6 | **Throttling:** a single open-ended range request gets throttled to **~1.8–2× real time**, so the buffer never fills. Fix: a **loopback relay on 127.0.0.1** fetching **1 MB ranges** (a 5-min song arrives in ~2 s). The first chunk is fetched before the response head so a 403 reaches the player as HTTP 403 | **Mandatory:** pure-Dart relay (`dart:io HttpServer`, section 8.2) for audio and video on all platforms. Android: allow cleartext for 127.0.0.1 only (`network_security_config.xml`) |
| F7 | DASH: a static MPD built from `adaptiveFormats` (BaseURL + SegmentBase index/init ranges), **one codec family per MPD** (H.264 ≤1080p, VP9 above when HW decoder). ExoPlayer caps height to the display. MPD written to `<temp>/video/<id>_<maxHeight>.mpd` | Plan 8 adds an **Android player option B**: `video_player` + local MPD (proven). Desktop stays media_kit |
| F8 | Downloads: **native OkHttp, 1 MB Range chunks**, UA matching `c=`. "The earlier **Dart/dio** implementation got 403s intermittently." YouPipe (video) uses **WorkManager** + foreground data-sync notification | Likely cause: dio used a different address family/UA than extraction (F3/F4). Our Dart stack uses **one HttpClient** for extraction+download+relay. Chunk default **1 MiB** (configurable). 🧪 watch for 403s in P5 |
| F9 | Signed-out `FEwhat_to_watch` = **empty** + `feedNudgeRenderer` (WEB, MWEB, TVHTML5). `FEtrending`, `FEexplore` → HTTP 400 | Y9 confirmed empty. Use the local Home mixer (11.3) |
| F10 | Home mixer: related of the last 6 watched videos (weight 2), unwatched subs uploads ≤14 days (2), topic-chip searches (1, or 2 when nothing personal). Round-robin by weight, no repeats, skip ≥90% watched. 12-h launch cache | Adopted in 11.3 |
| F11 | Shorts: `reel/reel_watch_sequence` with `sequenceParams: "CA8%3D"` (fresh) → 1 entry, then 12/page via continuation. Signed out OK | Added as **Y19** |
| F12 | Comments: `next` → `comment-item-section` token → `next(continuation)`. Data in `frameworkUpdates.entityBatchUpdate.mutations` (`commentEntityPayload`) | Added as **Y20** (optional) |
| F13 | Unavailable YTM songs: some ATV uploads return `UNPLAYABLE` for every client. Fallback: search **Videos** for the song's music video and play its audio | Added to section 6 (M19) |
| F14 | YTM: lyrics order **LRCLIB `get` → LRCLIB `search` (closest duration) → YT `MPLY`**. SponsorBlock music uses only `music_offtopic`. Opus 251/250/249 = high/normal/low | Lyrics order updated (section 7). Music SponsorBlock = `music_offtopic` only |
| F15 | Remote config = static `config/remote.json` in the repo, read from `raw.githubusercontent.com` every ≤12 h (WEB `clientVersion` only) | Optional, and not a server. Better: auto-read the WEB version from `sw.js_data` (4.3). Kept as an option in 16 |
| F16 | YTM filter params in YouPipe Music use suffix `AWoSEAUQCRADEAQQChAOEBAQFRAR` (ytmusicapi: `AWoMEA4QChADEAQQCRAF`) | Probe tests both (M6x) |

**Quality target = 1080p (your decision, rev 3).** That's what YouPipe does: H.264 (avc1) ≤1080p for playback and downloads. VP9/AV1 and >1080p are out of scope (optional later).

---

## 1. Fixed decisions (from your answers)

- Platforms: Android, Windows, macOS, Linux. No web (CORS).
- Extraction: pure Dart, own InnerTube client.
- Dislikes: Return YouTube Dislike API (attribution required).
- Video quality: **max 1080p** (H.264/avc1 + AAC 140 → `.mp4`). Downloads merge video+audio with `ffmpeg_kit_flutter_new_min` (stream copy, no re-encode).
- Testing: Dart probe script you run locally (section 15).
- Stack: Riverpod 3 + Drift.
- Extras: background play + media notification, YTM lyrics, SponsorBlock.
- Music "profile" = local profile (name, avatar, stats, backup import/export).

---

## 2. Package matrix (versions checked on pub.dev, Oct 2026)

| Need | Package | Version / date | Platforms | Note |
|---|---|---|---|---|
| HTTP | `dio` | 5.11.1 (2026-09-04) | all | CancelToken, progress |
| State | `flutter_riverpod` + `riverpod_generator` | 3.4.3 / 4.0.9 | all | |
| DB | `drift` + `drift_flutter` | 2.35.3 (2026-10-23) / 0.3.1 | all | `driftDatabase(name:)` |
| Player (video+audio) | `media_kit`, `media_kit_video`, `media_kit_libs_video` | 1.2.6 / 2.0.1 / 1.0.7 | Android, Win, Linux, macOS | libmpv. `AudioTrack.uri()` = external audio, `SubtitleTrack.uri()/.data()` |
| Media notif Android/macOS | `audio_service` | 0.18.19 (2026-06-29) | Android, iOS, macOS, web | wrap media_kit in a `BaseAudioHandler` |
| Media notif Linux | `audio_service_mpris` | 0.2.1 (2026-03-15) | Linux | no Seek over MPRIS |
| Media notif Windows | `smtc_windows` | 1.1.0 (~2025-08) | Windows | needs rustup to build |
| Merge/remux | `ffmpeg_kit_flutter_new_min` | 3.6.7 (2026-10-05) | Android, iOS, Linux x64, macOS, Win x64 | LGPL-3.0, Android API 24+, Linux needs `libjson-glib-dev` |
| JS (fallback sig/n only) | `flutter_js` | 0.8.7 | Android (QuickJS), Win/Linux (QuickJS), macOS (JSC) | phase 6 only |
| Hash (SponsorBlock) | `crypto` | — | all | sha256 prefix |
| RSS parse | `xml` | — | all | subscription feed |
| Paths | `path_provider` | — | all | |
| Android public save (optional) | `media_store_plus` | 0.1.3 (2024-09) | Android | old, verify on targetSdk before using |
| Alt audio engine (not needed) | `just_audio` 0.10.6, `just_audio_media_kit` 2.1.0 | | | skip: one engine (media_kit) everywhere (YouPipe Music uses just_audio on Android) |
| Android video option B | `video_player` 2.14.x (ExoPlayer/media3) | | Android | local DASH MPD, proven by YouPipe (8.4) |

---

## 3. InnerTube client matrix (status Oct 2026)

Sources: yt-dlp `_base.py`/`_video.py` (2026-10-29), Metrolist `PlaybackClientCatalog.kt` notes (benchmarks 2026-08-13 / 2026-10-14), NewPipe `ClientsConstants.java`.

| Client | Use in app | Status | PO token | JS (sig/n) | Notes |
|---|---|---|---|---|---|
| **VISIONOS** (id 101) | **stream URLs (video + music)** | ✅ yt-dlp default JS-less, NewPipe primary | none | none | needs `visitorData`. No kids or age-restricted. 8K/AV1 formats reported |
| WEB (id 1) | browse/search/next/resolve_url | ✅ API-only | GVS for streams | yes | **don't use for streams** (SABR-only) |
| WEB_REMIX (id 67) | YTM browse/search/next/lyrics | ✅ | GVS for streams | yes | streams need a BotGuard token → skip for streams |
| WEB_MUSIC_ANALYTICS (id 31) | charts.youtube.com | ✅ NewPipe | — | — | trending charts |
| WEB_EMBEDDED_PLAYER (id 56) | **stream fallback** (kids content) | ✅ Metrolist "STABLE" | none | **yes** | needs `encryptedHostFlags` + embedUrl, no age-restricted. Phase 6 |
| tv / tv_samsung (TVHTML5 id 7) | — | yt-dlp default (with JS) | none | yes | Metrolist: disabled/unplayable in Aug 2026 Android probes |
| ANDROID_VR (id 28) | ❌ | dead: "ALL formats 403 since 2026-08-17" (yt-dlp PR #17461) | | | |
| ANDROID / IOS | ❌ | SABR-only, no direct URLs (Metrolist). URLs die after ~1 MB without PO token (YouPipe, 2026-09-29). Removed from NewPipe master | | | |
| ANDROID_MUSIC 7.21.50 | YTM **timed lyrics** browse only | ✅ ytmusicapi `as_mobile()` | — | — | not for streams |

**Client versions break.** Keep all client constants in `assets/innertube_clients.json`, ship updates with app releases, and allow a user-editable override in Settings (no remote server).

---

## 4. Common request rules

### 4.1 Hosts
| Host | Used for |
|---|---|
| `https://www.youtube.com/youtubei/v1/{ep}?prettyPrint=false` | WEB browse/search/next/navigation/resolve_url/visitor_id |
| `https://youtubei.googleapis.com/youtubei/v1/player?prettyPrint=false&t={12rand}&id={videoId}` | VISIONOS player (NewPipe) |
| `https://music.youtube.com/youtubei/v1/{ep}?prettyPrint=false&alt=json` | WEB_REMIX + ANDROID_MUSIC |
| `https://charts.youtube.com/youtubei/v1/browse?alt=json&prettyPrint=false` | charts |
| `https://suggestqueries-clients6.youtube.com/complete/search` | YT search suggestions |
| `https://www.youtube.com/feeds/videos.xml?channel_id=UC…` | subscription feed (RSS, latest 15) |
| `*.googlevideo.com` | media bytes |
| `i.ytimg.com/vi/{id}/{hqdefault,mqdefault,maxresdefault,sddefault}.jpg` | thumbnails |

No API key is needed (yt-dlp hardcodes none).

### 4.2 Base context (all InnerTube POSTs)
```json
{
  "context": {
    "client": { "clientName": "...", "clientVersion": "...", "hl": "en", "gl": "US",
                "utcOffsetMinutes": 0, "visitorData": "<visitorData>" , "...client extras": "" },
    "user": { "lockedSafetyMode": false },
    "request": { "useSsl": true, "internalExperimentFlags": [] }
  }
}
```

### 4.3 Client constants (copy into `innertube_clients.json`)
```json
{
  "WEB":       {"id":"1",  "clientName":"WEB","clientVersion":"2.20260805.01.00","platform":"DESKTOP",
                "ua":"Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0",
                "origin":"https://www.youtube.com"},
  "WEB_REMIX": {"id":"67", "clientName":"WEB_REMIX","clientVersion":"1.20260804.16.00","platform":"DESKTOP",
                "ua":"Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0",
                "origin":"https://music.youtube.com"},
  "ANDROID_MUSIC_LYRICS": {"clientName":"ANDROID_MUSIC","clientVersion":"7.21.50"},
  "WEB_MUSIC_ANALYTICS": {"id":"31","clientName":"WEB_MUSIC_ANALYTICS","clientVersion":"2.0",
                "origin":"https://charts.youtube.com"},
  "VISIONOS":  {"id":"101","clientName":"VISIONOS","clientVersion":"1.04","clientScreen":"WATCH",
                "platform":"MOBILE","deviceMake":"Apple","deviceModel":"RealityDevice17,1",
                "osName":"visionOS","osVersion":"26.6.0.23O770",
                "ua":"com.google.visionos.youtube/1.04(RealityDevice17,1; U; CPU visionOS 26_6_0 like Mac OS X; US)"},
  "VISIONOS_YTDLP": {"id":"101","clientName":"VISIONOS","clientVersion":"1.02",
                "deviceMake":"Apple","deviceModel":"RealityDevice17,1","osName":"visionOS","osVersion":"26.5.23O471",
                "ua":"Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"}
}
```
Sources: `VISIONOS` = NewPipe master `ClientsConstants`/`getVisionOsUserAgent` (v0.26.5, used by YouPipe, had `1.02` / `25.6.0.23O471`); `VISIONOS_YTDLP` = yt-dlp `_base.py` + Metrolist; WEB/WEB_REMIX versions = NewPipe hardcoded fallbacks (YouPipe: WEB `2.20261002.01.00` on 2026-10-03).

**Auto WEB clientVersion (NewPipe master `efd3d854`, 2026-10-20):** GET `https://www.youtube.com/sw.js_data`, strip the leading `)]}'`, JSON-decode: `data[0][2][0][0][16]` = WEB `clientVersion`, and `[13]` = visitorData (youtube_explode_dart `_extractVisitorData`). Do this at startup and fall back to the JSON constant. This removes most client-version maintenance for WEB.

### 4.4 Headers
- WEB / WEB_REMIX / analytics (yt-dlp `generate_api_headers`): `Content-Type: application/json`, `User-Agent`, `X-YouTube-Client-Name: <numeric id>`, `X-YouTube-Client-Version`, `Origin`, `Referer: <origin>/`, `X-Goog-Visitor-Id: <visitorData>`. Add cookie `SOCS=CAE=` (NewPipe consent cookie, avoids EU consent wall).
- VISIONOS player (NewPipe): `User-Agent: <visionOS UA>`, `X-Goog-Api-Format-Version: 2`, `Content-Type: application/json`.

### 4.5 visitorData ✅ (NewPipe `getVisitorDataFromInnertube`)
`POST https://www.youtube.com/youtubei/v1/visitor_id?prettyPrint=false` with the base context of the client you'll use, then read `responseContext.visitorData`. Cache it in Drift `prefs` with a ~30-day TTL (Harmony Music uses 30 days) and refresh it on UNPLAYABLE/403. Fallback: parse `ytcfg.set({...})` → `VISITOR_DATA` from the `https://music.youtube.com` HTML (ytmusicapi `get_visitor_id`).

### 4.6 Continuations
- WEB: find `continuationItemRenderer.continuationEndpoint.continuationCommand.token`, then POST the same endpoint with `{context, "continuation": token}`.
- YTM (ytmusicapi `get_continuations_2025`): body `{"continuation": token}`. Older shelves use `?ctoken=&continuation=&type=next` query params (`get_continuation_params`).

### 4.7 Parse defensively
2026 YouTube responses mix legacy renderers with view-models. Support all of: `videoRenderer`, `compactVideoRenderer`, `richItemRenderer.content.*`, `lockupViewModel` (videoId=`contentId`, title=`metadata.lockupMetadataViewModel.title.content`), `shortsLockupViewModel`, `reelItemRenderer`, `channelRenderer`, `playlistRenderer`. Build a recursive `findAll(json, key)` helper. Never hard-index deep paths without fallbacks.

---

## 5. YouTube endpoint hit list

| # | Feature | Request | Body (besides context) | Parse | Status |
|---|---|---|---|---|---|
| Y1 | visitorData | POST www `/visitor_id` | — | `responseContext.visitorData` | ✅ NewPipe |
| Y2 | Search | POST www `/search` (WEB) | `{"query":q,"params":P}` | renderers in `contents.twoColumnSearchResultsRenderer…` | ✅ NewPipe |
| Y2a | Search params | all=`8AEB`, videos=`EgIQAfABAQ%3D%3D`, channels=`EgIQAvABAQ%3D%3D`, playlists=`EgIQA_ABAQ%3D%3D` (NewPipe). YouPipe: videos `EgIQAQ%3D%3D`, **shorts `EgIQCQ%3D%3D`**, channels `EgIQAg%3D%3D`, playlists `EgIQAw%3D%3D`, **live `EgJAAQ%3D%3D`**. Best: read `searchFilterGroupRenderer` params from each response (YouPipe filter sheet) | | | ✅ NewPipe + YouPipe |
| Y3 | Search suggestions | GET `suggestqueries-clients6.youtube.com/complete/search?client=youtube&ds=yt&gl=US&q={q}&xhr=t` + `Origin/Referer: https://www.youtube.com` (NewPipe), or GET `suggestqueries.google.com/complete/search?client=firefox&ds=yt&q={q}` → plain `[q,[s…]]` (YouPipe, simpler) | — | JSON | ✅ both |
| Y4 | Watch page meta + related | POST www `/next` (WEB) | `{"videoId":id,"contentCheckOk":true,"racyCheckOk":true}` | title/owner/description: `videoPrimaryInfoRenderer`, `videoSecondaryInfoRenderer`. Like count: `segmentedLikeDislikeButtonViewModel.likeButtonViewModel.likeButtonViewModel…accessibilityText`. Related: `secondaryResults` (lockupViewModel / compactVideoRenderer) | ✅ NewPipe |
| Y5 | Channel resolve (@handle / URL) | POST www `/navigation/resolve_url` | `{"url":"https://www.youtube.com/@handle"}` | `endpoint.browseEndpoint.browseId` | ✅ NewPipe |
| Y6 | Channel home/header | POST www `/browse` | `{"browseId":"UC…"}` | header: `pageHeaderViewModel` / `c4TabbedHeaderRenderer` | ✅ |
| Y7 | Channel tabs | POST www `/browse` | `{"browseId":"UC…","params":TAB}` | `richGridRenderer` items | ✅ NewPipe `YoutubeChannelTabExtractor` |
| Y7a | TAB params | videos=`EgZ2aWRlb3PyBgQKAjoA`, shorts=`EgZzaG9ydHPyBgUKA5oBAA%3D%3D`, live=`EgdzdHJlYW1z8gYECgJ6AA%3D%3D`, releases=`EghyZWxlYXNlc_IGBQoDsgEA`, playlists=`EglwbGF5bGlzdHPyBgQKAkIA`, podcasts=`Eghwb2RjYXN0c_IGBQoDugEA` | | | ✅ |
| Y8 | Playlist | POST www `/browse` | `{"browseId":"VL"+playlistId}` | `playlistVideoRenderer` / lockup | ✅ |
| Y9 | Logged-out home | POST www `/browse` | `{"browseId":"FEwhat_to_watch"}` | `richItemRenderer` | ✅ **empty signed out** (YouPipe phase 0, 2026-10-03: only `feedNudgeRenderer` "history is off", same on WEB/MWEB/TVHTML5). Build home locally (section 11) |
| Y10 | Explore: Live | POST www `/browse` | `{"browseId":"UC4R8DWoMoI7CAwX8_LjQHig","params":"EgdsaXZldGFikgEDCKEK"}` | | ✅ NewPipe kiosk |
| Y11 | Explore: Gaming trending | POST www `/browse` | `{"browseId":"UCOpNcN46UbXVtpKMrmU4Abg","params":"Egh0cmVuZGluZw%3D%3D"}` | | ✅ |
| Y12 | Explore: Podcasts | POST www `/browse` | `{"browseId":"FEpodcasts_destination","params":"qgcCCAM%3D"}` | | ✅ |
| Y13 | Trending (old) | `FEtrending` | | | ❌ removed from YouTube on 2025-07-21 (NewPipe) |
| Y14 | Trending charts | POST `charts.youtube.com/youtubei/v1/browse?alt=json&prettyPrint=false` (WEB_MUSIC_ANALYTICS, Origin/Referer charts.youtube.com) | `{"browseId":"FEmusic_analytics_charts_home","query":"perspective=CHART_DETAILS&chart_params_country_code=US&chart_params_chart_type=TRENDING_VIDEOS"}` (also `TRENDING_MOVIES`) | `contents.sectionListRenderer.contents[0].musicAnalyticsSectionRenderer.content.videos[0].videoViews[]`. No continuation | ✅ NewPipe |
| Y15 | **Stream URLs** | POST `youtubei.googleapis.com/youtubei/v1/player?prettyPrint=false&t={rand12}&id={id}` (VISIONOS, headers 4.4) | `{"videoId":id,"cpn":CPN,"contentCheckOk":true,"racyCheckOk":true}` with `visitorData` in context | `playabilityStatus.status=="OK"`, `streamingData.adaptiveFormats[]` (`url`, `itag`, `mimeType`, `height`, `fps`, `bitrate`, `contentLength`, `audioTrack`), `streamingData.expiresInSeconds`, `captions…captionTracks[]` | ✅ NewPipe/yt-dlp · 🧪 avc1 1080p presence |
| Y15a | Stream URL fixups | append `&cpn={CPN}` (NewPipe). CPN = 16 chars from `A-Za-z0-9-_` | | | ✅ |
| Y16 | Captions | GET `captionTracks[i].baseUrl` + `&fmt=vtt` (or `json3`) | — | WebVTT text | 🧪 WEB-client timedtext needs a PO token (empty 200 otherwise). yt-dlp says subs PO is not required for its default clients (visionos is one). Fallback: Y16b |
| Y16b | Transcript fallback | POST `music.youtube.com/youtubei/v1/get_transcript` (WEB_REMIX) | `{"params": base64([0x0A, len(videoId), ...utf8(videoId)])}` (a tiny protobuf: field 1 = videoId; SourecResource `Innertube.transcript`) | `transcriptCueRenderer{startOffsetMs, cue}` → timed lines | ✅ SourecResource source · 🧪 |
| Y17 | Subscription feed | GET `feeds/videos.xml?channel_id=UC…` (no shorts: `?playlist_id=UULF`+id[2:]) | — | Atom `<entry>` ×15 (`yt:videoId`, `published`, `media:thumbnail`) | ✅ (brief 404 outages reported Jan 2026, so fall back to Y7 videos tab) |
| Y18 | Chapters | in `/next`: `playerOverlayRenderer…decoratedPlayerBarRenderer…markersMap` | | | 🧪 optional |
| Y19 | Shorts feed | POST www `/reel/reel_watch_sequence` (WEB) | `{"sequenceParams":"CA8%3D"}` fresh, then `{"continuation": token}` | `entries[].command.reelWatchEndpoint.videoId` (metadata from Y4/Y15). 1 entry first, 12/page after | ✅ YouPipe |
| Y20 | Comments (optional) | POST www `/next` | `{"videoId":id}` → token from `itemSectionRenderer` with `sectionIdentifier: comment-item-section` → `next {continuation}` | header `commentsHeaderRenderer` (count, sort tokens). Data in `frameworkUpdates.entityBatchUpdate.mutations[].payload.commentEntityPayload` (`properties.content.content`, `author.displayName/avatarThumbnailUrl/channelId`, `toolbar.likeCountNotliked/replyCount`). Replies: `commentRepliesRenderer` token | ✅ YouPipe |
| Y21 | Storyboards (seek previews) | from player response `storyboards.playerStoryboardSpecRenderer.spec` | | `|`-separated levels | 🧪 optional |

### 5.1 Stream selection
- `adaptiveFormats` with `height` → video-only. `audioQuality` present → audio-only.
- Video for player/download: **H.264 (`video/mp4; codecs="avc1…"`) only, height ≤ 1080** (target 144…1080), prefer `fps` match, highest bitrate per height (YouPipe: `groupBy(height).maxBy(bitrate)`, drop <360p from adaptive sets). Fallback to VP9 only when a video has no avc1 at all (YouPipe `avc.ifEmpty{vp9}`).
- Audio itags: 139 (AAC ~48k), 140 (AAC 128k), 249/250/251 (Opus ~50/70/160k). 141/774 are Premium-only and won't appear.
- Multi-language audio: `audioTrack.displayName`/`id`. Default = `audioTrack.audioIsDefault`.
- Legacy `formats[]` (muxed itag 18) may or may not appear. Don't rely on it.
- Each URL contains `expire=` (unix ts). Re-fetch the player response when `now > expire - 300` or on HTTP 403.

### 5.2 If VISIONOS fails (kids/age-restricted/UNPLAYABLE)
1. Refresh visitorData and retry once.
2. Try `VISIONOS_YTDLP` profile (www host, headers per 4.4 plus `X-YouTube-Client-Name: 101`).
3. Phase 6: `WEB_EMBEDDED_PLAYER` + signature/n solving through yt-dlp **EJS** (`yt.solver.lib.min.js` + `yt.solver.core.min.js`, v0.8.0, sha256-pinned like youtube_explode_dart) running in `flutter_js` (QuickJS, 32 MB stack, run in a background isolate). Implement `BaseEJSSolver.executeJavaScript` from youtube_explode_dart's interface, or write your own.
4. Otherwise show "Unavailable in this app (age/kids restricted)".

---

## 6. YouTube Music endpoint hit list (WEB_REMIX, host music.youtube.com) — source: ytmusicapi

| # | Feature | Endpoint | Body | Parse | Status |
|---|---|---|---|---|---|
| M1 | Home | `browse` | `{"browseId":"FEmusic_home"}` + continuations | `singleColumnBrowseResultsRenderer.tabs[0]…sectionListRenderer.contents[]` → `musicCarouselShelfRenderer`, `musicImmersiveCarouselShelfRenderer` | ✅ |
| M2 | Explore | `browse` | `{"browseId":"FEmusic_explore"}` | carousels keyed by header browseId: `FEmusic_new_releases_albums`, `FEmusic_moods_and_genres`, `FEmusic_new_releases_videos`, `FEmusic_top_non_music_audio_episodes` | ✅ |
| M3 | Moods & genres list | `browse` | `{"browseId":"FEmusic_moods_and_genres"}` | `musicNavigationButtonRenderer` → `clickCommand.browseEndpoint.params` | ✅ |
| M4 | Mood playlists | `browse` | `{"browseId":"FEmusic_moods_and_genres_category","params":P}` | playlists | ✅ |
| M5 | Charts | `browse` | `{"browseId":"FEmusic_charts","formData":{"selectedValues":["US"]}}` (`ZZ` = global) | | ✅ |
| M6 | Search (all) | `search` | `{"query":q}` | `tabbedSearchResultsRenderer`, `musicShelfRenderer`, `musicCardShelfRenderer` (top result) | ✅ |
| M6a | Search filters (`params`) | songs `EgWKAQIIAWoMEA4QChADEAQQCRAF` · videos `EgWKAQIQAWoMEA4QChADEAQQCRAF` · albums `EgWKAQIYAWoMEA4QChADEAQQCRAF` · artists `EgWKAQIgAWoMEA4QChADEAQQCRAF` · playlists(all) `Eg-KAQwIABAAGAAgACgBMABqChAEEAMQCRAFEAo%3D` · featured playlists `EgeKAQQoADgBagwQDhAKEAMQBBAJEAU%3D` · community playlists `EgeKAQQoAEABagwQDhAKEAMQBBAJEAU%3D` · podcasts `EgWKAQJQAWoMEA4QChADEAQQCRAF` | | built from ytmusicapi `get_search_params` (`EgWKAQ` + filter code + `AWoMEA4QChADEAQQCRAF`) | ✅ |
| M7 | Suggestions | `music/get_search_suggestions` | `{"input":q}` | `searchSuggestionsSectionRenderer.contents[]` | ✅ |
| M8 | Up next / radio queue | `next` | `{"videoId":id,"playlistId":"RDAMVM"+id,"isAudioOnly":true,"enablePersistentPlaylistPanel":true,"tunerSettingValue":"AUTOMIX_SETTING_NORMAL","watchEndpointMusicSupportedConfigs":{"watchEndpointMusicConfig":{"hasPersistentPlaylistPanel":true,"musicVideoType":"MUSIC_VIDEO_TYPE_ATV"}}}`. Radio: `params:"wAEB"`, shuffle playlist: `params:"wAEB8gECKAE%3D"` | `singleColumnMusicWatchNextResultsRenderer.tabbedRenderer.watchNextTabbedResultsRenderer` → tab0 `musicQueueRenderer.content.playlistPanelRenderer.contents[]` (`playlistPanelVideoRenderer`, or `playlistPanelVideoWrapperRenderer` with `counterpart`). Tab browseIds: lyrics `MUSIC_PAGE_TYPE_TRACK_LYRICS` (MPLY…), related `MUSIC_PAGE_TYPE_TRACK_RELATED` | ✅ |
| M9 | **Song ↔ video switch** | ⚠️ **Anonymous `next` no longer has `playlistPanelVideoWrapperRenderer.counterpart`/`segmentMap`** (YouPipe Music, checked 2026-09, for WEB_REMIX, ANDROID_MUSIC and IOS_MUSIC). Use instead: if the song `isVideo` (`musicVideoType != MUSIC_VIDEO_TYPE_ATV`) play it as-is, else `search` Videos filter `"<title> <first artist>"` → `pickMusicVideo` (6.1.6) | | positions not aligned (keep same timestamp) | ✅ YouPipe Music source |
| M10 | Lyrics (plain) | `browse` | `{"browseId":"MPLY…"}` | `musicDescriptionShelfRenderer.description` + footer (source) | ✅ |
| M11 | Lyrics (timed) | `browse` with **ANDROID_MUSIC 7.21.50** context | `{"browseId":"MPLY…"}` | `contents.elementRenderer.newElement.type.componentType.model.timedLyricsModel.lyricsData.timedLyricsData[]` | ✅ ytmusicapi `as_mobile()` · 🧪 |
| M12 | Related | `browse` | `{"browseId": related}` | carousels | ✅ |
| M13 | Album | `browse` | `{"browseId":"MPREb_…"}` (from `audioPlaylistId` OLAK…: browse `VL`+id, regex `"MPRE.+?"`) | tracks `musicResponsiveListItemRenderer` | ✅ |
| M14 | Artist | `browse` | `{"browseId":"UC…"}` | shelves (songs browseId → playlist, albums/singles browseId+params) | ✅ |
| M15 | Artist albums | `browse` | `{"browseId":channelId,"params":P}` | grid | ✅ |
| M16 | Playlist | `browse` | `{"browseId":"VL"+playlistId}` | tracks + continuations | ✅ |
| M17 | Song credits | `browse` | `{"browseId":"MPTC…"}` | | ✅ optional |
| M18 | **Music stream URL** | same as **Y15** (VISIONOS) | | audio itags 251/250/249/140/139. Video if user taps "Video": video adaptive + audio | ✅ Metrolist uses VISIONOS (`useMusicPlayerEndpoint` = music host) · 🧪 test both hosts |
| M19 | **Unavailable song fallback** (YouPipe Music) | if M18 → `UNPLAYABLE` "This video is not available" (some ATV uploads block anonymous clients): `search` with the **Videos** filter for `"<title> <artist>"`, pick the top `MUSIC_VIDEO_TYPE_OMV`, play its audio in song mode. Remember the mapping per session | | | ✅ YouPipe Music |

Signed-out limits (Metrolist note): signed-out clients usually **can't play explicit tracks** reliably. VISIONOS is "LIMITED" for explicit content. Show an error with retry instead of crashing.

---

### 6.1 YouPipe Music — actual source implementation (repo `SanuSanal/YouPipe-Music`, 2026-10-12)
Read from `lib/innertube/*`, `lib/data/*`, `lib/player/*` and `android/.../*.kt`. No LICENSE file, so **re-implement, don't copy**.

#### 6.1.1 Architecture
| Layer | YouPipe Music | Our plan (pure Dart, Android + desktop) |
|---|---|---|
| Browse/search/next/lyrics | pure Dart `InnerTube` (dio), WEB_REMIX only | same (`core/ytm/`) |
| Stream URLs | Kotlin `StreamExtractorChannel` → NewPipeExtractor v0.26.5 → `getAudioStreams` / `getVideoStream` (muxed) / `getVideoManifest` (DASH MPD) | Dart VISIONOS player (Y15), same outputs |
| Relay | Kotlin `PlaybackProxy.kt` (127.0.0.1, 1 MiB) | Dart `relay_server.dart` (8.2) |
| Audio player | `just_audio` (ExoPlayer) + `audio_service` | media_kit + audio_service/mpris/smtc |
| Video mode | `video_player` + local MPD | media_kit (Android option B = same as YouPipe) |
| Downloads | Kotlin OkHttp 1 MiB chunks → `<appSupport>/downloads/<id>.webm|m4a` + dio cover `<id>.jpg` | Dart, same layout |
| DB | Drift | Drift |

#### 6.1.2 InnerTube client (`clients.dart`, `innertube.dart`)
- Base `https://music.youtube.com/youtubei/v1/<ep>?prettyPrint=false`. dio timeouts: connect 15 s, receive 20 s. JSON.
- WEB_REMIX `clientVersion: 1.20260304.03.00` still works in Oct 2026, so the version is tolerant. UA: `Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36`.
- Context = only `{client:{clientName, clientVersion, hl, gl, visitorData?}}` (no `user`/`request` objects needed).
- Headers: `User-Agent`, `X-YouTube-Client-Name: 67`, `X-YouTube-Client-Version`, `Origin: https://music.youtube.com`, `Referer: …/`, `X-Goog-Visitor-Id`.
- visitorData: `POST visitor_id {}` once, **or take `responseContext.visitorData` from the first response**. Persist in prefs key `visitorData` and reuse forever (no TTL).
- Every call = `{context, ...body}`. Continuations = same endpoint with `{"continuation": token}`.
- Method → endpoint:

| Method | Endpoint | Body |
|---|---|---|
| `home({chip})` | browse | `FEmusic_home` or the chip's `browseEndpoint{browseId,params}` |
| `sectionsContinuation(t)` | browse | `{continuation}` → `continuationContents.sectionListContinuation` |
| `explore()` | browse | `FEmusic_explore` |
| `browseSections(ep)` | browse | any `browseEndpoint` (charts, new releases, moods, mood category, every "More" button) |
| `search(q, filter)` | search | `{query, params?}` |
| `searchContinuation(t)` | search | `{continuation}` → `continuationContents.musicShelfContinuation` |
| `searchSuggestions(i)` | music/get_search_suggestions | `{input}` |
| `album(id)` / `artist(id)` / `playlist(id)` | browse | `MPREb_…` / `UC…` / `VL<id>` |
| `playlistContinuation(t)` | browse | `{continuation}` → `musicPlaylistShelfContinuation` **or** appended items (may return *related shelves* when songs end) |
| `next(ep)` | next | `{videoId?, playlistId?, params?, index?, isAudioOnly:true, enablePersistentPlaylistPanel:true, tunerSettingValue:"AUTOMIX_SETTING_NORMAL"}` |
| `nextContinuation(t)` | next | `{continuation, playlistId?, isAudioOnly:true, enablePersistentPlaylistPanel:true}` → `continuationContents.playlistPanelContinuation` |
| `lyrics(ep)` / `related(ep)` | browse | `MPLY…` / `MPTR…` from `next` tabs |

- **SearchFilter params (YouPipe Music, live):**

| Filter | params |
|---|---|
| Songs | `EgWKAQIIAWoSEAUQCRADEAQQChAOEBAQFRAR` |
| Videos | `EgWKAQIQAWoSEAUQCRADEAQQChAOEBAQFRAR` |
| Albums | `EgWKAQIYAWoSEAUQCRADEAQQChAOEBAQFRAR` |
| Artists | `EgWKAQIgAWoSEAUQCRADEAQQChAOEBAQFRAR` |
| Community playlists | `EgeKAQQoAEABahIQBRAJEAMQBBAKEA4QEBAVEBE%3D` |
| Featured playlists | `EgeKAQQoADgBahIQBRAJEAMQBBAKEA4QEBAVEBE%3D` |

  These are preferred over the ytmusicapi suffix (M6a). Keep both in config; the probe (M6x) picks one.

#### 6.1.3 Parse paths (`parsers/pages.dart`, `parsers/items.dart`)
- Helpers: `nav<T>(json, path)` returns null on any miss, plus `navList`, `textOf` (runs or simpleText) and `parseDuration`. **Parsers never throw**; unknown renderers are skipped.
- Single-column page list: `contents.singleColumnBrowseResultsRenderer.tabs[0].tabRenderer.content.sectionListRenderer`.
- Two-column (album/playlist): header `contents.twoColumnBrowseResultsRenderer.tabs[0].tabRenderer.content.sectionListRenderer.contents[0].musicResponsiveHeaderRenderer` (or wrapped in `musicEditablePlaylistDetailHeaderRenderer`); tracks in `…twoColumnBrowseResultsRenderer.secondaryContents.sectionListRenderer.contents[0].musicPlaylistShelfRenderer|musicShelfRenderer`.
- Section types: `musicCarouselShelfRenderer`, `musicImmersiveCarouselShelfRenderer` (header `musicCarouselShelfBasicHeaderRenderer`/`musicImmersiveCarouselShelfBasicHeaderRenderer`, "More" = `header.moreContentButton.buttonRenderer.navigationEndpoint`), `musicShelfRenderer`, `gridRenderer` (title `header.gridHeaderRenderer.title`), unwrap `itemSectionRenderer.contents[0]`. `numItemsPerColumn` = "Quick picks" grid.
- Home chips: `sectionListRenderer.header.chipCloudRenderer.chips[].chipCloudChipRenderer` → `navigationEndpoint.browseEndpoint`.
- Items: `musicTwoRowItemRenderer` (cards), `musicResponsiveListItemRenderer` (rows), `playlistPanelVideoRenderer` (queue; also under `playlistPanelVideoWrapperRenderer.primaryRenderer`), `musicNavigationButtonRenderer` (mood tiles).
- **Item type comes from the navigation endpoint:** `watchEndpoint` → song; `watchPlaylistEndpoint` → radio playlist; `browseEndpoint.browseEndpointContextSupportedConfigs.browseEndpointContextMusicConfig.pageType` = `MUSIC_PAGE_TYPE_ALBUM` / `_ARTIST` / `_PLAYLIST`. Podcasts/episodes/profiles are skipped.
- Song vs video: `watchEndpoint.watchEndpointMusicSupportedConfigs.watchEndpointMusicConfig.musicVideoType`. `isVideo = type != MUSIC_VIDEO_TYPE_ATV` or the label is "Video".
- Subtitle runs split on `" • "`. Classify each group as type label (`Song, Video, Album, Single, EP, Artist, Playlist, Episode, Podcast, Profile, Station`), artists (runs with ARTIST/USER_CHANNEL pageType), album, year (`^\d{4}$`), duration, or stats (regex `views?|plays?|subscribers?|monthly audience|…$`). Join flex columns first.
- Explicit: `subtitleBadges[]|badges[].musicInlineBadgeRenderer.icon.iconType == MUSIC_EXPLICIT_BADGE`.
- Thumbnails: `musicThumbnailRenderer.thumbnail.thumbnails` | `croppedSquareThumbnailRenderer…` | `thumbnail.thumbnails`. **Resize** googleusercontent art: replace from the last `=w` with `=w{N}-h{N}-l90-rj`. i.ytimg can't be resized.
- Search: `contents.tabbedSearchResultsRenderer.tabs[0].tabRenderer.content.sectionListRenderer.contents[]`, with `musicCardShelfRenderer` = top result. **Unfiltered search is flat** (each result its own `itemSectionRenderer` with a type label). Filtered = `musicShelfRenderer`.
- Suggestions: `contents[].searchSuggestionsSectionRenderer.contents[].searchSuggestionRenderer.navigationEndpoint.searchEndpoint.query`.
- Next: `contents.singleColumnMusicWatchNextResultsRenderer.tabbedRenderer.watchNextTabbedResultsRenderer.tabs[0].tabRenderer.content.musicQueueRenderer.content.playlistPanelRenderer.contents[]`. Tab endpoints are typed by pageType (`MUSIC_PAGE_TYPE_TRACK_LYRICS` / `_RELATED`).
- Lyrics: `contents.sectionListRenderer.contents[0].musicDescriptionShelfRenderer` (`description` + `footer` = source). Related: `contents.sectionListRenderer.contents[]` as sections.
- Artist header: `header.musicImmersiveHeaderRenderer` | `musicVisualHeaderRenderer`. `subscriptionButton.subscribeButtonRenderer.{subscriberCountText,channelId}`; shuffle = `playButton…navigationEndpoint`, radio = `startRadioButton…navigationEndpoint`.
- Album tracks lack artists/album/art; fill them from the album header.
- **Continuation token** appears in either form, sometimes both: `continuations[0].nextContinuationData.continuation` | `nextRadioContinuationData.continuation` | last item `continuationItemRenderer.continuationEndpoint.continuationCommand.token`.
- Quirks: anonymous home has **no "Quick picks"** until there's history on that visitorData. **Charts ignore `gl`** (they use the IP country). Empty library pages return a `messageRenderer`, which is not an error.

#### 6.1.4 Stream resolve (`stream_resolver.dart` + Kotlin)
- Audio list: progressive HTTP only, **ORIGINAL audio track only** (`audioTrackType == null|ORIGINAL`), **drop DRC "stable volume" copies** (`isDrc`) unless nothing else exists. In InnerTube JSON (NewPipe `YoutubeStreamExtractor`): DRC = `adaptiveFormats[].isDrc == true`. Track type = the `acont` key in `xtags` (base64url-decoded protobuf `XTags{repeated KeyValuePair{1:key,2:value}}`; in Dart a ~20-line varint/length-delimited reader is enough) (`original` / `dubbed` / `dubbed-auto` / `descriptive` / `secondary`). Formats without `audioTrack` are single-track = original.
- Quality pick (unit-tested): prefer Opus/WebM. **high** = max bitrate (251 ~160 kbps), **normal** = highest ≤100 kbps (250 ~70), **low** = min (249 ~50). Free tier tops out at 251.
- Cache per videoId until **10 min before `expire=`**. `invalidate(id)`; **`clearCache()` on every network error/change** (URLs are bound to the old IP).
- Video mode:
  - `auto`: MPD of avc1 360p–1080p + best Opus audio. ExoPlayer adapts.
  - `high`: tallest ≤1080p only.
  - `dataSaver`: muxed 360p (itag 18).
  - `NO_HD` when there's no avc/vp9, the top is <480p, or duration ≤0 → fall back to muxed. ⚠️ NewPipe master is VISIONOS-only, so muxed itag 18 may not exist → dataSaver = 360p avc1 video-only + audio.
- MPD template (Kotlin `buildMpd`, port it 1:1 in Dart from `adaptiveFormats` `initRange{start,end}` / `indexRange{start,end}`; skip formats without both):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" profiles="urn:mpeg:dash:profile:isoff-on-demand:2011"
     type="static" minBufferTime="PT1.5S" mediaPresentationDuration="PT{durSec}S"><Period>
 <AdaptationSet id="0" contentType="video" mimeType="video/mp4">
  <Representation id="v{n}" codecs="{avc1…}" bandwidth="{bitrate}" width="{w}" height="{h}" frameRate="{fps}">
   <BaseURL>{xmlEscaped url}</BaseURL>
   <SegmentBase indexRange="{indexStart}-{indexEnd}"><Initialization range="{initStart}-{initEnd}"/></SegmentBase>
  </Representation>…
 </AdaptationSet>
 <AdaptationSet id="1" contentType="audio" mimeType="audio/webm">
  <Representation id="a0" codecs="opus" bandwidth="{b}" audioSamplingRate="{sr}">…same BaseURL/SegmentBase…</Representation>
 </AdaptationSet></Period></MPD>
```
  Write it to `<temp>/video/<id>_<quality>.mpd`. For playback, write a `.relay.mpd` copy whose BaseURLs are relay URLs (pass each URL's `clen` as its size). Keep the cached MPD with the googlevideo URLs.
- Error codes surfaced: `AGE_RESTRICTED, GEO_RESTRICTED, UNAVAILABLE, RECAPTCHA, BOT_CHECK, EXTRACTION_FAILED, NO_STREAMS, NO_VIDEO, NO_HD`. **Not retried:** AGE/GEO/UNAVAILABLE/NO_STREAMS. `UNAVAILABLE` is YouTube's answer (some ATV songs are UNPLAYABLE for every client), so go to M19.

#### 6.1.5 Relay + googlevideo fetch (`PlaybackProxy.kt`, `Googlevideo.kt`)
- `CHUNK = 1 MiB`. Each fetch is a GET with header **`Range: bytes=a-b`** (not the `&range=` query) and **UA by `c=`** in the URL (`c=VISIONOS` → visionOS UA, else web Firefox UA).
- Size unknown → `Range: bytes=0-0`, read the total from `Content-Range: bytes 0-0/<total>`.
- Server: bind **127.0.0.1** (not `::1`), random port, token map (keep the last 64), path `/s/<token>`, GET/HEAD only, otherwise 404.
- Parse the player's `Range`. **Fetch the first chunk before writing the head** (upstream 4xx passes through, else 502). Then write `206` + `Content-Range bytes s-e/size` (or 200), `Content-Length`, `Accept-Ranges: bytes`, `Content-Type`.
- Loop: write the chunk, fetch the next one, read each **in full** before writing. A mid-body failure closes the socket, and the player re-requests from its offset.
- One shared HTTP client with the family preference (IPv4-first sort), used by extraction, relay and downloads. Bot check → `switchFamily(from)` only if no one else flipped meanwhile, evict pooled connections, persist the flag.

#### 6.1.6 Song ↔ music video (`music_video.dart`)
- `musicVideoFor(song)`: if `song.isVideo`, use it. Else `search("<title> <firstArtist>", Videos)` → `pickMusicVideo`.
- `pickMusicVideo`: strip brackets `(…)`/`[…]` from the inside out repeatedly. Normalize: lowercase, non-letter/digit → space (`\p{L}\p{N}`, unicode). Pick the first candidate that `isVideo`, whose normalized title **contains** the song title, and that shares an artist (or names one in its title). Else null.
- Cache per song (`MusicVideoFinder`). The same function also serves the unavailable-song fallback (M19).

#### 6.1.7 Player behaviour (`audio_handler.dart`, `providers.dart`) → port to media_kit
- The queue lives in the handler (`songs, index, shuffle, repeat, title`). Push `queue` to audio_service only when the list changes, not on index moves.
- **Load lazily:** current + **next only** (URLs expire). Order: local download file → resolve → set source → play → **preload next (gapless)**. media_kit equivalent: `Playlist([current, next])` + `player.next()`; rebuild slot 2 after any queue/shuffle/repeat edit; serialize edits; use a load-generation guard so a slow load can't override a newer one.
- Preload failure: log only. Unavailable → give up. Other errors → retry every 20 s, max 4.
- **Song switch:** pause the old song at once and report `loading` at 0:00 until the new one is ready (otherwise the old song kept playing under the new title). Ignore completion/index/error events while switching.
- **Recovery:** on a player error, `clearCache()` (all URLs), reload from the last position. Delays **0, 2, 5, 10, 20, 30 s** (~3.5 min), then "Can't play this song". Report `buffering` while retrying. Pause cancels; Play retries now. The retry budget resets after 20 s of playback.
- **Buffer 3–5 min ahead** (Android `AndroidLoadControl`). media_kit: raise `demuxer-max-bytes` / `cache-secs` via `NativePlayer.setProperty` 🧪.
- **Radio:** tapping a single song plays it, then appends `next(videoId, playlistId: RDAMVM<id>)` minus its first item (`QueueExtender`). **Top up when ≤5 songs remain** via `nextContinuation`. An empty result ends the radio. Albums/playlists: `playList(songs, index, shuffle)` with no extender. Artist Shuffle/Mix: `playEndpoint(watchEndpoint)`.
- **Shuffle like YTM:** reorders the *visible* upcoming queue. Turning it off doesn't restore the order. Repeat modes: off/all/one. Queue ops: playNext, addToQueue, remove (not current), move.
- SponsorBlock (setting `skipNonMusic`): `music_offtopic` + `actionType=skip`, hash prefix 4, ignore segments <1 s. Skip when `p >= start && p < end-300ms`. A segment reaching the end = completion. Silent. Share in-flight requests.
- Sleep timer: fade ~5 s then pause, or pause at end of song. Speed. History when `saveHistory` is on. Swiping the app from Recents stops everything (`onTaskRemoved`).
- Video mode: same queue. Next stays in video mode. Fallback to the song with a toast for "no video" or "video unavailable" (dim the toggle for the session). Video errors use the same recovery. Casting turns video mode off.
- Equalizer/loudness: native Android `Equalizer` + `LoudnessEnhancer` on the audio session, best-effort (P-later; desktop: mpv `af` filters 🧪).

#### 6.1.8 Lyrics (`lyrics_service.dart`, `lrc.dart`)
- `cleanTitle`: remove `(…official|video|audio|lyric|visuali[sz]er|mv|hd|4k…)` and `(feat|ft|with …)` brackets, and trailing ` - Topic|Official…`. `cleanArtist`: strip ` - Topic`.
- LRCLIB `GET /api/get?track_name&artist_name&album_name?&duration?` → use it if synced. `instrumental:true` → "♪ Instrumental ♪". 404 → `GET /api/search?track_name&artist_name`, keep results with **|duration−song| ≤ 4 s**, sort synced first then by duration gap, take the first usable. Then YT `next` → lyrics tab → `MPLY` plain.
- UA header `AppName/1.0 (platform; repo-url)`. Cache per videoId.
- LRC: tag `\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]`, multiple tags per line, `[offset:±ms]` (positive = earlier). Active line = binary search + **250 ms lead**.

#### 6.1.9 Downloads (`download_manager.dart`, `DownloadChannel.kt`)
- Queue, **one at a time**: `queued → downloading → done|failed`.
  1. Resolve a fresh URL (`forceRefresh`).
  2. Fetch the audio in 1 MiB chunks to `<appSupport>/downloads/<id>.webm|m4a`.
  3. Fetch the cover with dio to `<id>.jpg`.
  4. On error, delete the partial file and mark `failed`.
- Write progress to the DB at most every 400 ms; the UI watches the table. `resumePending()` at app start re-queues `queued`/`downloading` rows.
- Playback prefers the local file (`localFile(videoId)`) before any extraction.
- Their gap: no WorkManager, so downloads stop when the app dies. Ours: foreground service (9.7).

#### 6.1.10 Local DB (Drift) and prefs — merge into 11.1
- Tables:
  - `Songs(videoId PK, title, artistsJson, albumId?, albumName?, durationMs?, thumbnailUrl?, isVideo)`
  - `LikedSongs(videoId PK→Songs, likedAt)`
  - `PlayHistory(id, videoId→Songs, playedAt)`
  - `SavedAlbums(browseId PK, playlistId?, title, artistsJson, year?, thumbnailUrl?, savedAt)`
  - `SavedArtists(browseId PK, title, thumbnailUrl?, savedAt)`
  - `SavedPlaylists(playlistId PK, title, author?, thumbnailUrl?, savedAt)`
  - `LocalPlaylists(id, name, createdAt)`
  - `LocalPlaylistItems(id, playlistId→cascade, videoId, position)`
  - `Downloads(videoId PK, status enum, filePath?, artPath?, sizeBytes, downloadedBytes, addedAt)`
  - `SearchHistory(query PK, searchedAt)`
- Foreign keys are on (`PRAGMA foreign_keys` in `beforeOpen`).
- Prefs: `visitorData, quality(low|normal|high), videoQuality(auto|high|dataSaver), hl, gl, saveHistory, skipNonMusic, eq*` .
- Music profile (our addition): name/avatar + stats from `PlayHistory` (top artists/songs, minutes).

#### 6.1.11 What we add beyond YouPipe Music
- Desktop (Win/macOS/Linux) via the pure-Dart streams + media_kit.
- Music LRU cache (10) (they rely only on the buffer + explicit downloads).
- Local profile + JSON backup (11.2).
- YT timed lyrics M11 as a 3rd fallback (optional).

### 6.2 SourecResource — music + lyrics implementation (reviewed project snapshot, v1.8.2, 2026-10-30, GPL-3.0)
Kotlin Android (+ TV, Wear OS, desktop JVM, React web). It's the most engineered YTM client reviewed. GPL-3: porting code makes our app GPL-3 (we're already GPL, section 14).

#### 6.2.1 Stream engine (`shared/.../innertube/StreamResolver.kt`, `InnerTubeXResolver.kt`, `PlayerClient.kt`)
- **Order:**
  1. **InnerTubeX** (Metrolist's `innertubex` v0.7.0: live-benchmarked client catalog + cipher tiers + PO tokens; section 3 notes).
  2. **NewPipeExtractor** as a failsafe. It's last because it scrapes the watch page, which Google rate-shapes hardest; a shaped response can hold a call open ~1 min.
  3. **Probe** every URL before the player or cache sees it.
- **Probe rule (adopt):**
  - GET with the *real* media headers and a range **starting past 1 MiB** when the file is longer, the same size as a real fetch. Some clients serve the first MiB then 403, which shows up as playback dying ~50 s in.
  - At least **16 KiB must actually arrive**. Probe timeout **6 s**.
  - Only a probed URL is cached. A URL later refused while playing → `onPlaybackRefused` forgets it and excludes that client for the track.
- **Media headers by `c=`** (`PlayerClient.forStreamUrl`): parse the `c` and `cver` query params and send that client's UA. **Web clients also need `Origin` + `Referer`** (WEB_REMIX → music.youtube.com, WEB/MWEB/TVHTML5 → www.youtube.com). Native app clients must send none. A mismatch → throttled to a crawl or 403. Unknown `c` → iOS UA.
- **Range size by client:** 1 MiB default, **512 KiB for `ANDROID_VR` and `TVHTML5_SIMPLY`**.
- **Measured throttling:** unbounded GET **15.5 kB/s** vs `Range: bytes=0-2097151` **5.7 MB/s** (same track/connection). Confirms the relay (8.2) for *every* read, including the track currently playing.
- **Coalesce:** one resolve per videoId in flight. A second caller awaits the first (read-ahead + playback raced → 250 ms calls stretched past 3 s).
- **Unplayable verdict cache 10 min:** age/takedown/region → remember for 10 min and don't retry. One permanent failure caused ~27 client walks and 50 youtubei requests in 2m41s before this. Clear it on sign-in/out.
- **URL TTL 20 min** in the memory cache (not "until expire"): URLs are tied to the minting session. Max 32 entries.
- **Extraction leash:** watch-page/extractor calls get their **own connection pool** and a **5 s call timeout**, retried up to **3×** with a fresh connection, back-off 1 s × attempt. A pooled dead socket hangs silently, and a read timeout alone never fires on a trickle.
- **Serialize JS (n-sig) work:** concurrent player-JS runs collapse (1.8 s alone → 16.2 s with 2 → 30.3 s with 3). Use one global mutex. Read-ahead = **1 track**. Only ask for audio streams; asking for all video formats costs 49.8 s vs 2.3 s.
- **Loudness normalization:** keep `playerConfig.audioConfig.loudnessDb` (also `perceptualLoudnessDb`, per-format `loudnessDb`) per videoId. Apply the gain per player, not on the shared session (crossfades otherwise re-level the outgoing track). Add a peak limiter.
- **Response field mask (innertubex):** header **`X-Goog-FieldMask`** with only the needed fields (playabilityStatus, streamingData(formats/adaptiveFormats(itag,url,mimeType,bitrate,averageBitrate,width,height,contentLength,quality,audioQuality,approxDurationMs,audioSampleRate,audioChannels,loudnessDb,lastModified,xtags,audioTrack,isDrc,signatureCipher),expiresInSeconds,hlsManifestUrl,serverAbrStreamingUrl), videoDetails, playerConfig.audioConfig). Shrinks the response. **For MPD building add `initRange,indexRange,fps`.** 🧪
- **Live:** `live=1` / `source=yt_live_broadcast` in the URL → use `streamingData.hlsManifestUrl`.
- **WEB_REMIX version:** read live from the music.youtube.com shell (`ytcfg` `INNERTUBE_CLIENT_VERSION`), with a hardcoded fallback.

#### 6.2.2 PO token (optional unlock, P6+)
- BotGuard in a hidden browser page (Android WebView, desktop JavaFX WebView). This is the NewPipe-app `PoTokenWebView` method:
  1. POST `https://www.youtube.com/api/jnn/v1/Create` with body `["<requestKey>"]` (headers `Content-Type: application/json+protobuf`, `x-goog-api-key: <public web key>`, `x-user-agent: grpc-web-javascript/0.1`).
  2. Run the returned challenge in the page.
  3. POST `…/GenerateIT` with `["<requestKey>","<botguardResponse>"]` → integrity token + TTL (use TTL − 10 min).
  4. Mint `poToken(identifier)` from the page: the **visitorData** for the session token, the **videoId** for the per-video token.
  5. One page per visitorData. Recreate it on expiry or failure, with one retry.
- This unlocks WEB_REMIX/WEB streams (explicit/kids content, signed-in).
- Flutter: Android/macOS `webview_flutter`. Windows needs a WebView2-capable plugin. Linux has no stable option, so treat it as Android/macOS-first. 🧪

#### 6.2.3 Downloads & containers (`StreamResolver.Stream`, `resolveForDownload`)
- **YouTube Opus is Opus-in-WebM:** name it **`.webm`, never `.opus`** (`.opus` must be Ogg, and players refuse it).
- **Android MediaStore rejects `audio/webm`** (`IllegalArgumentException: Unsupported MIME type audio/webm` on insert). So:
  - app-private downloads can keep Opus/WebM;
  - **exports to the Music collection must use AAC-in-MP4 (itag 140 → `.m4a`)**.
  - Choose the container before resolving and fail clearly; never silently swap codecs.
- One download = one rendition. Pass the bitrate ceiling in, so a mid-fetch re-resolve can't splice two renditions.
- Quality: highest at or under the ceiling, else the cheapest available. **Separate ceilings for Wi-Fi vs mobile data.**

#### 6.2.4 Playback cache (`AudioCache.kt`, `ChunkedDataSource.kt`, `DynamicLruCacheEvictor.kt`)
- Write everything played to an on-disk cache (Media3 `SimpleCache` + LRU evictor with a live-adjustable `maxBytes`).
- **Read-ahead** puts the *next* track fully on disk between songs, so seeking anywhere is a file read.
- `ChunkedDataSource` splits every player read into bounded ranges using `clen` from the URL (the total size must be known).
- Port: our relay (8.2) writes through to `cache/audio/<id>.<itag>` with a sparse-range index. LRU (section 10). Read-ahead 1 track. 🧪
- **StreamChoice:** pin the chosen rendition per track for its whole play. Re-opens (seek, resume, continuation) must not resolve to a different file/container mid-track (it once got MP4 bytes spliced into an Opus play).

#### 6.2.5 Lyrics engine (`shared/.../data/lyrics/`)
- **Model** (`LyricLine.kt`):
  - `LyricLine{timeMs, text, words[], sungUntilMs?, background: LyricLine?, alignment Start|End, timingSource?}`
  - `LyricWord{startMs, endMs, text, syllables[]}`
  - `LyricSyllable{startMs, endMs, startChar, endChar}`
  - Gap = empty text. `isWordSynced = words.isNotEmpty()`. Plain lyrics = every line `timeMs = 0`.
- **Format sniffing** (`ProviderLyrics.parse`):
  1. unwrap JSON envelopes (keys `ttml, ttmlContent, lyrics, lrc, content, text, plainLyrics, syncedLyrics, line, lines, lyric, data, result, response`; reject `isError/ok:false/error`), strip ``` fences and BOM, un-escape `&lt;tt`;
  2. `<tt` or the TTML namespace → **TTML**;
  3. karaoke LRC → KaraokeLrc;
  4. other XML → none;
  5. else **Enhanced LRC** → plain **LRC** → **plain** (drop "lyrics not found/error" bodies and `[ar:…]` metadata).
- **TTML (Apple)** (`TtmlLyrics.kt`):
  - `<p begin end ttm:agent>` per line, `<span begin end>` per syllable.
  - **Whitespace (not span boundaries) separates words.**
  - `ttm:role="x-bg"` = background vocal, carried as `background`.
  - Skip roles `x-translation` and `x-roman`.
  - Agents `v1`/`v2` = singers, `v1000` = group, `v2000` = other → alignment (duet right/left).
  - Parse with external entities and DOCTYPE disabled (XXE).
- **Enhanced LRC (A2):** `[mm:ss.xx]<mm:ss.xx>word <mm:ss.xx>word`. Only starts are given: a word ends at the next word, and the last word at the next line.
- **LRC:** `\[(\d{1,3}):(\d{2})[.:](\d{2,3})]`. Two fraction digits = centiseconds, 3 = ms. Stamp-only lines = instrumental gaps, kept only if **≥4 s** to the next line. Prepend an intro gap if the first line is ≥4 s in. A trailing stamp closes the outro.
- **Query cleanup** (`LyricsQuery.kt`):
  - Remove **credits and packaging only**: `(feat|ft|featuring|with …)` in brackets, or unbracketed to the end; `(official) (music) video|audio|visualizer|lyric(s) video|lyrics|m/v|hd|hq|4k|full song`; `(official)`.
  - **Keep** `(Remix) (Acoustic) (Live) (Remastered 2011) (Sped Up)`: a different recording means different lyrics.
  - Artist: strip ` - Topic`.
- **Race + priority** (`LyricsRepository.kt`):
  - Ask **all enabled sources in parallel**, then await them **in priority order**. A word-synced answer wins outright. Without "prioritize syllable sync", the first line-synced answer in priority order wins. Cancel the losers.
  - Plain-text sources (Genius) start lazily, only if nothing timed came back.
  - Optional **ISRC identify** step first (2.5 s cap), cached per videoId, for sources that accept ISRC.
  - Per-source on/off + reorder in Settings. A disabled source is never contacted.
  - Cache the last 100 results.
- **Per-song lyrics offset** sheet (user shifts ± ms). Share-card image. Optional translation via `translate.googleapis.com/translate_a/single` (unofficial "gtx").

#### 6.2.6 Lyrics sources found, and what we take
| Source | Request | Returns | Timing | Our decision |
|---|---|---|---|---|
| **LRCLIB** | `GET lrclib.net/api/get?track_name&artist_name&duration` → else `/api/search?track_name&artist_name`, keep synced, **min |duration − song|** | LRC | line | ✅ **default #1** (open, community, key-less) |
| **YouTube Music tab** | `next(videoId)` → tab titled "Lyrics" (or the 2nd tab) `browseEndpoint{browseId,params}` → `browse` → `musicDescriptionShelfRenderer.description` | plain | none | ✅ default #2 (exact video) |
| **YouTube transcript** | `get_transcript` protobuf params (Y16b) → `transcriptCueRenderer` | lines | line | ✅ default #3 (exact video; captions may not equal lyrics) |
| **Unison** | `GET unison.boidu.dev/lyrics?song&artist&album?&duration?` → `{success, data{lyrics, format(ttml/lrc), syncType(plain)}}` | TTML/LRC/plain | word/line | ⚙️ opt-in (user-contributed, thin) |
| **KuGou** | `mobileservice.kugou.com/api/v3/search/song?version=9108&plat=0&pagesize=8&showtype=0&keyword="<title> - <artist> <album>"` (keep **±8 s**) → `lyrics.kugou.com/search?ver=1&man=yes&client=pc&hash=…` → `lyrics.kugou.com/download?fmt=lrc&charset=utf8&client=pc&ver=1&id&accesskey` → base64 LRC, strip credit lines | LRC | line | ⚙️ opt-in (good for Asian catalogs; unofficial endpoints) |
| BetterLyrics / Portato | `lyrics-api.boidu.dev/getLyrics?s&a&d&al` / `/qq/getLyrics` | TTML | word | ⚠️ off by default: unofficial re-serving of Apple/QQ licensed timings |
| lrc.red, BiniLyrics, PaxSenix, LyricsPlus (6 community mirrors) | ISRC/title search → TTML | TTML | syllable | ⚠️ same: Apple-catalog proxies, mirrors come and go |
| Musixmatch | `apic.musixmatch.com/ws/1.1` with a reverse-engineered app signature | LRC/richsync | word | ❌ don't port (embedded signing secret = ToS breach) |
| Genius | `genius.com/api/search/multi` + page scrape | plain | none | ⚙️ optional last resort (scraping) |
| SimpMusic, Megalobiz | — | — | — | hidden by SourecResource itself (dead/unreliable) |

**Recommended defaults:**
- Order: LRCLIB → YT Music tab → YT transcript. Opt-in: Unison, KuGou.
- Race + priority + "prefer word-synced" toggle.
- Store **raw text + detected format + source** in `lyrics_cache` and re-parse on load, so parser fixes apply retroactively.
- One parser set for all sources: TTML / A2 / LRC / plain.

#### 6.2.7 Other interesting features (scope notes)
- ✅ Worth adding: crossfade/gapless (media_kit `Playlist` + two players for crossfade 🧪), skip-silence, sleep timer incl. "stop after this track", per-network quality, stats-for-nerds (codec/bitrate/itag), lyrics offset, local-file library, Last.fm/ListenBrainz scrobbling (user's own token, no server).
- ❌ Not adopted:
  - "Hi-Res lossless module sources": third-party catalogs with unclear licensing.
  - Spotify import via web-player tokens.
  - Discord RPC.
  - "Listen together" party: needs SourecResource's Go backend, against your no-server rule.
  - Automix beat-matching (ONNX models).
  - USB bit-perfect output.

## 7. Third-party APIs (user device → public API, no own server)

| API | Request | Response | Rules |
|---|---|---|---|
| Return YouTube Dislike | GET `https://returnyoutubedislikeapi.com/votes?videoId={id}` | `{id,dateCreated,likes,dislikes,rating,viewCount,deleted}`. 404 not found, 400 bad id | **100/min, 10,000/day per client** → 429. **Attribution required**: link to returnyoutubedislike.com in the UI. Cache 24 h in Drift. API reported working in Apr 2026 (user comment on issue #1274; only the extension broke) |
| SponsorBlock | GET `https://sponsor.ajay.app/api/skipSegments/{sha256(videoId)[0..4]}?categories=["sponsor","selfpromo","interaction","intro","outro","preview","music_offtopic","filler"]&actionTypes=["skip","mute"]` | `[{videoID, segments:[{segment:[s,e],UUID,category,actionType,votes,locked,videoDuration,description}]}]` → filter `videoID==id` | hash-prefix = privacy (recommended by SponsorBlock). No GET rate limit listed. Show "skipped sponsor" toast + undo |
| LRCLIB (synced lyrics fallback) | GET `https://lrclib.net/api/get?track_name=&artist_name=&album_name=&duration={sec}` or `/api/search?q=` / `track_name=&artist_name=` | `{id,trackName,artistName,albumName,duration,instrumental,plainLyrics,syncedLyrics}` | duration 1–3600. Set your own `User-Agent: AppName/ver (repo url)` |

Lyrics priority: **see 6.2.6** (rev 4, SourecResource race model). Default: LRCLIB → YT Music lyrics tab → YT transcript, all asked in parallel and taken in priority order. Music-mode SponsorBlock: `categories=["music_offtopic"]` only, ignore segments <1 s.

---

## 8. Playback (media_kit, all 4 platforms)

```dart
final player = Player();
final controller = VideoController(player);
await player.open(Media(videoUrl, httpHeaders: {'User-Agent': visionUa}), play: false);
await player.setAudioTrack(AudioTrack.uri(audioUrl)); // external audio track (mpv audio-files)
await player.play();
```
- 🧪 Test that `AudioTrack.uri` with a googlevideo URL stays in sync on Android + desktop. Fallback if it fails: build a local DASH MPD (two `AdaptationSet`s with `BaseURL` + `SegmentBase indexRange/initRange` from `adaptiveFormats`) and open it from a file. NewPipe does the same (`YoutubeProgressiveDashManifestCreator`).
- **Quality change**: keep `pos = player.state.position`, re-open with the new video URL + same audio, `seek(pos)`. Debounce, and keep the old frame until the first frame arrives.
- **Audio-only mode (music + background video)**: `player.open(Media(audioUrl))`, no video track.
- **Captions**: `player.setSubtitleTrack(SubtitleTrack.uri(vttUrl, title:, language:))` or `.data(vttString)`. `SubtitleTrack.no()` turns them off. Translated tracks: append `&tlang={code}` to baseUrl (from `translationLanguages[]`) 🧪.
- **Speed**: `setRate`. **SponsorBlock**: listen to `player.stream.position`; if inside a skip segment, `seek(end)`.
- **Range/buffer**: mpv streams with HTTP Range. Raise `demuxer-max-bytes` via `NativePlayer.setProperty` for smooth seeking (optional).
- **403 mid-play**: on `player.stream.error`, re-fetch the player response, swap URLs, seek to the **last good position**. `video_player` resets to 0:00 on error (YouPipe bug, fixed 2026-10-05), so store the position before the error. Max 3 re-resolves in a row; the budget resets after 60 s of playback (F5).

### 8.2 Loopback relay (mandatory, F6)
- `RelayServer` = `HttpServer.bind(InternetAddress.loopbackIPv4, 0)` (bind 127.0.0.1 explicitly, not `::1`). Register a stream with `relay.register(url, ua, contentLength)` → `http://127.0.0.1:<port>/s/<token>`. Keep the last 64 tokens.
- On a player request with `Range: bytes=a-b?`: loop over 1 MiB windows, GET `googleUrl&range=x-y` (or a `Range` header) with the **c= client UA**. **Fetch the first chunk before writing the response head** so a 403 or a network error reaches the player as HTTP 403/502 and triggers 8's recovery. Read each chunk in full before writing it.
- Answer `206` with `Content-Range`/`Content-Length` from `clen`/`contentLength`. Support `HEAD`.
- Use it for media_kit audio + video URLs (and `AudioTrack.uri`). If the relay fails to start, fall back to direct URLs.
- Android: `res/xml/network_security_config.xml` with `<domain-config cleartextTrafficPermitted="true"><domain>127.0.0.1</domain></domain-config>`.

### 8.3 Address-family switch (F3)
- One shared `HttpClient` for extraction, relay and downloads. Set `connectionFactory` to resolve via `InternetAddress.lookup(host, type: preferIpv4 ? IPv4 : any)` and connect to the chosen address.
- On `LOGIN_REQUIRED` with "not a bot" (or a burst of 403s): flip `preferIpv4`, close idle connections, retry once. Persist the flag in `prefs`.
- 🧪 Verify that `HttpClient.connectionFactory` + `Socket.startConnect` gets TLS applied for https on each platform (Dart SDK behavior). If not, use `SecureSocket.startConnect(address, 443, …)` with SNI = host (`supportedProtocols` http/1.1).
- If both families fail: show "YouTube wants to confirm you're not a bot. Try again later". Don't loop.

### 8.4 Android player option B (proven by YouPipe)
If media_kit + `AudioTrack.uri` misbehaves on Android (🧪 P3):
- Build a static DASH MPD: one video `AdaptationSet` with **H.264 only, 360p–1080p** (VP9 only if no avc1 exists) and one Representation per height, each with `BaseURL` + `SegmentBase indexRange`/`Initialization range`. Add the best Opus audio.
- Rewrite the BaseURLs to relay URLs and write it to `<temp>/video/<id>_<maxH>.relay.mpd`.
- `VideoPlayerController.file(..., formatHint: VideoFormat.dash)`, with headers via `httpHeaders`. ExoPlayer adapts within the MPD.
- Desktop keeps media_kit (video_player has no DASH on desktop).

### 8.1 Background + media notification
- One `PlaybackService` (Riverpod singleton) owns the media_kit `Player`.
- Android/macOS: `audio_service` `BaseAudioHandler` that forwards play/pause/seek/skip to media_kit and pushes `MediaItem` + `PlaybackState` from player streams. Android manifest: `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, service `com.ryanheise.audioservice.AudioService` with `foregroundServiceType="mediaPlayback"`, `AudioServiceActivity`.
- Linux: add `audio_service_mpris` (same handler).
- Windows: `smtc_windows` adapter subscribed to the same player state.
- Video in background: switch to audio-only on `AppLifecycleState.paused` if the user enabled it, and switch back on resume (re-open at position).

---

## 9. Downloads (Dio chunked + ffmpeg merge, max 1080p)

1. Resolve the player response (Y15) and pick video (avc1, height ≤1080) + audio **140 (AAC 128k)** so the result is a plain `.mp4` (YouPipe: H.264 + best AAC). Audio-only downloads: 251 Opus.
2. **Chunked range download** (un-ranged googlevideo requests get throttled or cut). Chunk size **1 MiB default** (YouPipe, proven on device) and up to 10 MiB as an option (yt-dlp `CHUNK_SIZE = 10 << 20`). For `start in 0..contentLength step chunk`, GET `url + '&range=$start-${min(start+chunk-1, len-1)}'` and append to `*.part`. Use the **same User-Agent and same shared HttpClient/address family as the extraction** (F3/F4/F8). Run video + audio in parallel, 1 connection each. Re-resolve fresh URLs inside the download job, never URLs passed from the UI (they expire and are IP-bound).
   - Android: run the job in a foreground service (data-sync notification) so it survives app close. YouPipe uses WorkManager; Dart option: `workmanager` or the audio_service process. 🧪 P5.
3. Resume: store `bytesDone` per stream in Drift. On restart, continue from the next chunk. On 403, re-resolve URLs (expire) and continue at the same offset.
4. Merge (no re-encode): `ffmpeg -y -i v.part -i a.part -map 0:v:0 -map 1:a:0 -c copy out.{ext}` via `FFmpegKit.execute`.
   - H.264 + AAC → `.mp4` (default). Rare VP9-only video → VP9 + Opus → `.webm`.
   - Add `-movflags +faststart` for mp4.
5. Audio-only download: 251 → `ffmpeg -i a -c copy out.opus` (or `.webm`). 140 → `.m4a` (copy). Optionally embed the cover with `-i cover.jpg -map 0 -map 1 -c copy -disposition:v attached_pic` (m4a). For opus, use metadata tags only.
6. Locations: Android → `getExternalStorageDirectory()/Downloads` (app-specific, no permission). Optional "Export to Movies/Music" via MediaStore (verify `media_store_plus` on your targetSdk). Desktop → `getDownloadsDirectory()/AppName`.
7. Android background downloads: run inside the foreground service (same audio_service process) or show a progress notification (`flutter_local_notifications`). Keep the downloader in a Dart isolate-safe service.
8. Delete `.part` files after a successful merge. Write a sidecar `.json` with metadata so the library survives a reinstall/rescan.

---

## 10. Music cache (offline-ish, LRU)

- On play: stream the URL directly. In parallel, a background chunked download (same as 9.2) writes `cache/audio/{videoId}.{itag}`. When complete, insert an `audio_cache` row.
- Next play: if a cache file exists, open the local file (zero network).
- LRU limit (setting, default 1 GB): evict by `lastPlayedAt`.
- Also cache: home/explore JSON 30 min, lyrics forever, RYD 24 h, SponsorBlock 24 h, thumbnails via `cached_network_image` (optional).

---

## 11. Local "account" (no Google login)

### 11.1 Drift schema
```
prefs(key TEXT PK, value TEXT)                                   -- visitorData+exp, settings, client override JSON
profile(id INT PK=1, name, avatarPath, createdAt)                -- music local profile
subscriptions(channelId PK, name, avatarUrl, subscribedAt, lastFeedAt)
feed_items(videoId PK, channelId, title, publishedAt, thumbUrl, durationSec?, fetchedAt)
media(videoId PK, title, channelId, channelName, durationSec, thumbUrl, isMusic BOOL, musicVideoType, updatedAt)
reactions(videoId PK, value INT /*1 like,-1 dislike*/, at, scope /*yt|ytm*/)
history(id PK AUTO, videoId, positionMs, durationMs, at, scope)
playlists(id PK AUTO, name, scope, remoteId?, thumbUrl?, createdAt, updatedAt)
playlist_items(playlistId, videoId, position, addedAt, PK(playlistId,videoId))
saved_remote(id PK /*VL…|MPREb…|UC…*/, kind /*playlist|album|artist|channel*/, title, thumbUrl, savedAt)
downloads(id PK AUTO, videoId, kind /*video|audio*/, vItag?, aItag, height?, container, path, total, done, status, error?, createdAt)
audio_cache(videoId PK, itag, path, bytes, lastPlayedAt)
lyrics_cache(videoId PK, source, format /*ttml|a2|lrc|plain*/, raw TEXT, offsetMs INT default 0, fetchedAt)  -- store raw, re-parse on load (6.2.6)
ryd_cache(videoId PK, likes, dislikes, fetchedAt)
sb_cache(videoId PK, json, fetchedAt)
search_history(query, scope, at, PK(query,scope))
```
- "Liked songs" (YTM) = `reactions where value=1 and scope='ytm'`. Liked videos = scope `yt`.
- A local dislike only hides the item and down-ranks its channel in the local home feed. The **displayed** dislike count comes from RYD (we never vote on RYD; voting requires their registration flow and isn't needed).
- Pause/resume history and "resume at position" both come from `history`.

### 11.2 Backup / import
- Export/import a single JSON (`subscriptions, playlists+items, reactions, history, saved_remote, profile, prefs-safe`).
- Import Google Takeout `subscriptions.csv` (format `Channel Id,Channel Url,Channel Title`, per NewPipe `YoutubeSubscriptionExtractor`).

### 11.3 YouTube home without login (local algorithm)
1. "New from subscriptions": RSS (Y17) for all subscriptions, refreshed in parallel (cap 6 concurrent, at most once every 30 min), sorted by `publishedAt`.
2. "For you" = **YouPipe HomeMixer (F10)**. Sources, all started at once:
   - related (Y4 + continuations) of the **last 6 watched** videos, weight 2;
   - **unwatched subscription uploads ≤14 days**, weight 2;
   - topic-chip searches (Music, Gaming, Live, News…), weight 1, or 2 when nothing personal exists.
   Mix round-robin by weight. No repeats, drop items ≥90% watched and disliked channels.
   **Launch cache:** keep the first page + Shorts shelf in `prefs` for 12 h. Show it in the first frame; replace it with the fresh mix only if the user hasn't touched Home yet.
3. "Trending": Y14 charts (country = device locale) + Y10/Y11/Y12 kiosks as chips.
4. Try Y9 `FEwhat_to_watch` first. If it returns items, show them on top.
- Cold start (no history/subs): charts + kiosks + a "pick topics" search chip row.

YTM home: M1 is fine logged-out (ytmusicapi works unauthenticated). Add local "Quick picks from your likes": M8 radio of your top-played songs.

---

## 12. Project structure

```
lib/
  core/
    innertube/
      clients.dart            # loads assets/innertube_clients.json (+ user override from prefs)
      innertube_http.dart     # dio, headers per client, visitorData provider, retries
      visitor.dart            # Y1 + cache
      json_find.dart          # findAll / safe nav helpers
      continuation.dart
    yt/                       # YouTube API (Y2..Y18) -> models
      yt_search.dart yt_next.dart yt_browse.dart yt_charts.dart yt_rss.dart yt_suggest.dart
    ytm/                      # YouTube Music API (M1..M17)
      ytm_home.dart ytm_search.dart ytm_watch.dart ytm_browse.dart ytm_lyrics.dart
    streams/
      player_client.dart      # Y15 VISIONOS (+ fallbacks)
      relay_server.dart       # 8.2 loopback 1 MiB relay
      net_family.dart         # 8.3 shared HttpClient + IPv4/IPv6 switch
      dash_mpd.dart           # 8.4 option B (Android video_player)
      stream_selector.dart    # quality/codec rules
      stream_cache.dart       # in-memory, expire-aware
      ejs_solver.dart         # phase 6 (flutter_js)
    thirdparty/ ryd.dart sponsorblock.dart
    lyrics/ model.dart query_clean.dart repository.dart(race) parsers/{ttml,a2_lrc,lrc,plain,unwrap}.dart sources/{lrclib,ytm_tab,yt_transcript,unison,kugou}.dart
    download/ chunk_downloader.dart merger.dart download_service.dart
    playback/ playback_service.dart audio_handler.dart smtc_adapter.dart
    db/ app_db.dart tables/*.dart daos/*.dart
  features/
    yt_home/ yt_search/ yt_watch/ yt_channel/ yt_playlist/ yt_library/ yt_subs/
    ytm_home/ ytm_explore/ ytm_search/ ytm_player/ ytm_album/ ytm_artist/ ytm_playlist/ ytm_library/ ytm_profile/
    downloads/ settings/
  app.dart main.dart
assets/innertube_clients.json
tool/probe.dart
```
Riverpod: `innertubeProvider`, `visitorDataProvider` (async, cached), `ytApiProvider`, `ytmApiProvider`, `streamResolverProvider.family(videoId)`, `playbackServiceProvider` (keepAlive), `downloadServiceProvider` (keepAlive), `dbProvider` (keepAlive), DAO stream providers (`watchSubscriptions()`, …), feature notifiers per screen with `AsyncNotifier` + pagination state.

App shell: one app with two modes (bottom switch "YouTube | Music"), or two flavors sharing `core/`. Recommended: **one app, two shells**. The shared PlaybackService lets YTM video mode and YT background audio reuse the same engine.

---

## 13. Implementation phases (each ends with probe + manual test)

| Phase | Scope | Done when |
|---|---|---|
| P0 | Run `tool/probe.dart` (section 15). Fix client constants until all core rows PASS | VISIONOS stream PASS incl. range at 5 MiB+ |
| P1 | Core: dio InnerTube layer, clients.json, visitorData, json helpers, Drift DB + DAOs, Riverpod skeleton, routing (go_router) | unit tests on recorded JSON fixtures |
| P2 | YT: search (+filters, suggestions, continuation), watch page (Y4), channel (Y5–Y7), playlist (Y8) | lists paginate, no crash on unknown renderers |
| P3 | Playback: Y15 resolver + selector, **relay (8.2) + family switch (8.3)**, media_kit video+external audio (Android fallback 8.4), quality switch, speed, captions (Y16), SponsorBlock, RYD counts, history/resume, 403 recovery | 1080p (avc1) plays on desktop + Android; quality switch keeps position |
| P4 | Local account: subscribe/unsubscribe, RSS feed, local home (11.3), likes/dislikes, playlists, library, backup/import | home populated from subs + history |
| P5 | Downloads: chunked + resume + ffmpeg merge, audio-only, download manager UI | 1080p H.264+AAC → mp4 plays offline; resume after kill |
| P6 | Fallbacks: VISIONOS_YTDLP profile, WEB_EMBEDDED + EJS on flutter_js (isolate), error UX for kids/age | kids video plays via embedded |
| P7 | YTM: home/explore/moods/charts (M1–M5), search+filters (M6–M7), queue/radio (M8), song↔video (M9), album/artist/playlist (M13–M16) | queue auto-extends via continuation |
| P8 | YTM player: audio-only, quality setting (Opus 160/70/50, AAC 128/48), lyrics engine 6.2.5–6.2.6 (race: LRCLIB→YTM tab→transcript; TTML/A2/LRC parsers; word-sync view; offset), loudness normalization, probe+coalesce (6.2.1), export m4a (6.2.3), likes, playlists, profile, cache LRU, downloads (audio) | offline cached song plays in airplane mode |
| P9 | Background: audio_service (Android/macOS), mpris (Linux), smtc (Windows), lock-screen artwork, headset buttons | controls work on each OS |
| P10 | Hardening: retries/backoff (429), client-version bump workflow, settings to override clients JSON, crash-free parsing tests from saved fixtures | probe green on all 4 OS |

---

## 14. Risk list

| Risk | Mitigation |
|---|---|
| VISIONOS gets killed (like ANDROID_VR on 2026-08-17) | client JSON override, P6 embedded+EJS fallback, watch yt-dlp/NewPipe releases and bump constants |
| SABR-only rollout to all clients | no Dart SABR implementation exists. References: yt-dlp PR #13515 (SABR downloader), `LuanRT/yt-sabr-shaka-demo`, `moderntube/innertube-rs`. Large job; keep it out of v1 |
| PO token needed for captions | `get_transcript` fallback (Y16b). Hide CC if both fail |
| Explicit/kids/age content | show a clear "restricted" message. No login by design |
| 429 / IP blocks (user IP) | exponential backoff, de-dupe in-flight requests, cache aggressively |
| Renderer schema changes | defensive parsing (4.7), fixture tests, field-level fallbacks |
| ffmpeg binary size | `_min` variant (LGPL). Stream copy only |
| Bot check per IP / address family (F3) | IPv4⇄IPv6 switch (8.3), cache aggressively, avoid burst prefetch |
| Throttled open-ended reads (F6) | loopback relay with 1 MiB ranges (8.2) |
| Random VISIONOS 403 ~1/25 (F5) | re-resolve + resume, 3-try budget |
| IP-bound URLs (F4) | never share URLs between devices. Cast needs a LAN relay (YouPipe `CastProxy`); out of scope v1 |
| URL serves 1st MiB then 403 (6.2.1) | probe past 1 MiB, ≥16 KiB, 6 s before play/cache; exclude client per track on refusal |
| Request storms on permanent failures (6.2.1) | 10-min unplayable verdict cache, coalesced resolves, serialized JS |
| Dart download 403s seen by YouPipe (F8) | shared client + same UA/family. If still flaky on Android, a native OkHttp chunk downloader (YouPipe pattern) as a last resort |

Legal: this uses YouTube's private API, which YouTube's ToS doesn't allow. Fine for a non-commercial portfolio, but don't publish to Play Store. License: if you port code (not just constants/endpoints) from NewPipe (GPL-3), Metrolist (GPL-3) or kmep (GPL-3), your app must be **GPL-3.0**. ytmusicapi is MIT, yt-dlp is Unlicense, youtube_explode_dart is BSD-3. Simplest: license the repo GPL-3.0.

---

## 15. Probe script — `tool/probe.dart` (run this first)

Not executed by me (my sandbox can't reach youtube.com). Create a pure-Dart package and run it on your PC and on an Android device (`dart run` on desktop; on Android, call `runProbe()` from a debug screen). **Stream URLs are IP-bound (F4), so the range tests are only valid on the device that ran the player request.** Run the full probe on the phone too, over Wi-Fi and over mobile data (IPv6).

`pubspec.yaml` (probe package):
```yaml
name: yt_probe
environment: { sdk: ">=3.4.0 <4.0.0" }
dependencies:
  crypto: ^3.0.0
```

```dart
// tool/probe.dart — dart run tool/probe.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';

const hl = 'en', gl = 'US';
const fourKVideo = 'aqz-KE-bpKQ'; // Big Buck Bunny 60fps 4K (expect avc1 1080p)
const channelId = 'UC_x5XG1OV2P6uZZ5FSM9Ttw'; // Google for Developers
const desktopUa =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0';

final _rnd = Random.secure();
const _abc = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
String rand(int n) => List.generate(n, (_) => _abc[_rnd.nextInt(64)]).join();

final hc = HttpClient()..userAgent = null;
int passN = 0, failN = 0;

void report(String name, bool ok, [Object info = '']) {
  ok ? passN++ : failN++;
  stdout.writeln('${ok ? 'PASS' : 'FAIL'}  $name  $info');
}

void info(String name, Object v) => stdout.writeln('INFO  $name  $v');

Future<(int, String)> send(String method, String url,
    {Map<String, String> headers = const {}, Object? json}) async {
  final rq = await hc.openUrl(method, Uri.parse(url));
  headers.forEach(rq.headers.set);
  if (json != null) {
    final bytes = utf8.encode(jsonEncode(json));
    rq.headers.set('Content-Type', 'application/json');
    rq.contentLength = bytes.length;
    rq.add(bytes);
  }
  final rs = await rq.close();
  final body = await rs.transform(const Utf8Decoder(allowMalformed: true)).join();
  return (rs.statusCode, body);
}

Future<dynamic> postJson(String url, Map<String, String> h, Map<String, dynamic> body) async {
  final (code, txt) = await send('POST', url, headers: h, json: body);
  if (code != 200) throw 'HTTP $code ${txt.length > 200 ? txt.substring(0, 200) : txt}';
  return jsonDecode(txt);
}

Iterable<dynamic> findAll(dynamic j, String key) sync* {
  if (j is Map) {
    for (final e in j.entries) {
      if (e.key == key) yield e.value;
      yield* findAll(e.value, key);
    }
  } else if (j is List) {
    for (final v in j) {
      yield* findAll(v, key);
    }
  }
}

int countKeys(dynamic j, List<String> keys) =>
    keys.fold<int>(0, (s, k) => s + findAll(j, k).length);

// ---------- clients ----------
const web = {'clientName': 'WEB', 'clientVersion': '2.20260805.01.00', 'platform': 'DESKTOP'};
const webRemix = {'clientName': 'WEB_REMIX', 'clientVersion': '1.20260804.16.00', 'platform': 'DESKTOP'};
const androidMusic = {'clientName': 'ANDROID_MUSIC', 'clientVersion': '7.21.50'};
const analytics = {'clientName': 'WEB_MUSIC_ANALYTICS', 'clientVersion': '2.0'};
const vision = {
  'clientName': 'VISIONOS', 'clientVersion': '1.04', 'clientScreen': 'WATCH', 'platform': 'MOBILE',
  'deviceMake': 'Apple', 'deviceModel': 'RealityDevice17,1', 'osName': 'visionOS',
  'osVersion': '26.6.0.23O770',
};
const visionUa =
    'com.google.visionos.youtube/1.04(RealityDevice17,1; U; CPU visionOS 26_6_0 like Mac OS X; US)';
const visionYtdlp = {
  'clientName': 'VISIONOS', 'clientVersion': '1.02', 'deviceMake': 'Apple',
  'deviceModel': 'RealityDevice17,1', 'osName': 'visionOS', 'osVersion': '26.5.23O471',
};
const visionYtdlpUa =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15';

Map<String, dynamic> ctx(Map<String, Object> client, String? visitor) => {
      'context': {
        'client': {
          ...client, 'hl': hl, 'gl': gl, 'utcOffsetMinutes': 0,
          if (visitor != null) 'visitorData': visitor,
        },
        'user': {'lockedSafetyMode': false},
        'request': {'useSsl': true, 'internalExperimentFlags': []},
      }
    };

Map<String, String> webHdr(String id, String ver, String origin, String? visitor, {String ua = desktopUa}) => {
      'User-Agent': ua,
      'X-YouTube-Client-Name': id,
      'X-YouTube-Client-Version': ver,
      'Origin': origin,
      'Referer': '$origin/',
      'Cookie': 'SOCS=CAE=',
      if (visitor != null) 'X-Goog-Visitor-Id': visitor,
    };

const yt = 'https://www.youtube.com/youtubei/v1';
const ytm = 'https://music.youtube.com/youtubei/v1';

Future<T?> step<T>(String name, Future<T> Function() f) async {
  try {
    return await f();
  } catch (e) {
    report(name, false, e);
    return null;
  }
}

// ---------- stream checks ----------
Future<(int, int)> rangeGet(String url, int start, int end, String ua) async {
  final rq = await hc.getUrl(Uri.parse('$url&range=$start-$end'));
  rq.headers.set('User-Agent', ua);
  final rs = await rq.close();
  var n = 0;
  await for (final c in rs) {
    n += c.length;
  }
  return (rs.statusCode, n);
}

Future<void> checkPlayer(String label, String videoId, String? visitor,
    {bool ytdlpProfile = false}) async {
  final cpn = rand(16);
  final url = ytdlpProfile
      ? '$yt/player?prettyPrint=false'
      : 'https://youtubei.googleapis.com/youtubei/v1/player?prettyPrint=false&t=${rand(12)}&id=$videoId';
  final ua = ytdlpProfile ? visionYtdlpUa : visionUa;
  final h = ytdlpProfile
      ? webHdr('101', '1.02', 'https://www.youtube.com', visitor, ua: ua)
      : {'User-Agent': ua, 'X-Goog-Api-Format-Version': '2'};
  final body = {
    ...ctx(ytdlpProfile ? visionYtdlp : vision, visitor),
    'videoId': videoId, 'cpn': cpn, 'contentCheckOk': true, 'racyCheckOk': true,
  };
  final pr = await step('$label player', () => postJson(url, h, body));
  if (pr == null) return;
  final status = pr['playabilityStatus']?['status'];
  report('$label playability', status == 'OK', '$status ${pr['playabilityStatus']?['reason'] ?? ''}');
  final fmts = (pr['streamingData']?['adaptiveFormats'] as List?) ?? const [];
  final direct = fmts.where((f) => f['url'] != null).toList();
  final ciphered = fmts.where((f) => f['signatureCipher'] != null || f['cipher'] != null).length;
  final withN = direct.where((f) => Uri.parse(f['url']).queryParameters.containsKey('n')).length;
  final vids = direct.where((f) => f['height'] != null).toList();
  final auds = direct.where((f) => f['audioQuality'] != null).toList();
  final maxH = vids.fold<int>(0, (m, f) => max(m, (f['height'] as num).toInt()));
  report('$label direct urls', direct.isNotEmpty,
      'total=${fmts.length} direct=${direct.length} ciphered=$ciphered nParam=$withN');
  info('$label video max height', maxH);
  info('$label itags', direct.map((f) => '${f['itag']}:${(f['mimeType'] as String).split(';').first}:${f['height'] ?? f['audioQuality']}').join(' '));
  info('$label hasSabrUrl', pr['streamingData']?['serverAbrStreamingUrl'] != null);
  info('$label expiresInSeconds', pr['streamingData']?['expiresInSeconds']);

  Future<void> testFmt(String tag, Map f) async {
    final u = '${f['url']}&cpn=$cpn';
    final len = int.tryParse('${f['contentLength'] ?? ''}') ?? 0;
    final a = await step('$label $tag range0', () => rangeGet(u, 0, 1048575, ua));
    if (a != null) report('$label $tag range 0-1MiB', a.$1 == 200 || a.$1 == 206, 'http=${a.$1} bytes=${a.$2}');
    if (len > 6 * 1048576) {
      final b = await step('$label $tag range5', () => rangeGet(u, 5 * 1048576, 6 * 1048576 - 1, ua));
      if (b != null) report('$label $tag range 5-6MiB', b.$1 == 200 || b.$1 == 206, 'http=${b.$1} bytes=${b.$2}');
    }
  }

  if (vids.isNotEmpty) {
    vids.sort((a, b) => (b['height'] as num).compareTo(a['height'] as num));
    final avc = vids.where((f) => (f['mimeType'] as String).contains('avc1')).toList();
    final pool = avc.isNotEmpty ? avc : vids;
    final target = pool.firstWhere((f) => (f['height'] as num) <= 1080, orElse: () => pool.last);
    info('$label avc1 max height', avc.isEmpty ? 0 : avc.first['height']);
    await testFmt('video${target['height']}p/${target['itag']}', target);
  }
  if (auds.isNotEmpty) {
    final a = auds.firstWhere((f) => f['itag'] == 251, orElse: () => auds.first);
    await testFmt('audio/${a['itag']}', a);
  }
  final caps = findAll(pr['captions'], 'captionTracks').expand((e) => e as List).toList();
  info('$label caption tracks', caps.length);
  if (caps.isNotEmpty) {
    final base = caps.first['baseUrl'] as String;
    info('$label caption exp=xpe', base.contains('exp=xpe'));
    final r = await step('$label captions', () => send('GET', '$base&fmt=vtt', headers: {'User-Agent': ua}));
    if (r != null) report('$label captions vtt', r.$1 == 200 && r.$2.startsWith('WEBVTT') && r.$2.length > 30, 'http=${r.$1} len=${r.$2.length}');
  }
}

Future<void> main() async {
  // Y1 visitorData
  final vis = await step('Y1 visitor_id', () async {
    final j = await postJson('$yt/visitor_id?prettyPrint=false',
        {'User-Agent': visionUa, 'X-Goog-Api-Format-Version': '2'}, ctx(vision, null));
    return j['responseContext']?['visitorData'] as String?;
  });
  report('Y1 visitorData', vis != null && vis.isNotEmpty, vis ?? '');
  final wh = webHdr('1', web['clientVersion']!, 'https://www.youtube.com', vis);

  // Y2 search
  String? firstVid;
  await step('Y2 search', () async {
    final j = await postJson('$yt/search?prettyPrint=false', wh,
        {...ctx(web, vis), 'query': 'lofi hip hop', 'params': 'EgIQAfABAQ%3D%3D'});
    final ids = [
      ...findAll(j, 'videoRenderer').map((v) => v['videoId']),
      ...findAll(j, 'lockupViewModel').map((v) => v['contentId']),
    ].whereType<String>().toList();
    firstVid = ids.isEmpty ? null : ids.first;
    final cont = findAll(j, 'continuationCommand').isNotEmpty;
    report('Y2 search videos', ids.isNotEmpty, 'n=${ids.length} continuation=$cont');
  });

  // Y3 suggestions
  await step('Y3 suggest', () async {
    final (c, t) = await send('GET',
        'https://suggestqueries-clients6.youtube.com/complete/search?client=youtube&ds=yt&gl=$gl&q=lofi&xhr=t',
        headers: {'Origin': 'https://www.youtube.com', 'Referer': 'https://www.youtube.com'});
    report('Y3 suggest', c == 200 && t.contains('lofi'), 'http=$c');
  });

  // sw.js_data: auto WEB clientVersion + visitorData (NewPipe master / youtube_explode_dart)
  await step('SW sw.js_data', () async {
    var (c, t) = await send('GET', 'https://www.youtube.com/sw.js_data', headers: {'User-Agent': desktopUa});
    if (t.startsWith(")]}'")) t = t.substring(4);
    final d = jsonDecode(t) as List;
    final row = d[0][2][0][0] as List;
    report('SW clientVersion', '${row[16]}'.startsWith('2.'), 'ver=${row[16]} visitorLen=${'${row[13]}'.length} http=$c');
  });

  // Y19 shorts sequence
  await step('Y19 shorts', () async {
    final j = await postJson('$yt/reel/reel_watch_sequence?prettyPrint=false', wh,
        {...ctx(web, vis), 'sequenceParams': 'CA8%3D'});
    final ids = findAll(j, 'reelWatchEndpoint').map((e) => e['videoId']).whereType<String>().toList();
    report('Y19 reel_watch_sequence', ids.isNotEmpty, 'n=${ids.length} continuation=${findAll(j, 'continuation').isNotEmpty}');
  });

  // Y4 next
  if (firstVid != null) {
    await step('Y4 next', () async {
      final j = await postJson('$yt/next?prettyPrint=false', wh,
          {...ctx(web, vis), 'videoId': firstVid, 'contentCheckOk': true, 'racyCheckOk': true});
      final rel = countKeys(j, ['compactVideoRenderer', 'lockupViewModel']);
      final title = findAll(j, 'videoPrimaryInfoRenderer').isNotEmpty;
      final likes = findAll(j, 'segmentedLikeDislikeButtonViewModel').isNotEmpty;
      report('Y4 next', rel > 0 && title, 'related=$rel primaryInfo=$title likeVM=$likes');
    });
  }

  // Y5 resolve_url
  await step('Y5 resolve', () async {
    final j = await postJson('$yt/navigation/resolve_url?prettyPrint=false', wh,
        {...ctx(web, vis), 'url': 'https://www.youtube.com/@Google'});
    final id = findAll(j, 'browseId').whereType<String>().firstOrNull;
    report('Y5 resolve_url', id?.startsWith('UC') ?? false, id ?? '');
  });

  // Y6/Y7 channel videos tab
  await step('Y7 channel', () async {
    final j = await postJson('$yt/browse?prettyPrint=false', wh,
        {...ctx(web, vis), 'browseId': channelId, 'params': 'EgZ2aWRlb3PyBgQKAjoA'});
    final n = countKeys(j, ['videoRenderer', 'lockupViewModel', 'richItemRenderer']);
    report('Y7 channel videos tab', n > 0, 'items=$n');
  });

  // Y9 logged-out home
  await step('Y9 home', () async {
    final j = await postJson('$yt/browse?prettyPrint=false', wh, {...ctx(web, vis), 'browseId': 'FEwhat_to_watch'});
    info('Y9 FEwhat_to_watch items (0 = blank home, expected possible)', countKeys(j, ['richItemRenderer']));
  });

  // Y10-12 kiosks
  for (final k in [
    ('Y10 live', 'UC4R8DWoMoI7CAwX8_LjQHig', 'EgdsaXZldGFikgEDCKEK'),
    ('Y11 gaming', 'UCOpNcN46UbXVtpKMrmU4Abg', 'Egh0cmVuZGluZw%3D%3D'),
    ('Y12 podcasts', 'FEpodcasts_destination', 'qgcCCAM%3D'),
  ]) {
    await step(k.$1, () async {
      final j = await postJson('$yt/browse?prettyPrint=false', wh, {...ctx(web, vis), 'browseId': k.$2, 'params': k.$3});
      final n = countKeys(j, ['videoRenderer', 'lockupViewModel', 'richItemRenderer', 'gridVideoRenderer']);
      report(k.$1, n > 0, 'items=$n');
    });
  }

  // Y14 charts
  await step('Y14 charts', () async {
    final j = await postJson('https://charts.youtube.com/youtubei/v1/browse?alt=json&prettyPrint=false',
        webHdr('31', '2.0', 'https://charts.youtube.com', vis), {
      ...ctx(analytics, null),
      'browseId': 'FEmusic_analytics_charts_home',
      'query': 'perspective=CHART_DETAILS&chart_params_country_code=$gl&chart_params_chart_type=TRENDING_VIDEOS',
    });
    final vv = findAll(j, 'videoViews').whereType<List>().firstOrNull;
    report('Y14 trending charts', (vv?.length ?? 0) > 0, 'n=${vv?.length}');
  });

  // Y17 RSS
  await step('Y17 rss', () async {
    final (c, t) = await send('GET', 'https://www.youtube.com/feeds/videos.xml?channel_id=$channelId');
    report('Y17 rss', c == 200 && t.contains('<entry>'), 'http=$c entries=${'<entry>'.allMatches(t).length}');
  });

  // Y15/Y16 streams
  await checkPlayer('Y15 visionOS(NewPipe) 4K', fourKVideo, vis);
  await checkPlayer('Y15b visionOS(yt-dlp) 4K', fourKVideo, vis, ytdlpProfile: true);
  await checkPlayer('Y15c visionOS no-visitor', fourKVideo, null);

  // ---------- YouTube Music ----------
  final mh = webHdr('67', webRemix['clientVersion']!, 'https://music.youtube.com', vis);
  final mq = '?prettyPrint=false&alt=json';
  await step('M1 home', () async {
    final j = await postJson('$ytm/browse$mq', mh, {...ctx(webRemix, vis), 'browseId': 'FEmusic_home'});
    final n = countKeys(j, ['musicCarouselShelfRenderer', 'musicImmersiveCarouselShelfRenderer']);
    report('M1 FEmusic_home', n > 0, 'shelves=$n continuation=${findAll(j, 'nextContinuationData').isNotEmpty || findAll(j, 'continuationCommand').isNotEmpty}');
  });
  for (final b in [('M2 explore', 'FEmusic_explore'), ('M3 moods', 'FEmusic_moods_and_genres')]) {
    await step(b.$1, () async {
      final j = await postJson('$ytm/browse$mq', mh, {...ctx(webRemix, vis), 'browseId': b.$2});
      final n = countKeys(j, ['musicCarouselShelfRenderer', 'musicNavigationButtonRenderer', 'gridRenderer']);
      report(b.$1, n > 0, 'n=$n');
    });
  }
  await step('M5 charts', () async {
    final j = await postJson('$ytm/browse$mq', mh, {
      ...ctx(webRemix, vis), 'browseId': 'FEmusic_charts', 'formData': {'selectedValues': [gl]}
    });
    report('M5 FEmusic_charts', countKeys(j, ['musicCarouselShelfRenderer', 'musicShelfRenderer']) > 0);
  });
  await step('M7 suggest', () async {
    final j = await postJson('$ytm/music/get_search_suggestions$mq', mh, {...ctx(webRemix, vis), 'input': 'coldp'});
    report('M7 suggestions', countKeys(j, ['searchSuggestionRenderer']) > 0);
  });

  String? songId, albumId, artistId, plId;
  Future<dynamic> ytmSearch(String q, String params) =>
      postJson('$ytm/search$mq', mh, {...ctx(webRemix, vis), 'query': q, 'params': params});
  await step('M6 songs', () async {
    final j = await ytmSearch('coldplay yellow', 'EgWKAQIIAWoMEA4QChADEAQQCRAF');
    songId = findAll(j, 'videoId').whereType<String>().firstOrNull;
    report('M6 search songs', songId != null, 'items=${countKeys(j, ['musicResponsiveListItemRenderer'])} first=$songId');
  });
  await step('M6x songs alt suffix (YouPipe Music)', () async {
    final j = await ytmSearch('coldplay yellow', 'EgWKAQIIAWoSEAUQCRADEAQQChAOEBAQFRAR');
    report('M6x songs alt suffix', countKeys(j, ['musicResponsiveListItemRenderer']) > 0);
  });
  await step('M6 albums', () async {
    final j = await ytmSearch('coldplay', 'EgWKAQIYAWoMEA4QChADEAQQCRAF');
    albumId = findAll(j, 'browseId').whereType<String>().where((s) => s.startsWith('MPREb')).firstOrNull;
    report('M6 search albums', albumId != null, albumId ?? '');
  });
  await step('M6 artists', () async {
    final j = await ytmSearch('coldplay', 'EgWKAQIgAWoMEA4QChADEAQQCRAF');
    artistId = findAll(j, 'browseId').whereType<String>().where((s) => s.startsWith('UC')).firstOrNull;
    report('M6 search artists', artistId != null, artistId ?? '');
  });
  await step('M6 playlists', () async {
    final j = await ytmSearch('chill hits', 'EgeKAQQoADgBagwQDhAKEAMQBBAJEAU%3D');
    plId = findAll(j, 'browseId').whereType<String>().where((s) => s.startsWith('VL')).firstOrNull;
    report('M6 search featured playlists', plId != null, plId ?? '');
  });
  for (final b in [('M13 album', albumId), ('M14 artist', artistId), ('M16 playlist', plId)]) {
    if (b.$2 == null) continue;
    await step(b.$1, () async {
      final j = await postJson('$ytm/browse$mq', mh, {...ctx(webRemix, vis), 'browseId': b.$2});
      final n = countKeys(j, ['musicResponsiveListItemRenderer', 'musicCarouselShelfRenderer', 'musicShelfRenderer']);
      report(b.$1, n > 0, 'n=$n');
    });
  }

  if (songId != null) {
    String? lyricsId, relatedId;
    await step('M8 next', () async {
      final j = await postJson('$ytm/next$mq', mh, {
        ...ctx(webRemix, vis),
        'videoId': songId, 'playlistId': 'RDAMVM$songId', 'isAudioOnly': true,
        'enablePersistentPlaylistPanel': true, 'tunerSettingValue': 'AUTOMIX_SETTING_NORMAL',
        'watchEndpointMusicSupportedConfigs': {
          'watchEndpointMusicConfig': {'hasPersistentPlaylistPanel': true, 'musicVideoType': 'MUSIC_VIDEO_TYPE_ATV'}
        },
      });
      final ids = findAll(j, 'browseId').whereType<String>();
      lyricsId = ids.where((s) => s.startsWith('MPLY')).firstOrNull;
      relatedId = ids.where((s) => s.startsWith('MPTR')).firstOrNull;
      final q = countKeys(j, ['playlistPanelVideoRenderer']);
      report('M8 queue', q > 1, 'tracks=$q lyrics=$lyricsId related=$relatedId counterpart=${findAll(j, 'counterpart').isNotEmpty}');
    });
    if (lyricsId != null) {
      await step('M10 lyrics', () async {
        final j = await postJson('$ytm/browse$mq', mh, {...ctx(webRemix, vis), 'browseId': lyricsId});
        report('M10 plain lyrics', findAll(j, 'musicDescriptionShelfRenderer').isNotEmpty);
      });
      await step('M11 timed lyrics', () async {
        final j = await postJson('$ytm/browse$mq',
            {'User-Agent': desktopUa, 'Origin': 'https://music.youtube.com', if (vis != null) 'X-Goog-Visitor-Id': vis},
            {...ctx(androidMusic, vis), 'browseId': lyricsId});
        info('M11 timedLyricsData present', findAll(j, 'timedLyricsData').isNotEmpty);
      });
    }
    if (relatedId != null) {
      await step('M12 related', () async {
        final j = await postJson('$ytm/browse$mq', mh, {...ctx(webRemix, vis), 'browseId': relatedId});
        report('M12 related', countKeys(j, ['musicCarouselShelfRenderer', 'musicDescriptionShelfRenderer']) > 0);
      });
    }
    await step('M20 get_transcript', () async {
      final id = utf8.encode(songId!);
      final params = base64.encode([0x0A, id.length, ...id]);
      final j = await postJson('$ytm/get_transcript$mq', mh, {...ctx(webRemix, vis), 'params': params});
      info('M20 transcript cues', findAll(j, 'transcriptCueRenderer').length);
    });
    await checkPlayer('M18 visionOS song', songId!, vis);
  }

  // ---------- third party ----------
  final testId = firstVid ?? fourKVideo;
  await step('RYD', () async {
    final (c, t) = await send('GET', 'https://returnyoutubedislikeapi.com/votes?videoId=$testId');
    report('RYD votes', c == 200 && t.contains('dislikes'), 'http=$c $t');
  });
  await step('SponsorBlock', () async {
    final p = sha256.convert(utf8.encode('dQw4w9WgXcQ')).toString().substring(0, 4);
    final cats = Uri.encodeQueryComponent(jsonEncode(['sponsor', 'selfpromo', 'intro', 'outro', 'interaction']));
    final (c, t) = await send('GET', 'https://sponsor.ajay.app/api/skipSegments/$p?categories=$cats');
    report('SponsorBlock hash-prefix', c == 200 || c == 404, 'http=$c len=${t.length}');
  });
  await step('LRCLIB', () async {
    final (c, t) = await send('GET', 'https://lrclib.net/api/search?track_name=Yellow&artist_name=Coldplay',
        headers: {'User-Agent': 'yt-probe/0.1'});
    report('LRCLIB search', c == 200 && t.contains('syncedLyrics'), 'http=$c');
  });

  stdout.writeln('\nDONE  pass=$passN  fail=$failN');
  hc.close(force: true);
}
```

### 15.1 Reading results
| Row | Must | If FAIL |
|---|---|---|
| Y1 visitorData | PASS | try music.youtube.com HTML `ytcfg` VISITOR_DATA |
| Y15 visionOS playability + direct urls + range 0-1MiB **and** 5-6MiB | PASS | try Y15b. Bump `clientVersion`/`osVersion` from latest yt-dlp `_base.py` / NewPipe `ClientsConstants.java`. "403 after 1 MiB" = client dead (the android_vr pattern) |
| Y15 `avc1 max height` | 1080 for `aqz-KE-bpKQ` | if 0, avc1 missing → VP9 fallback / check itags |
| Y15 `nParam` | 0 | if >0, URLs need n-solving (EJS, P6) |
| Y15c no-visitor | expected FAIL/UNPLAYABLE | confirms visitorData is required |
| Y16 captions vtt | PASS ideally | empty body ⇒ PO token required ⇒ use Y16b get_transcript |
| Y9 | INFO only | 0 expected (YouPipe confirmed) ⇒ local home (11.3) |
| SW clientVersion | PASS | keep JSON constant as fallback |
| Y19 | PASS | Shorts tab off until fixed |
| M6x | either M6 or M6x PASS | use whichever suffix passes |
| M18 visionOS song | PASS | try www vs music host for the player request (Metrolist uses music host) |
| M11 | INFO | false ⇒ LRCLIB synced fallback |
| M20 | INFO | >0 ⇒ transcript lyrics source usable (6.2.6 #3) |

### 15.2 Optional: is youtube_explode_dart's stream layer alive today?
```dart
// add dependency youtube_explode_dart: ^3.1.0
import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
Future<void> main() async {
  final yt = YoutubeExplode();
  try {
    final m = await yt.videos.streams.getManifest('aqz-KE-bpKQ'); // default: androidSdkless
    final v = m.videoOnly.sortByVideoQuality().first;
    final a = m.audioOnly.withHighestBitrate();
    print('video ${v.videoResolution.height}p itag ${v.tag}  audio itag ${a.tag}');
    for (final s in [v, a]) {
      final rq = await HttpClient().getUrl(Uri.parse('${s.url}&range=0-1048575'));
      final rs = await rq.close();
      print('itag ${s.tag} -> HTTP ${rs.statusCode}');
      await rs.drain();
    }
  } catch (e) {
    print('youtube_explode_dart FAIL: $e');
  } finally {
    yt.close();
  }
}
```

---

## 16. Maintenance loop (no central server)
1. When playback breaks, run `tool/probe.dart`.
2. Diff client constants against yt-dlp `yt_dlp/extractor/youtube/_base.py` (`INNERTUBE_CLIENTS`, `_DEFAULT_CLIENTS`), NewPipeExtractor `ClientsConstants.java`, and Metrolist innertubex `YouTubeClient.kt` + `PlaybackClientCatalog.kt`.
3. Update `assets/innertube_clients.json`, ship an app update. Power users can paste JSON in Settings → Advanced → Client override.

---

## 17. Sources
- yt-dlp source (`_base.py` INNERTUBE_CLIENTS, `_video.py` defaults/CHUNK_SIZE, Changelog 2026.08.19–2026.10.26): https://github.com/yt-dlp/yt-dlp
- yt-dlp PO Token Guide: https://github.com/yt-dlp/yt-dlp/wiki/PO-Token-Guide
- yt-dlp PR #17461 (android_vr 403 since 2026-08-17): https://github.com/yt-dlp/yt-dlp/pull/17461
- yt-dlp PR #17184 (visionos client): https://github.com/yt-dlp/yt-dlp/pull/17184
- yt-dlp SABR downloader PR #13515: https://github.com/yt-dlp/yt-dlp/pull/13515
- NewPipeExtractor (ClientsConstants, YoutubeStreamHelper visionOS, kiosks, search/channel params): https://github.com/TeamNewPipe/NewPipeExtractor
- Metrolist + innertubex (YouTubeClient.kt, PlaybackClientCatalog.kt benchmarks): https://github.com/MetrolistGroup/Metrolist · https://github.com/MetrolistGroup/innertubex
- ytmusicapi (YTM endpoints/params): https://github.com/sigma67/ytmusicapi
- youtube_explode_dart (3.1.0 source, clients, EJS solver): https://github.com/Hexer10/youtube_explode_dart · issues: https://github.com/Hexer10/youtube_explode_dart/issues
- kmep: https://pub.dev/packages/kmep · https://github.com/dipodev20/kmep
- Harmony Music (Flutter YTM reference): https://github.com/anandnet/Harmony-Music
- YouPipe (docs/streaming.md, playback.md, apis.md, innertube.md, data.md, downloads.md, phase0.md): https://github.com/SanuSanal/YouPipe (no LICENSE file → reference only)
- YouPipe Music (docs/streaming.md, apis.md, playback.md): https://github.com/SanuSanal/YouPipe-Music
- SourecResource (StreamResolver/PlayerClient/InnerTubeXResolver, data/lyrics/*, playback/AudioCache, ChunkedDataSource), GPL-3.0.
- NewPipeExtractor commits `9ed62db3` (remove ANDROID/IOS/WEB_EMBEDDED usage), `61e04a4c` (update clients), `efd3d854` (client version from sw.js_data, 2026-10-20); tag v0.26.5 = 2026-08-15
- Return YouTube Dislike API: https://github.com/Anarios/return-youtube-dislike
- SponsorBlock API: https://wiki.sponsor.ajay.app/w/API_Docs
- LRCLIB server source: https://github.com/tranxuanthang/lrclib
- pub.dev: media_kit, audio_service, audio_service_mpris, smtc_windows, ffmpeg_kit_flutter_new_min, drift, drift_flutter, flutter_riverpod, riverpod_generator, dio, flutter_js, just_audio, just_audio_media_kit, media_store_plus
- Caption PO-token behaviour (2026): https://github.com/jdepoix/youtube-transcript-api/issues/592
- YouTube RSS feeds (2026): https://feeder.co/help/rss/youtube-feeds/
