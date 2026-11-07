# Reel Analyser: open-source survey (Instagram + YouTube fetching)

**Checked:** 5 Nov 2026, by reading each project's source (not just its README).
**Feeds:** [PLAN.md](PLAN.md) §3, [ENDPOINTS.md](ENDPOINTS.md), [TESTS.md](TESTS.md).

Confidence tags as in PLAN: **[Certain]** = seen in code, **[Likely]** = strong inference, **[Guessing]** = filling gaps.

---

## 1. Instagram projects

| Project | ★ | Last push | Licence | Lang | How it gets a reel's video (logged out) | Verdict |
|---|---|---|---|---|---|---|
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | 205k | 2026-11-04 | Unlicense | Python | GraphQL `PolarisLoggedOutDesktopWWWPostRootContentQuery` (`doc_id 27130156389949648`, `variables {media_id}`), LSD token from the home page, `X-IG-App-ID 936619743392459`. Fallback: post page JSON `xig_polaris_media.if_not_gated_logged_out`. Needs Chrome TLS impersonation (`curl-cffi`) | **Primary source** for current endpoint names |
| [cobalt](https://github.com/imputnet/cobalt) | 46k | 2026-04-06 | AGPL-3.0 | JS | Cascade: `api/v1/oembed` → media id → mobile API `api/v1/media/<id>/info/` → `/p/<code>/embed/captioned/` (`contextJSON`) → GraphQL `PolarisPostActionLoadPostQueryQuery` (`doc_id 8845758582119845`) with tokens scraped from the post page | **Best design** (ordered fallbacks). AGPL: copy ideas, not code |
| [gallery-dl](https://github.com/mikf/gallery-dl) | 20k | 2026-10-31 | GPL-2.0 | Python | REST `api/v1/media/…` or GraphQL `query_hash`, both with the user's **login cookies** | No (login) |
| [instaloader](https://github.com/instaloader/instaloader) | 14k | 2026-11-01 | MIT | Python | Old `query_hash` GraphQL + `api/v1/media/` with login | No. [Likely] Its logged-out web GraphQL returns 401 since ~Jan 2025 (reported by social-knowledge-base) |
| [instagrapi](https://github.com/subzeroid/instagrapi) | 7k | 2026-11-03 | other | Python | Private mobile API, **logged in** | No (account bans) |
| [InstaFix](https://github.com/Wikidepia/InstaFix) | 1k | 2025-08-04 (archived) | MIT | Go | Embed page first (`/embed/captioned/`), then `graphql/query` `PolarisPostActionLoadPostQueryQuery` | Proved embed-first works at scale; archived |
| [InstaFix-Revived](https://github.com/Bl0ck154/InstaFix-Revived) | 20 | **2026-11-02** | MIT | Go | 1) embed page (3 retries) → 2) web GraphQL `PolarisPostActionLoadPostQueryQuery` (`doc_id 25531498899829322`, `variables {shortcode,…}`) → 3) "mobile" GraphQL `PolarisPostRootQuery` (`doc_id 27128499623469141`) → 4) `api/v1/oembed` for title/author/thumbnail. Negative cache per post, stale-cache on failure, single-flight per post, ids in env vars | **Most current cascade**; best operational ideas (negative cache, ids as config). Also uses a Googlebot crawler page and `r.jina.ai`, which we skip |
| [InstaFix-remote-scraper](https://github.com/Wikidepia/InstaFix-remote-scraper) | 7 | 2025-02-27 | — | Go | `graphql/query` `doc_id 8845758582119845` | Same as cobalt |
| [InstaDownload](https://github.com/Orang-Studio/InstaDownload) | 115 | 2026-11-03 | **GPL-3.0** (F-Droid lists MIT; the repo says GPL-3.0) | Kotlin | Post page `instagram.com/reel/<code>/`, scans `<script data-sjs>` for the item whose `pk` = decoded shortcode, reads `video_versions`. Sends a **Googlebot** UA. Rediscovers `doc_id`s from `static.cdninstagram.com/rsrc.php/…js` | Closest to us (Android, native, no login). GPL: ideas only. Skip the Googlebot UA |
| [totallynotdavid/downloader](https://github.com/totallynotdavid/downloader) | 9 | 2026-10-29 | MIT | TS | `api/graphql` `PolarisLoggedOutDesktopWWWPostRootContentQuery` `27130156389949648` (same as yt-dlp); profile queries `27553725110923321` / `27389614800735091`; detects `require_login` | Confirms yt-dlp's ids are current (Oct 2026) |
| [instagram-direct-url](https://github.com/victorsouzaleal/instagram-direct-url) | 88 | 2025-06-02 | none | TS | `graphql/query` → `xdt_shortcode_media.video_url` | Older variant of the web query |
| [Instagram-reels-downloader](https://github.com/Okramjimmy/Instagram-reels-downloader) | 53 | 2025-12-23 | MIT | TS | `PolarisPostActionLoadPostQueryQuery` `doc_id 10015901848480474` | Shows how often `doc_id`s rotate (4 different ids across projects) |
| [reelflow](https://github.com/code3-dev/reelflow) | 6 | 2025-03-12 | MIT | TS | Same query, `doc_id 10015901848480474` | Same |
| [vxinstagram](https://github.com/Lainmode/InstagramEmbed-vxinstagram) | 134 | 2026-10-31 | MIT | C# | Calls **snapsave**, a third-party downloader site | No (sends links to a third party) |
| [vxinst](https://github.com/bitwise74/vxinst) | 14 | 2025-03-27 (archived) | GPL-3.0 | Go | Embed page `contextJSON` | Same as InstaFix |
| [embetter](https://github.com/everettsouthwick/embetter) | 19 | 2026-10-28 | GPL-3.0 | JS | Rewrites links to ddinstagram/kkinstagram-style hosts | No (third-party hosts) |
| [n8n-instagram-scrapper-with-transcription](https://github.com/1ordo/n8n-instagram-scrapper-with-transcription) | 5 | 2025-04-16 | MIT | Python | Apify actor → `videoUrl` → Whisper | Same as our optional Apify step |
| [mcp-video-analyzer](https://github.com/guimatheus92/mcp-video-analyzer) | 111 | 2026-11-02 | MIT | TS | yt-dlp for download, then transcript + key frames + OCR for an LLM; Puppeteer for some sites | Good model for the **analysis** side (frames + transcript); too heavy for a phone |
| [social-knowledge-base](https://github.com/guimatheus92/social-knowledge-base) | 12 | 2026-06-29 | MIT | TS | gallery-dl with **login cookies** of a throwaway account → faster-whisper → LLM notes → RAG | Same product idea as Reel Analyser, server/desktop and login-based. Confirms the market gap: "no open-source tool does the full flow" |

## 2. YouTube projects

| Project | ★ | Last push | Licence | Lang | How it gets video/text | Verdict |
|---|---|---|---|---|---|---|
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | 205k | 2026-11-04 | Unlicense | Python | Innertube clients, signature/n-param JS, PO tokens | Arms race; not needed |
| [Invidious](https://github.com/iv-org/invidious) | 26k | 2026-11-03 | AGPL-3.0 | Crystal | Innertube via its own server | Server |
| [Seal](https://github.com/JunkFood02/Seal) | 30k | 2026-09-25 | GPL-3.0 | Kotlin | youtubedl-android (Python + yt-dlp in the APK) | Too big; GPL |
| [LibreTube](https://github.com/libre-tube/LibreTube) | 13k | 2026-11-02 | GPL-3.0 | Kotlin | Piped API or local NewPipeExtractor | Not needed |
| [ytdlnis](https://github.com/deniscerri/ytdlnis) | 11k | 2026-11-04 | GPL-3.0 | Kotlin | youtubedl-android | Too big; GPL |
| [youtube-transcript-api](https://github.com/jdepoix/youtube-transcript-api) | 8.6k | 2026-11-03 | MIT | Python | Captions via Innertube; blocked on cloud IPs | Text only; Shorts often have no captions |
| [YouTube.js](https://github.com/LuanRT/YouTube.js) | 5.4k | 2026-11-04 | MIT | TS | Innertube client (cobalt uses it), PO tokens | Not needed |
| [YoutubeExplode](https://github.com/Tyrrrz/YoutubeExplode) | 3.7k | 2026-11-01 | MIT | C# | Innertube + ciphers | Not needed |
| [NewPipeExtractor](https://github.com/TeamNewPipe/NewPipeExtractor) | 2k | 2026-11-02 | GPL-3.0 | Java | Pure-Java extractor | Not needed; GPL |
| [Grayjay](https://github.com/futo-org/grayjay-android) | 1.8k | 2026-11-03 | FUTO source-first (not OSI) | Kotlin | JS source plugins | Not needed |
| [pytubefix](https://github.com/JuanBindez/pytubefix) | 1.7k | 2026-10-16 | MIT | Python | Innertube clients + PO tokens | Not needed |
| [youtubedl-android](https://github.com/yausername/youtubedl-android) | 1.4k | 2025-11-16 | GPL-3.0 | Kotlin | Bundles Python + yt-dlp | Too big; GPL |
| [Piped-Backend](https://github.com/TeamPiped/Piped-Backend) | 171 | 2026-11-01 | AGPL-3.0 | Java | NewPipeExtractor on a server | Server |

## 3. What we learned

1. **YouTube: our approach wins.** Every downloader fights YouTube's PO tokens, signatures and client changes. Gemini reads public YouTube URLs itself (8 h/day free), so we download nothing. Fallback: keyless `youtube.com/oembed` for title, channel and thumbnail.
2. **Instagram: there are five logged-out routes, and they rot at different speeds.** In order of cost: embed page (one GET, no tokens) → logged-out post GraphQL (`media_id`) → web post GraphQL (`shortcode`) → post page JSON → `api/v1/oembed` (metadata only). Projects that last (cobalt, InstaFix-Revived) try several and fall through.
3. **`doc_id`s rotate.** Four different `PolarisPostActionLoadPostQueryQuery` ids appear across projects (`8845758582119845`, `10015901848480474`, `25531498899829322`, plus the logged-out query `27130156389949648`). Keep them in config, rediscover them from the JS bundles, and test them weekly.
4. **Operational patterns worth copying** (InstaFix-Revived): a negative cache per post (don't retry a dead post for an hour), single-flight (one fetch per post at a time), "use stale data if the new fetch fails", and per-step retries.
5. **Avoid:** login cookies (gallery-dl, instagrapi, social-knowledge-base), third-party downloader sites (snapsave, ddinstagram hosts), `r.jina.ai` proxies, and crawler user agents (Googlebot). All either risk accounts, leak links to third parties, or misrepresent the client.
6. **On a phone we have advantages servers don't:** a real Chrome (WebView) instead of TLS impersonation, a residential IP, and a handful of requests per day instead of thousands.
7. **Licences:** only Unlicense/MIT code may be copied (yt-dlp, InstaFix, InstaFix-Revived, totallynotdavid/downloader, YouTube.js, mcp-video-analyzer), with attribution. GPL/AGPL (cobalt, InstaDownload, gallery-dl, Seal, NewPipe, LibreTube) are ideas only.

## 4. Re-checking this survey

Re-run when an Instagram step starts failing in the debug screen (see [TESTS.md](TESTS.md) `T-LIVE-*`):
- `git log -1` of yt-dlp's `yt_dlp/extractor/instagram.py`, InstaFix-Revived's `handlers/scraper/data.go`, cobalt's `api/src/processing/services/instagram.js`.
- Compare their `doc_id`s and friendly names with `res/raw/ig_queries.json` ([ENDPOINTS.md](ENDPOINTS.md) §2).
