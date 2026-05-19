# Hivefy Project Structure

## 📂 Directories & Files

### 1. `lib/main.dart`

- **Purpose:** Application entry point. Sets up Hive DB, Riverpod provider scopes, and initiates background audio handlers.

---

### 2. 📂 `lib/components`

- **generalcards.dart:** Standard card layouts for songs, albums, and playlists.
- **shimmers.dart:** Smooth skeleton loading placeholders.
- **showmenu.dart:** Context actions menu (add to playlist, download, share).
- **snackbar.dart:** Premium toast/alert overlays.
- **timersheet.dart:** Bottom sheet interface for sleep timer config.

---

### 3. 📂 `lib/models`

- **database.dart:** Hive database adapters, keys, storage boxes, and initializer logic.
- **datamodel.dart:** Serialization, deserialization, and structures for Songs, Albums, Artists, Playlists.

---

### 4. 📂 `lib/screens`

- **dashboard.dart:** Core shell containing navigation bar and active tab screens.
- **home.dart:** Main landing hub. Displays charts, recommendations, and recent plays.
- **library.dart:** Storage drawer for user local playlists, downloaded songs, and liked items.
- **search.dart:** Unified global search interface with filtering.

#### 📂 `lib/screens/features`

- **about.dart:** App version and license info.
- **drawer.dart:** Sidebar menu drawer.
- **language.dart:** Select custom language for JioSaavn content search.
- **profile.dart:** User name and customization options.
- **queuesheet.dart:** Drag-and-drop bottom sheet to re-order/view the playing song queue.
- **settings.dart:** Storage, quality, cache, theme, and server toggle configurations.
- **soundcapsule.dart:** Custom sound equalizer and system sound controls.

#### 📂 `lib/screens/views`

- **albumviewer.dart:** Track listings, covers, and actions for selected albums.
- **artistviewer.dart:** Displays artist details, followers, bio, top songs, and albums.
- **playlistviewer.dart:** Displays songs inside curated or user-created playlists.
- **songsviewer.dart:** Generic song list list-view.

---

### 5. 📂 `lib/services`

- **audiohandler.dart:** Extends `BaseAudioHandler`. Handles play, pause, seek, repeat, background controls.
- **defaultfetcher.dart:** Saavn fallback API endpoints.
- **jiosaavn.dart:** Direct API requests to JioSaavn backend for song details, streaming links, lyrics.
- **latestsaavnfetcher.dart:** Specialized JioSaavn crawler for new releases and charts.
- **localnotification.dart:** Displays download status and active tasks in notification panel.
- **offlinemanager.dart:** Direct filesystem downloads, integrity checks, and offline playing path resolution.
- **shufflemanager.dart:** Custom shuffle algorithms and state handlers.
- **sleeptimer.dart:** Countdown timer that pauses music when elapsed.
- **systemconfig.dart:** Dynamic system configurations, themes, and locale storage.

---

### 6. 📂 `lib/shared`

- **constants.dart:** Global Riverpod providers (liked lists, active players, key bindings, tabs).
- **likedsong.dart:** Business logic to manage local database state for favorite/liked tracks.
- **player.dart:** The mini-player bar and the full-screen immersive Spotify-like player.
- **serversource.dart:** Base backend URLs and mirror configurations.

---

### 7. 📂 `lib/utils`

- **format.dart:** String parsers, capitalization helpers, duration formatting, follower count shortening.
- **share_image.dart:** Custom dynamic share card generator that draws high-res metadata onto a Canvas for story sharing.
- **theme.dart:** Color tokens, HSL adjustments, and text styles.

## Hivefy File Tree

```text
E:\HIVEFY\LIB
│   main.dart
│
├───components
│       generalcards.dart
│       shimmers.dart
│       showmenu.dart
│       snackbar.dart
│       timersheet.dart
│
├───models
│       database.dart
│       datamodel.dart
│
├───screens
│   │   dashboard.dart
│   │   home.dart
│   │   library.dart
│   │   search.dart
│   │
│   ├───features
│   │       about.dart
│   │       drawer.dart
│   │       language.dart
│   │       profile.dart
│   │       queuesheet.dart
│   │       settings.dart
│   │       soundcapsule.dart
│   │
│   └───views
│           albumviewer.dart
│           artistviewer.dart
│           playlistviewer.dart
│           songsviewer.dart
│
├───services
│       audiohandler.dart
│       defaultfetcher.dart
│       jiosaavn.dart
│       latestsaavnfetcher.dart
│       localnotification.dart
│       offlinemanager.dart
│       shufflemanager.dart
│       sleeptimer.dart
│       systemconfig.dart
│
├───shared
│       constants.dart
│       likedsong.dart
│       player.dart
│       serversource.dart
│
└───utils
        format.dart
        share_image.dart
        theme.dart
```
