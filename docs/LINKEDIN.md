# LinkedIn: progress and what to check next (2026-11-12, about 15:40 IST)

Issue: **#12** ("linkedin is not working", still open). Releases with LinkedIn work: v1.2.0.0, v1.2.1.0, v1.2.1.3, v1.2.1.4.

## How a LinkedIn share works today

1. The user shares a post link from the LinkedIn app. `ShareReceiverActivity` puts it in `pending_items` (status `queued`) and shows "Saved ✓".
2. The background analysis (`lib/pipeline/runner.dart`, `_linkedin`) checks first for a page saved by **Read in app** (`linkedin-page-<id>.html` in the temp folder, `linkedInPagePath` in `lib/pipeline/linkedin.dart`). If one is there, the app uses it and deletes it.
3. Without a saved page, the app fetches the **public** post page once, logged out, with no cookies (`linkedInUserAgent`).
   - HTTP 999 ("too many requests from this network"): fails at once and is **never retried**.
   - HTTP 429 or 5xx: left for the next run.
   - Anything else, or a page with no post on it: fails with a reason.
4. `parseLinkedIn` reads the schema.org JSON-LD (`SocialMediaPosting`, `VideoObject`, `Article`), falling back to the `og:` tags. It collects the text, author, up to 10 pictures and up to 3 videos, only from `licdn.com` media hosts.
5. Each picture and video is analysed with the post text as context, and `mergeAnalyses` turns them into one note.
6. If it fails, the reason is saved in `pending_items.title`. The Library then shows **"Could not analyse N shares"** (last 7 days, hidden once the same link is in the library) with these buttons:
   - **Read in app** (LinkedIn only)
   - **Retry**
   - **Dismiss**

### Read in app (v1.2.1.4)
- Opens the post in the app's own web page (`lib/ui/web_screen.dart`, `readPost: true`), with no login.
- When the page has loaded, an **Analyse this post** button appears. It takes the page's HTML. If no post can be found in it, it says so and suggests a screenshot. Otherwise the HTML is saved for that share, the share is queued again, and the analysis reads that HTML instead of fetching from LinkedIn.

## What was found

- **"Not showing in the analysis at all"** had two causes:
  - A share that failed in the background was never shown anywhere. Fixed in v1.2.1.3 by the failed-shares card.
  - LinkedIn answered the phone with **HTTP 404** for public posts.
- **The 404 comes and goes for the network; it doesn't mean the post is private.**
  - On 2026-11-12, the jasonhaider post (`ugcPost-7221657670615719939`) showed "Page not found" even in the in-app page at 15:28.
  - Shared again at 15:29, it was fetched and analysed normally ("Cooperative Power of Dung Beetles").
  - The same posts always loaded from the computer.
- Many failures came at once (several shares at 15:09). A burst of requests may set it off. **This is a guess, not proven.**
- After that post was saved, all 11 failed rows disappeared from the card. They were most likely all that same link, shared several times (the card hides failures whose link is in the library). **Not confirmed:** a release build can't read the database.

## Why the app doesn't do more

- **Your rule:** no LinkedIn login or cookies (to avoid a ban), and HTTP 999 is never retried.
- **Open-source scrapers** (github.com/topics/linkedin-scraper, read 2026-11-12):
  - **Need your login or session:** joeyism/linkedin_scraper, stickerdaniel/linkedin-mcp-server, cullenwatson/StaffSpy, open-linkedin-api. This is ban risk on your own account. Not used.
  - **Jobs only:** speedyapply/JobSpy, linkedin-jobs-api. They don't read posts.
  - **Paid fetch services:** Scrapfly (`SCRAPFLY_KEY`), Bright Data / luminati-io, Apify actors. These need no LinkedIn account and get through the 404 and 999 answers, but they are paid (free trials) and need your own key.
- The official LinkedIn API is limited to approved partners, and LinkedIn has no public oEmbed for posts.
- **Screenshots always work:** a shared screenshot never contacts LinkedIn.
- **Not to be done:** changing request headers to get past LinkedIn's bot check. That was refused and must not be tried again.

## What to check next (in this order)

1. [ ] **Read in app on a page that shows the post:**
   - Share a public post.
   - If it fails, tap Read in app, wait for the post to show, then tap Analyse this post.
   - Expected: a note with the post text.
   - Not yet seen: at test time, LinkedIn showed "Page not found".
2. [ ] **Same Wi-Fi test:** share one post while the phone is on the same Wi-Fi as the computer. If it always works there, the mobile network or its IP is the cause.
3. [ ] **Burst test:** share 3 posts at once, then 3 posts a minute apart. If only the burst fails, add a short gap between LinkedIn fetches in a run (for example 20–30 seconds). Spacing requests is allowed; it is not a workaround of the bot check.
4. [ ] **Retry one at a time** on old failures, a minute apart, and note which succeed.
5. [ ] **Decide on an optional paid fetch key**, as the app already does with the Apify key:
   - It would be used only when the public fetch fails.
   - The key is kept on the phone, and the Privacy Policy must name the service.
   - Ask before building.
6. [ ] The **Semi build** on the phone (failed card, Read in app). Only the Full build has been checked on the phone.
7. [ ] Close #12 only when shares work again on the phone, or when you agree that screenshots and Read in app are enough. Comment the state on #12 either way.

## Files
- `lib/pipeline/linkedin.dart`: parser, host checks, `linkedInPagePath`
- `lib/pipeline/runner.dart`: `_linkedin` (fetch or saved page) and `_linkedinPost` (analysis)
- `lib/ui/library_screen.dart`: `_FailedCard`, `recentFailures`, Read in app
- `lib/ui/web_screen.dart`: in-app page, `readPost`, Analyse this post
- `packages/reelbot_native/.../CounterDb.kt`: `pending()` returns `title` (the failure reason)
- Tests:
  - `test/linkedin_test.dart`
  - `test/failed_shares_test.dart`
  - the two Read in app tests in `test/runner_test.dart`
