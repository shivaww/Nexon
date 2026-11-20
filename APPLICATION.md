# APPLICATION.md — Claude for Startups (Nexon)

Copy-paste answers for the Claude for Startups application form. Every fact below is verified against the repository, the live site, or the GitHub API — except the lines marked **OWNER**, which need founder input before submitting.

## Company

- **Company:** NexonAI — products: **Nexon** (shipped, this application) and **Nexon Studio** (AI motion graphics + voice, in development — https://github.com/shivaww/Recorder)
- **Website (fill this into the form's website field):** https://nexonai.me
- **Contact email:** founder@nexonai.me
- **Founder:** K. Shiva Reddy — https://www.linkedin.com/in/k-shiva-reddy21082008
- **Team:** 4 people — K. Shiva Reddy (founder/developer), K. Harsha Vardhan Reddy, R. Rithvik Ram, C. Naga Charan (developers).
- **Founded:** June 2026
- **Location:** Hyderabad, India
- **Stage:** Early stage, pre-revenue. Product shipped (v1.0.23); subscriptions planned, not launched.
- **Business model (planned):** Tools free to use; subscriptions sell managed model access — Claude and other models as credits per plan with daily usage limits (limits already implemented server-side). Chats stay on the user's device either way.
- **Legal status:** Four-person team; no registered legal entity (per owner).

## What it does (2 sentences, plain language)

Nexon is the first product from NexonAI: a source-available (PolyForm Noncommercial 1.0.0) AI coding and research app that runs entirely on an Android phone — a Flutter app with a Python bridge inside Termux, giving AI agents a real shell, real files, and live web search, with no cloud IDE in between. Users bring their own API keys; chats and keys stay on the device, with optional encrypted backup to their own Google Drive.

## How Nexon uses Claude

- Users run Claude models through the Anthropic API or OpenRouter with their own keys. Prompt caching and extended thinking are implemented natively (`lib/services/llm/llm_service.dart:438-442`, `lib/services/llm/chat_client.dart:944-986`), and model lists are fetched live from providers (`lib/services/llm/chat_client.dart:117`).
- Nexon itself is developed with heavy use of Claude (founder-confirmed, Oct 9, 2026).
- 36 other providers are also supported (OpenAI, Google, Mistral, xAI, DeepSeek, Groq, ...) — bring-your-own-key. Nexon is not Claude-only.

## Stage and traction (real numbers, verified Oct 9, 2026)

- Latest release: v1.0.23, APK published on GitHub Releases (`nexon-1.0.23.apk`).
- Downloads across all releases: ~16. GitHub stars: 3. Forks: 1.
- Honest framing: early stage — small but real distribution, zero marketing spend.

## Before submitting (owner checklist)

- Fill the application form's website field with `https://nexonai.me`.
- Make sure the Claude Console account uses `founder@nexonai.me` and the organization is named "Nexon".
- Complete every **OWNER** line above.
- Wait until the site changes are live and verified (privacy and terms returning HTTP 200) before submitting.
