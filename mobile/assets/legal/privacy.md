# Privacy Policy

Reel Analyser · Effective 7 November 2026 · Version 1.0

## 1. The short version

- Reel Analyser has no accounts, no ads, no analytics, no tracking and no servers of its own.
- Your notes, chats and counts are stored only on your phone.
- When you analyse a reel or ask a question, the content is sent straight from your phone to the AI service you chose, using your own API key. We never see it.
- You can erase everything from Settings at any time.

## 2. Who we are

Reel Analyser is made by an independent developer ("we", "us"), published on GitHub as nevil-sanish. We are the controller of the little data the app handles, which is none that leaves your phone to us. Contact: https://github.com/nevil-sanish/reel-analyser/issues

## 3. What the app stores on your phone

- **Notes** you create by sharing a reel, short or photo: title, summary, key points, tags, transcript, on-screen text, caption, author name, link, and a picture for photo notes.
- **Chats** with your notes.
- **Share queue**: the items waiting to be analysed and their status.
- **API keys** you enter, kept in Android's encrypted storage (Keystore).
- **Settings**: theme, a few on/off flags.
- **Insights (optional)**: counts of Reels and Shorts watched, stored as anonymous fingerprints (no author, caption or text), and time spent in Instagram and YouTube, by day and hour.
- **Debug capture**: off by default. If you switch it on in Counter debug, it keeps recent screen text of Instagram and YouTube on your phone for troubleshooting, until you switch it off.

All of this lives in the app's private storage, which other apps cannot read. Android's automatic cloud backup is turned off for this app.

## 4. What leaves your phone, and why

We do not receive any of it. It goes directly from your phone to these services, only when you use the feature:

- **Google Gemini API** (ai.google.dev): the video, frames, thumbnail and caption of a reel you share; or your saved notes and question when you chat. Used with your Gemini key.
- **OpenAI, Anthropic (Claude), Groq**: the same kind of content, only if you add that provider's key and it is used as a fallback or for chat.
- **Apify** (optional): the reel's link code, only if you add an Apify token and Instagram will not hand over the video.
- **Instagram (Meta) and YouTube (Google)**: to read the reel you shared, the app requests the public page or video of that link, like a web browser. They see your IP address and device details, as with any browser, and their own policies apply. The in-app link view loads the same pages.
- **GitHub**: the download version checks once a day whether a newer release exists (your IP address is visible to GitHub). "Send feedback" opens a GitHub issue page in your browser with only the text you wrote; you decide whether to post it.

Each AI provider handles what it receives under its own terms and privacy policy. Some providers treat free-tier and paid-tier data differently, including using free-tier content to improve their products. Check the terms of the key you use. We do not control this.

We do not collect your name, email, contacts, location, advertising ID or device identifiers, and we do not send crash reports.

## 5. Permissions and why

- **Internet**: to reach the services above.
- **Notifications** (optional): "note ready", an evening digest, and an alert if reel counting stops working.
- **Usage access** (optional, you turn it on in Android settings): reads Android's own app-usage statistics to show your time in Instagram and YouTube. Nothing is read from the screen.
- **Accessibility service** (optional, download version only): lets the app notice when you are on an Instagram or YouTube Reels or Shorts screen so it can count them. It reads only those two apps, never types, taps or scrolls, and stores only an anonymous fingerprint and a count. It ignores every other app.
- **Battery optimisation exemption and Autostart** (optional, download version only): so Android does not stop background counting.
- **Share target**: so Reel Analyser appears in the Share menu.

## 6. Data retention

- **Notes and chats**: kept until you delete them. Notes you have read move to the Archive after 3 days and are kept there until you delete them. Deleting removes them from the app straight away.
- **Shared photos**: kept while a note or queued item uses them, then removed.
- **Share queue entries**: finished, failed or stopped entries are deleted after 30 days.
- **Insights data**: deleted automatically after 90 days.
- **API keys**: kept until you remove them, erase your data or uninstall.
- **Exports you make** (Downloads/ReelBot): kept until you delete those files. They are not encrypted, except API keys, which are included only if you choose that and are protected with your passphrase.
- **Data held by AI providers and other services**: governed by their own policies. We cannot delete it for you; use your account with that provider.

## 7. Deleting your data

Settings → "Erase all my data" deletes every note, chat, queued item, photo, count and key from the app. Uninstalling the app does the same. Files you exported must be deleted by you.

## 8. Security

Keys are kept in Android's hardware-backed encrypted storage and sent only over HTTPS, in request headers, never in web addresses. Exports with keys use AES-256-GCM with a key derived from your passphrase (PBKDF2-SHA256, 600,000 rounds); we cannot recover a forgotten passphrase. No system is perfectly secure, so keep your phone locked and your keys private.

## 9. Children

Reel Analyser is not directed at children. You must be at least 13 years old, or the minimum age in your country if higher. We do not knowingly collect data from children, and the app holds no data about anyone but its user on the phone.

## 10. Your rights

Everything the app holds is in the app: you can read, correct, export (Settings → Backup) and delete it yourself. Depending on where you live (for example under the EU GDPR, India's Digital Personal Data Protection Act 2023, or California law) you may have further rights to access, correct, erase, restrict or move your data and to withdraw consent. Because we hold none of your data, exercising them is done with the tools above. We do not sell or share personal data and do not use it for advertising.

## 11. Changes

If this policy changes, the new version appears in the app and at the address below, with a new date. Material changes will be shown in the app before they apply.

## 12. Contact

Questions or requests: https://github.com/nevil-sanish/reel-analyser/issues
