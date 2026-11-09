# Privacy Policy

Reel Analyser · Effective 10 November 2026 · Version 1.2

## 1. The short version

- Reel Analyser has no accounts, no ads, no analytics, no tracking and no servers of its own.
- Your notes, chats and counts are stored only on your phone.
- When you analyse a reel or ask a question, the content is sent straight from your phone to the AI service you chose, using your own API key. We never see it.
- You can erase everything from Settings at any time.
- The app never takes screenshots and never records your screen, your voice or any video of you.
- The optional features that read the Reels and Shorts screens (the counter and the Reel blocker) work only in the full version, only after you allow them inside the app, and you can withdraw that at any time.

## 2. Who we are

Reel Analyser is made by an independent developer, Nevil Mathew Sanish ("we", "us"), published on GitHub as nevil-sanish. We are the controller of the little data the app handles, which is none that leaves your phone to us. Contact: https://github.com/nevil-sanish/reel-analyser/issues

## 3. What the app stores on your phone

- **Notes** you create by sharing a reel, short or photo: title, summary, key points, tags, transcript, on-screen text, caption, author name, link, and a picture for photo notes.
- **Chats** with your notes.
- **Share queue**: the items waiting to be analysed and their status.
- **API keys** you enter, kept in Android's encrypted storage (Keystore).
- **Settings**: theme, a few on/off flags.
- **Insights (optional)**: counts of Reels and Shorts watched, stored as anonymous fingerprints (no author, caption or text), and time spent in Instagram and YouTube, by day and hour.
- **Reel blocker (optional, full version)**: the rules you set (what to block, daily limits, allowed times), the minutes of reels you watched each day in each blocked app, and a history of the days you passed your limit, tried to cancel the block, cancelled it, kept it, changed the rules or removed the blocker. The history holds dates, times and kinds only. It holds no photos and no text you typed.
- **Daily goals (optional, full version)**: your public GitHub, Codeforces and LeetCode usernames, your daily targets, and for each finished day the counts, whether you met them, how many misses in a row, and the last day of any block. Only public usernames and numbers. No passwords, tokens or cookies are asked for or kept.
- **A written reason for changing a username (Daily goals, full version)**: usernames are locked once used. If you ask to change one, the reason you type is sent to the AI provider you already use (your own key, the cheapest model) together with the old and new username, only to check that it is a real reason. The app does not save the reason. That provider handles it under its own terms, like your notes. Without an AI key the change cannot be made.
- **A face photo (only if you cancel the block for a day)**: one photo, taken with your phone's own camera app, kept in the app's private storage.
- **Debug capture**: off by default. If you switch it on in Counter debug, it keeps the names and positions of the parts of the Instagram and YouTube screens, for troubleshooting. It never keeps text or pictures from the screen. Switching it off, or withdrawing your permission to read the reel screens, deletes it.

All of this lives in the app's private storage, which other apps cannot read. Android's automatic cloud backup is turned off for this app.

## 4. What leaves your phone, and why

We do not receive any of it. It goes directly from your phone to these services, only when you use the feature:

- **Google Gemini API** (ai.google.dev): the video, frames, thumbnail and caption of a reel you share; or your saved notes and question when you chat. Used with your Gemini key.
- **OpenAI, Anthropic (Claude), Groq**: the same kind of content, only if you add that provider's key and it is used as a fallback or for chat.
- **Apify** (optional): the reel's link code, only if you add an Apify token and Instagram will not hand over the video.
- **Instagram (Meta) and YouTube (Google)**: to read the reel you shared, the app requests the public page or video of that link, like a web browser. They see your IP address and device details, as with any browser, and their own policies apply. The in-app link view loads the same pages.
- **GitHub, Codeforces and LeetCode, only if you turn on Daily goals (full version)**: to read your own public activity, the app sends the site your public username (GitHub: api.github.com, a search for commits you authored on a given day; Codeforces: codeforces.com/api, your recent submissions; LeetCode: leetcode.com, the public profile query its own website uses, which is not an official API). It sends nothing else: no token, password, cookie or account. The site sees your IP address and device details, as with any browser, and its own policy applies. The answer is used on your phone and kept as a number per day. We never receive any of it. Requests happen when the app opens and in the background: automatically just after midnight, and about every 15 minutes while a day is waiting to be checked. There is no manual check.
- **GitHub**: the full version checks once a day whether a newer release exists (your IP address is visible to GitHub). "Send feedback" opens a GitHub issue page in your browser with only the text you wrote; you decide whether to post it.

Each AI provider handles what it receives under its own terms and privacy policy. Some providers treat free-tier and paid-tier data differently, including using free-tier content to improve their products. Check the terms of the key you use. We do not control this.

We do not collect your name, email, contacts, location, advertising ID or device identifiers, and we do not send crash reports.

## 5. Permissions and why

There are two versions. The **full** version has every feature. The **semi** version asks Android for nothing beyond the internet: no Accessibility, no Usage access, no notifications, no battery exemption, no Insights, no Reel blocker. It makes no network request except to the services you use.

- **Internet**: to reach the services above.
- **Notifications** (optional): "note ready", an evening digest, and an alert if reel counting stops working.
- **Usage access** (optional, you turn it on in Android settings): reads Android's own app-usage events for Instagram and YouTube, plus screen-off and lock events, to show your time in those two apps. It does not look at any other app and reads nothing from the screen.
- **Accessibility service** (optional, full version only): it needs two separate OKs from you, switching it on in Android settings and then "Allow reading the reel screens" inside this app, which is off by default. Until you give both, the app reads nothing. You can withdraw the second one in the app at any time (Settings → Set up Insights), and the first one in Android settings.
- **What the Accessibility service reads, once allowed**: Android tells it which app is in front, which it uses only to notice when you leave Instagram or YouTube. It keeps no record of other apps and reads nothing inside them. Inside Instagram and YouTube it reads the layout of the screen, including some on-screen text such as the author and caption, to tell that a Reel or Short is showing and to tell one reel from the next. That text is used in memory for that moment only. What is saved is an anonymous fingerprint (a hash), a count and the time spent. In a browser it reads only the address bar, to see whether the page is a reel or a short.
- **What it never does**: it never takes screenshots, never records the screen or video of it, never types, taps or scrolls for you, and never sends anything off the phone.
- **Reel blocker** (optional, full version): uses the same service. When your daily limit is used up or the time is outside the times you allowed, it opens a block screen over the reel. The rest of Instagram, YouTube and your browser is not blocked. To cancel the block for one day you take a photo of your face with your phone's camera app. The app checks on the phone that the photo has a face in it, shows it to you on a card with a quote, and deletes it after the day ends. It is never sent anywhere. The app has no camera permission of its own. To remove the blocker for good you type a paragraph; the paragraph is checked on the phone and is not stored or sent.
- **Daily goals** (optional, full version): when you miss a goal, the Accessibility service blocks the whole Instagram (and YouTube, if you chose it) app for the days of the penalty. For that it notes only which app is in front, and opens a block screen over it. It reads nothing inside that app while the penalty is on. It works only if you allowed reading the reel screens, as the Reel blocker does.
- **Battery optimisation exemption and Autostart** (optional, full version only): so Android does not stop background counting.
- **Share target**: so Reel Analyser appears in the Share menu.

## 6. Data retention

- **Notes and chats**: kept until you delete them. Notes you have read move to the Archive after 3 days and are kept there until you delete them. Deleting removes them from the app straight away.
- **Shared photos**: kept while a note or queued item uses them, then removed.
- **Share queue entries**: finished, failed or stopped entries are deleted after 30 days.
- **Insights data**: deleted automatically after 90 days.
- **Daily goals data**: each judged day is deleted after 90 days. Your usernames and targets are kept until you change them or erase your data.
- **Reel blocker data**: the minutes watched per day and the history are deleted automatically after 90 days. Your rules are kept until you change or remove them. The face photo is deleted after the day it was taken, the next time the app or its service runs.
- **API keys**: kept until you remove them, erase your data or uninstall.
- **Exports you make** (Downloads/ReelBot): kept until you delete those files. They are not encrypted, except API keys, which are included only if you choose that and are protected with your passphrase.
- **Data held by AI providers and other services**: governed by their own policies. We cannot delete it for you; use your account with that provider.

## 7. Deleting your data

Settings → "Erase all my data" deletes every note, chat, queued item, photo, count, blocker rule and history, daily goals and their results, face photo and key from the app. Uninstalling the app does the same. Files you exported must be deleted by you.

## 8. Security

Keys are kept in Android's hardware-backed encrypted storage and sent only over HTTPS, in request headers, never in web addresses. Exports with keys use AES-256-GCM with a key derived from your passphrase (PBKDF2-SHA256, 600,000 rounds); we cannot recover a forgotten passphrase. No system is perfectly secure, so keep your phone locked and your keys private.

## 9. Children

Reel Analyser is not directed at children. You must be at least 13 years old, or the minimum age in your country if higher. We do not knowingly collect data from children, and the app holds no data about anyone but its user on the phone.

## 10. Your rights

Everything the app holds is in the app: you can read, correct, export (Settings → Backup) and delete it yourself. Depending on where you live (for example under the EU GDPR, India's Digital Personal Data Protection Act 2023, or California law) you may have further rights to access, correct, erase, restrict or move your data and to withdraw consent. You can withdraw your permission to read the reel screens at any time, in the app (Settings → Set up Insights) or in Android settings. Because we hold none of your data, exercising them is done with the tools above. We do not sell or share personal data and do not use it for advertising.

## 11. Changes

If this policy changes, the new version appears in the app and at the address below, with a new date. Material changes will be shown in the app before they apply.

## 12. Contact

Questions or requests: https://github.com/nevil-sanish/reel-analyser/issues
