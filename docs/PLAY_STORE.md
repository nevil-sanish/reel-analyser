# Google Play: what is ready, what you must do, what could block approval

Prepared 7 November 2026 for v0.9.8+. This is a checklist and the answers to Play Console's forms, not legal advice: have a lawyer read the Privacy Policy and Terms before launch if you can.

## 1. Two builds

| | `direct` (GitHub) | `play` (Google Play) |
|---|---|---|
| Accessibility service (reel counting) | yes, optional | **removed** (Play restricts it to accessibility tools) |
| Battery-optimisation exemption, Autostart, Counter debug | yes | removed |
| In-app "newer version" banner and APK download | yes | **removed** (Play must be the only updater) |
| Usage access (time in Instagram and YouTube) | yes, optional | yes, optional |

Build commands (flavors need `--flavor`):

```bash
flutter build apk --release --flavor direct
```

```bash
flutter build appbundle --release --flavor play --dart-define=PLAY_BUILD=true
```

The bundle is `build/app/outputs/bundle/playRelease/app-play-release.aab`. Same package id and signing key as the APK. Use Play App Signing: upload this key as the **upload key**.

## 2. Documents (done)

- Privacy Policy: [privacy.md](../mobile/assets/legal/privacy.md). The public URL for Play is `https://github.com/nevil-sanish/reel-analyser/blob/main/mobile/assets/legal/privacy.md`.
- Terms of Use: [terms.md](../mobile/assets/legal/terms.md).
- Both are bundled in the app (Settings → About and legal) and shown for agreement on first start.
- Open-source licenses: Settings → Open-source licenses (Flutter collects them automatically).
- Retention rules are in the policy and enforced in code: Insights 90 days, finished queue entries 30 days, notes until deleted. "Erase all my data" in Settings deletes everything.
- Prominent disclosure before Usage access (and Accessibility in the direct build), as Play requires.

**Fill in before you submit:** the policy lists GitHub Issues as the contact. Play also needs a **developer contact email** in the Console, and, for the EU, your name and address if you are a "trader" (Digital Services Act). Add an email line to the Contact section of both documents if you want one shown.

## 3. Store listing (copy)

- **App name** (30 max): `Reel Analyser`
- **Short description** (80 max): `Turn reels and shorts you share into searchable notes with your own AI key.`
- **Full description**:

> Share a reel, short or screenshot and get a clear note: a short overview, every key point, what was said (transcript), the text on screen and what was mentioned. Ask questions across all your notes. Everything stays on your phone.
>
> • Share from Instagram or YouTube to Reel Analyser
> • Notes with overview, key points, transcript and on-screen text
> • Ask your notes: answers come only from what you saved
> • Several AI keys at once for faster analysis; see each reel's progress and stop any of them
> • Optional Insights: your time in Instagram and YouTube
> • Backup and restore, with API keys encrypted by a passphrase you choose
> • No account, no ads, no tracking, no servers: your notes never leave your phone except to the AI service you choose
>
> You bring your own free or paid AI key (Gemini, OpenAI, Claude, Groq). AI notes can be wrong. Reel Analyser is not affiliated with Instagram, Meta, YouTube or Google.

- **Category:** Productivity. **Tags:** note taking, AI assistant.
- Assets you must make: 512×512 icon (the launcher artwork), 1024×500 feature graphic, 2 to 8 phone screenshots (the Library with the progress card, a note with transcript, Ask, Settings → Backup).

## 4. Data safety form (answers)

- **Does the app collect or share user data?** The app itself sends nothing to the developer. Answer **"Yes, data is shared"** with the AI providers, because Play counts data sent to third-party services on the user's behalf. Declare:
  - **Photos and videos** (reels' video or frames, shared photos): shared with AI providers (Google, OpenAI, Anthropic, Groq) and, optionally, Apify. Purpose: **App functionality**. Optional (the user chooses to share each item). Not required for the app to work.
  - **Messages / other in-app content** (captions, note text and questions sent for chat): same recipients and purpose.
  - **App activity** (reels counted, time in apps): **collected on device only, not sent anywhere**: you may leave it undeclared as "collected" because it never leaves the device, or declare it as collected, not shared, optional, for App functionality, processed on device. Declaring it is the safer answer.
- **Is all data encrypted in transit?** Yes (HTTPS only).
- **Can users request data deletion?** Yes: Settings → Erase all my data, or uninstall. No account exists.
- **Security practices:** data encrypted in transit; user can request deletion; independent security review: no.
- **Privacy policy URL:** the GitHub URL in section 2.

## 5. Other Console declarations

- **App access:** all functionality available without login.
- **Ads:** no ads.
- **Content rating (IARC questionnaire):** user-generated content: **no** (the app does not publish user content to others); violence, sex, gambling, drugs: no. Note the app can summarise third-party video that the user shares, which the questionnaire covers as "user-supplied content only used privately". Expected rating: Everyone / PEGI 3 or 12 depending on the "unrestricted internet access" answer. Answer honestly that it loads web pages (in-app link view).
- **Target audience:** 13+ (not for children). Do not opt into Families.
- **News app / government / financial / health / COVID:** none.
- **Permissions:** Internet, notifications and Usage access need no special Console form. `PACKAGE_USAGE_STATS` is a user-granted special permission: describe it as "shows the user's time in Instagram and YouTube; optional". There is no Accessibility declaration because the play build has none.
- **Foreground service types:** the build includes WorkManager's short-service permission; no foreground service is started by the app. If the Console asks, state "WorkManager background analysis, no user-facing foreground service".
- **Target API:** 36 (current Flutter default). minSdk 29.
- **Data deletion web link:** not required (no accounts).

## 6. What could get the app rejected, in order of risk

1. **Instagram access.** The app reads Instagram pages in a hidden web view and with unofficial endpoints. That is against Instagram's terms and could draw a Meta complaint, and Play removes apps on valid IP or terms reports. Keeping the Play build to what users share is the safest position; there is no way to make it zero-risk. Consider making Instagram support clearly secondary or limiting Play to YouTube and photos.
2. **Accessibility service.** Removed from the play build for this reason. Do not add it back without Google's declaration and approval.
3. **Trademarks.** The name and listing mention Instagram and YouTube only to say what the app works with, with a disclaimer. Do not use their logos. Keep "Reel Analyser" as is (no "Instagram" in the app name).
4. **Misleading claims.** Do not promise accuracy. The listing says AI notes can be wrong.
5. **Self-update.** Removed from the play build.
6. **New personal developer accounts** must run a closed test with at least 12 testers for 14 days before production. Organisation accounts do not.

## 7. Your to-do list

1. Create a Play developer account (one-time fee, identity verification).
2. Add a contact email and, if asked, an address.
3. Make the icon, feature graphic and screenshots.
4. Build the bundle (section 1) and upload it to a closed testing track; invite testers.
5. Fill the Data safety, content rating and target audience forms from sections 4 and 5.
6. Paste the listing text from section 3 and the privacy URL.
7. Start the 14-day test if your account type requires it, then apply for production.
