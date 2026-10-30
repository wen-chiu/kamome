# Handoff — film music, rethought from scratch (2026-10-30)

Four rounds of rule-composed music (PR #340, `Docs/handoff-music.md` and
`Tools/kamome-music.py` on branch `claude/sleepy-maxwell-2pu24r`) were judged not good enough.
This document gathers Chiu's feedback and every round's result, breaks down what the film needs
from music, surveys where music could come from (licence first), and recommends one path.
**Nothing here changes the app.** Music in the film stays deferred (`Docs/current-state.md`)
until Chiu decides otherwise, and every route below adds a dependency, which needs his
confirmation (`CLAUDE.md` rule 2).

Labels follow `CLAUDE.md` rule 4: **VERIFIED** (read or measured), **INFERRED** (reasoned, not
measured), **UNKNOWN**. Each unmeasured claim names the cheapest thing that would settle it.

---

## Part A — the record

### A1. Chiu's feedback, verbatim and in order (2026-10-29 → 2026-10-30)

1. **The ask:** 「我想要搭配影片加入無版權音樂 可以怎麼實作?最好影片可以自動搭上beats跟符合那國家或旅遊風格」
2. **The brief:** 「目前我只想用免費授權的 是不是選擇不多 這樣的話你直接幫我找者地區方向創作以下這幾種beats跟旋律呢 可以一直重複 然後在我們影片轉折處加不同的beats?」

   | region | mood |
   |---|---|
   | 日本、台灣、韓國 | 輕 lo-fi、city pop 風、木吉他 |
   | 冰島、挪威 | ambient、鋼琴、post-rock |
   | 越南、泰國 | 溫暖的 acoustic、輕 tropical |
   | 紐西蘭、澳洲 | indie folk |

3. **The target:** 「https://suno.com/s/Lpa9UYUtg5XQc3kB 我讓suno幫我試試看 但他要錢 給你參考 大概做到這樣就很完美了」
4. **After round 1** (synthesised instruments): 「東亞的吉他聲聽起來不夠自然 北歐主旋律聽起來有點單調乏味 其他的主旋律整體還可以 大概有六七成完成度 但全部配樂的協調性都不夠 配起來很怪不好聽 尤其是打擊樂的部分」. He then chose CC0 recorded samples over synthesis, and an upright piano plus vibraphone over the guitar.
5. **After round 2:** 「整體還是有種詭異的不協調感 我覺得你太認真想要做和音 太多東西你沒辦完整控制協調就會變得畫蛇添足 我覺得你可以先減法 或是參考網路上免費資訊的和弦配置 給你聽聽看這個polarstep配的音樂 你不要看影片 聽音樂就好 基本上我們就做出類似適合影片配樂的旋律先給他四五種風格」. The reference was a Polarsteps trip film's music; the video is someone else's work and is not, and must never be, in this repository.
6. **After round 3,** a written brief, "Round 4: Musicality & Emotional Composition": round 3 was consonant but mechanical, repetitive, without emotional depth. Allow add9, maj7, sus2/sus4, inversions, voice leading, a moving bass; 2-bar motifs grown into 4- and 8-bar phrases; up to 5–6 layers with one role each; avoid excess mallets, constant plucking, toy sounds, synthetic imitations of acoustic instruments; a groove per genre; development from intro to peak; better balance, bass, melody, stereo and reverb; CC0-compatible, deterministic, timeline-arranged, fit for a commercial iOS app. Test Tropical and Pop as A (restrained) and B (expressive). His goal: *"Kamome to have its own recognizable musical identity: warm, cinematic, melodic, tasteful, and emotionally engaging."*
7. **An outside generator:** a seeded melody generator written by another AI assistant, run on the round 4 arrangement with only the tune swapped.
8. **The verdict** on round 4 A with both tunes: 「不行 更難聽了 兩個都是 都有一種很古老遊戲配樂的粗糙感 不符克壯闊有趣的公路旅行配樂」, and the direction: 「另外開一個seesion整理我所有feedback跟成果 我覺得要整個重頭思考拆解 應該需要AI開源音樂模型的幫助 做出類似suno的成果」

### A2. Every round, what was built and what was measured

| round | what was built | what Chiu heard | measured |
|---|---|---|---|
| 1 | synthesised guitar, piano, bass, drums; 4 regional styles | melodies 60–70 %; East Asian guitar unnatural; Nordic monotonous; nothing sits together, percussion worst | — |
| 2 | VCSL CC0 recordings (pinned commit) + synthesised kick, bass, pad, lead; new Nordic tune | 「詭異的不協調感」, too much harmony; subtract; match the Polarsteps music | Polarsteps reference: ~118 BPM, plain triads in one key, a short repeated hook, four layers |
| 3 | triads only, ≤ 4 layers, five moods (`lofi`, `cinematic`, `tropical`, `acoustic`, `pop`) | consonant but mechanical, repetitive, no depth | 17 of 26 / 21 of 30 drive bars repeat an earlier bar (tropical/pop); loudness flat |
| 4 | Tropical and Pop recomposed: colour chords, moving bass, 16-bar tunes, 5-rung energy ladder, A/B arrangements, per-instrument EQ, ducking | (with an outside generator's tune as well) 「更難聽了 … 很古老遊戲配樂的粗糙感」 | 0–7 repeated bars; loudness climbs −27 → −20; 20 of 20 loop seams clean; outside tune sits inside the piano's range 65–68 % of note-time (vs 25–28 %), glockenspiel played up to 17 semitones below its lowest recording |

Source for all of row 2–4's numbers: `Docs/handoff-music.md` on `claude/sleepy-maxwell-2pu24r`
(VERIFIED — read 2026-10-30; the numbers themselves were measured by that session and not re-run
here).

### A3. What was learned

- **VERIFIED (by Chiu's ears, four times):** changing the notes did not move the verdict. Round 4
  fixed every measured complaint of round 3 (repetition, flat dynamics, plain triads) and was
  judged *worse*.
- **INFERRED — the ceiling was the sound, not the composition.** One-shot samples and bare
  oscillators fired on a grid is how tracker and General MIDI game music was made, which is
  exactly what Chiu named (「古老遊戲配樂」). Nothing was performed (no strum, bowing, breath,
  pedal), the palette was piano, mallets and small percussion (no guitars, full kit, strings,
  voices), and the mix had no bus compression, saturation or mastering. "Grand and fun"
  (壯闊有趣) needs the opposite: a full band, real performances, a mastered mix.
  *Settle:* play one model-generated track in the same key and tempo beside a round 4 loop; if
  Chiu hears the gap at once, the inference holds. That is Part D's first experiment.
- **INFERRED — the reference was never a "composition" target.** His Suno track and the Polarsteps
  music are *produced records*. A pure-stdlib composer cannot reach a produced record by rules;
  the measurable gap (Part B2) is mostly production.
- **VERIFIED — free-licence recorded samples are thin.** VCSL is CC0 but has no drum kit, no
  electric or steel-string guitar ensemble, no string section legato; its lowest glockenspiel is
  G5 (`handoff-music.md` Evidence). Any rule-based route stays inside that palette.

### A4. What the existing tool can still give

Read `Tools/kamome-music.py` at `origin/claude/sleepy-maxwell-2pu24r` (2,119 lines).

| piece | reusable? | why |
|---|---|---|
| event model — `go`, `stop`, `crossing`, `end` and the `LinearTimeline` mapping (`journeyStartS`, hold start/end, `crossingBeatWindowsS`, end card) | **yes** (INFERRED) | It is about the film, not the sound. *Settle:* feed one real film's events (desk, local fixture only) to `plan()` with a generated track's BPM. |
| `plan()` — snaps each event to the nearest beat, rejects two changes on one beat, reports the shift in ms | **yes** (VERIFIED by reading: it needs only `beat_samples` and the events) | A generated track with a known, steady BPM gives it the same input. |
| energy ladder (`intro`, `build`, `main`, `peak`, `stop`) and the climb-at-the-next-8-bar-line rule | **as an idea** (INFERRED) | It assumes five loops at five energies. A generated track gives sections, not rungs; the ladder maps to "which section plays" and "filter/duck at a stop". |
| `beatmap.json` schema, the soft ceiling, fades | **partly** | Needs `sections` (start beat, energy) added; loops and one-shots become optional. |
| composer, sampler, synth voices, Freeverb, VCSL fetch | **no** | This is the part Chiu rejected. |
| "If it is wired in" notes (mix after `RecapVideoEncoder`, mux with passthrough, AAC) | **yes** (INFERRED, unchanged) | Independent of where the audio comes from. |

PR #340 is open and is another session's; this document does not edit its files.

---

## Part B — what the film needs, from scratch

### B1. Requirements

| need | value | label |
|---|---|---|
| film length | 60–90 s for the standard film (`total_duration_min_s` 60, `total_duration_max_s` 90), up to 300 s (`standard_duration_max_s`) in `Config/TrackingConfig.json` | VERIFIED (read) |
| loops or whole tracks | **whole tracks of ~2–3 min, cut to length**, not loops. A produced track has an intro, a lift and an ending; a loop has none of them, which is part of why round 3 sounded repetitive. Cut: intro from 0, crossfade on a phrase line into the track's ending so the last chord lands on the end card. | INFERRED. *Settle:* cut one generated track to a 75 s film by hand in any editor and listen. |
| changes at the film's turns | each `go`/`crossing` lands on a downbeat (`plan()`); a `stop` dips the music (low-pass + −6 dB, or drops to a quieter section) and it comes back at the next `go`; the ending lands on the end card | INFERRED from the brief; the dip values are tunables for `Config/TrackingConfig.json` |
| beats must be known | every bundled track needs a measured BPM, first-downbeat offset and section starts — measured once at the desk and shipped as a beatmap, never computed on the phone | INFERRED |
| per-country moods | the table in A1 → five moods: `lofi` (JP TW KR), `cinematic` (IS NO), `tropical` (VN TH), `folk` (NZ AU), `pop` (everyone else — still Chiu's call) | VERIFIED (Chiu's table); the `pop` default is UNKNOWN |
| how many tracks | 2–3 per mood so two trips to one country do not sound the same → **10–15 tracks**, ~30–45 min of audio, ~30–45 MB at 128 kbps AAC; or download on first premium use | INFERRED. Bundle size is Chiu's call. |
| tiers | ADR 2026-07-20 (`Docs/decisions.md` line 593): *free = silent export (user adds platform music), premium = in-app track*; it also rejected *bundled copyrighted music (royalty-free + optional silent export only)* | VERIFIED (read). Whether this still stands is Chiu's; nothing here reopens it. |
| licence | safe to bundle in a commercial iOS app, mixed into a film the user then posts to Instagram/YouTube/TikTok | — see Part C |
| §0 | music generation needs no trip data; nothing about a trip goes to any music service | VERIFIED by design |

### B2. What "like Suno" means, measurably

"Like Suno" is a produced record, not a better tune. Checkable proxies (the verdict stays Chiu's
ears; none of these is a gate):

1. **Instrumentation:** a full band where the style calls for it — kit with real ghost notes and
   fills, bass guitar, strummed acoustic or clean electric guitar, keys, strings or pads — each
   sounding performed. Check: name the instruments heard; no mallets carrying the tune.
2. **Form:** intro → lift → full section → (lift) → ending within 2–3 min; no two consecutive
   8-bar phrases identical. Check: a self-similarity matrix of 8-bar chunks.
3. **Mastering:** integrated loudness about −14 LUFS (streaming norm), true peak ≤ −1 dBTP,
   low end present (60–250 Hz within ~3 dB of a commercial reference). Check: `ffmpeg -af
   ebur128` and the band-energy script round 4 used.
4. **Steadiness:** tempo drift < 1 BPM over the track (so the beatmap holds). Check: beat-track
   it at the desk.
5. **The test that decides:** blind A/B against his own Suno track on the phone speaker and on
   earphones. "Suno level" = Chiu cannot reliably tell which is which, or prefers ours.

---

## Part C — the routes, licence first

"Open source" is not "safe to ship". For music the questions are: may the **weights** be used
commercially; was the **training data** licensed (if not, outputs may echo someone's record and
the model may be pulled); who **owns the output**; and can a Kamome user's shared film be
**claimed**. Hugging Face, arXiv, suno.com and stability.ai were unreachable from this session
(proxy), so the licence texts below were read on GitHub where possible and otherwise through
search results — each row says which.

### C1. Open-weight models

| model | weights licence | commercial in an app | training data | output owner | hardware | length, quality | steering |
|---|---|---|---|---|---|---|---|
| **ACE-Step 1.5** (StepFun/ACE Studio, 2026) | **MIT** — VERIFIED in the GitHub README (`ace-step/ACE-Step-1.5`); the README names no separate weights licence. Search results claim the XL variant's weights may carry a StepFun licence — UNKNOWN. *Settle:* read the `LICENSE` and model card on Hugging Face. | yes under MIT (INFERRED) | the model card says "licensed tracks, royalty-free and public-domain music, and synthetic MIDI-to-audio" — no licensors named, no audit (INFERRED from search; card unread here) | not stated; MIT claims nothing in outputs (INFERRED) | < 4 GB VRAM for the 2B model; CUDA, MPS, MLX (Apple Silicon), CPU supported; XL ≥ 12 GB (VERIFIED, README) | 10 s – 10 min; "under 10 s per song on an RTX 3090"; widely compared to Suno v4–4.5 (INFERRED) | **BPM, key, time signature, duration**, 1000+ style tags, lyrics or instrumental, repaint, cover, **stem separation**, LoRA from ~8 songs (VERIFIED, README) |
| **Stable Audio 3 Small / Medium** (Stability, May 2026) | Stability AI Community License — free commercial use under US$1 M annual revenue, registration required, Enterprise above (INFERRED from search; licence page unread) | yes while Kamome is under US$1 M | **licensed AudioSparx production library (806,284 files) + Creative Commons Freesound** per the Stable Audio 3 paper (INFERRED from search) — the most defensible provenance of any model here | the user, per Stability's terms (INFERRED) | Small (433 M) runs on CPU; Medium (1.4 B) needs CUDA (INFERRED) | Small up to 120 s, Medium up to 380 s; quality vs Suno UNKNOWN | text prompt incl. BPM in the prompt; no key/section control (INFERRED) |
| **Stable Audio Open Small** (2025) | same Community License (INFERRED) | same | Freesound + Free Music Archive CC audio (INFERRED, from memory of the 2025 card) | the user | Arm phone CPU, ~11 s in < 8 s | **11 s max** — loops and stingers only | text |
| **Magenta RealTime 2** (Google, 2026) | code Apache-2.0 (VERIFIED, GitHub); **weights CC-BY 4.0** with usage terms: no infringing outputs, "Google claims no rights in outputs" (INFERRED from search of the model card) | yes, with attribution (INFERRED) | stock/production music (v1 said ~190 k hours of mostly instrumental stock music — INFERRED from memory, *settle:* model card) | the user (Google claims none) | real-time on Apple Silicon (small 230 M on any M-series; base 2.4 B on Pro/Max); NVIDIA offline (VERIFIED, GitHub README) | streaming, any length; quality is "jam session", not a finished record (INFERRED) | text/audio style prompts that can change live; no tempo control in the README (VERIFIED) |
| **DiffRhythm** (ASLP-lab) | code and DiT weights **Apache-2.0** (VERIFIED, GitHub); its VAE was earlier described as fine-tuned from Stable Audio Open under Stability's licence — UNKNOWN whether still so | probably (INFERRED) | not published ("coming soon") | not stated | ≥ 8 GB VRAM | up to 4 m 45 s, song-style with vocals | style text or reference audio, lyrics, instrumental |
| **YuE / YuE2** (M-A-P) | code Apache-2.0; **YuE2 weights CC-BY-NC 4.0 "with additional creator permission"**: individuals may monetise outputs, **companies must ask for a commercial licence** (VERIFIED, GitHub README) | **no, without a negotiated licence** | not stated | individuals keep outputs | 24 GB VRAM | full songs, vocal-first | lyrics + style; ABC score input |
| **MusicGen / AudioCraft** (Meta) | code MIT; **weights CC-BY-NC 4.0** (INFERRED from multiple forks quoting the README — the brief's guess holds) | **no** | Meta-licensed 20 k h (ShutterStock, Pond5) (INFERRED, memory) | unresolved | GPU | 30 s typical | text, melody |

**Ruled out for shipping:** MusicGen (non-commercial weights) and YuE2 (company use needs a
licence). **Candidates:** ACE-Step 1.5, Stable Audio 3, Magenta RealTime 2, DiffRhythm.

### C2. Paid generators

| service | what a paid plan grants today | provenance | cost of a 15-track library | label |
|---|---|---|---|---|
| **Suno** | Pro US$10/mo, Premier US$30/mo. Commercial use only for songs made **while subscribed**; free-tier songs never gain commercial rights. Since **2026-09-03** commercial rights are tied to downloads: **Pro 20/month, Premier 60/month**. Terms say no copyright is warranted to vest in outputs. Warner settled (Nov 2025) and Suno is to replace its models with licensed ones in 2026; **Universal and Sony suits still active** in mid-2026. | contested, in litigation | **one month of Pro, US$10** (20 downloads ≥ 15 tracks) | INFERRED — from secondary sources and pricing-page captures; suno.com unreachable here. *Settle:* Chiu reads suno.com/terms for (a) the download cap, (b) any bar on embedding outputs in software or redistributing them inside a product. **Embedding in an app is UNKNOWN.** |
| **Udio** | downloads **off since 2025-10-29** under the Universal settlement; the licensed "walled garden" streams only | settled with Universal | **not usable** — no export | INFERRED (secondary sources) |
| **Google Lyria 3 (Gemini API / Vertex)** | ~US$0.04 per 30 s clip, ~US$0.08 per full song (Lyria 3 Pro, up to ~3 min); commercial use allowed under Google's terms (INFERRED); SynthID watermark; indemnity UNKNOWN | Google-licensed data (INFERRED) | **≈ US$1–5** including retries | INFERRED. *Settle:* read the Gemini API additional terms for generated-content ownership and app embedding. |
| **ElevenLabs Eleven Music** | commercial rights from a paid tier; training licensed from **Merlin and Kobalt** opt-ins; self-serve plans reported to carve out some uses (film/TV/games), full rights at Enterprise | **licensed** | US$6–22 for a month | INFERRED. *Settle:* the music terms page for in-app redistribution. |

**Note on Chiu's own Suno track:** if it was made on the free plan it can never be shipped, even
after upgrading (INFERRED from the reported terms). It stays a reference.

### C3. Can Kamome own AI-generated music, and the Content ID risk

- **Ownership — INFERRED:** in the US a purely machine-generated work has no copyright. The
  Supreme Court declined *Thaler v. Perlmutter* on 2026-03-02, leaving the human-author rule in
  place, and the Copyright Office's position is that only human selection, arrangement or edits
  are protected. Taiwan's copyright law likewise protects only human creative expression
  (INFERRED, not researched here). **Consequence:** Kamome can *use* the tracks but likely cannot
  stop anyone copying them; human cutting, arranging and mixing by Chiu may give thin protection
  to those parts only. For a bundled film soundtrack that is acceptable — Kamome needs the right
  to use, not exclusivity.
- **Content ID — INFERRED:** the risk is not Kamome's own tracks but *someone else* registering
  a near-identical output (same model, similar prompt) or a track the model echoed, so a user's
  shared film gets claimed. Rules: (1) **Kamome never registers its tracks with Content ID** —
  that would claim its own users' films; (2) generate with fixed seeds, keep the prompts and
  seeds in the repo as provenance; (3) prefer a model with licensed training data (lower echo
  risk); (4) run each finished track through a song-identification check (e.g. Shazam, ACRCloud
  free tier) before shipping. No source measured how often AI tracks are falsely claimed
  (UNKNOWN). *Settle:* upload one finished test film privately to YouTube and see if a claim
  appears.

### C4. Other routes

| route | licence | cost | verdict |
|---|---|---|---|
| stock libraries (Epidemic, Artlist, Musicbed) | standard licences cover finished videos, **not** embedding in a software binary that redistributes to every install; app tiers are custom (INFERRED from vendor blogs) | custom quote | possible but slow and recurring |
| app-licence libraries (e.g. vendors selling an "extended / in-app" tier) | buyout with app embedding stated | ~US$50–300 per track (INFERRED) | viable for 10–15 tracks; quality fixed, no BPM choice |
| commissioning a composer (work-for-hire, full buyout) | Kamome owns copyright outright — the only route that gives real ownership | ~US$100–500 per track on a freelance marketplace (INFERRED) | the cleanest licence; slowest; quality depends on the hire |
| keep composing by rules | CC0 | free | **stopped** by Chiu's verdict |

---

## Part D — recommendation

### D1. The path

**Generate a fixed, curated library at the desk with ACE-Step 1.5; ship only the chosen, mastered
tracks as AAC with a measured beatmap; the app only cuts, dips and mixes them.** No model ever
runs on the phone; no trip data goes anywhere.

Why ACE-Step 1.5 over the others:

1. **The licence is the plainest of the strong models** — MIT (VERIFIED for the repository),
   no revenue threshold, no attribution, no registration. Stable Audio 3 is close but has a
   revocable licence and a US$1 M ceiling; Magenta needs attribution.
2. **It is the only open model with the controls the film needs:** a set BPM and key (so the
   beatmap is known before generating), set duration, instrumental, repaint a weak section,
   and stem separation (so a `stop` can drop the drums instead of only filtering).
3. **It is the closest to Suno in quality** of the open models (INFERRED from reviews — the
   experiment below settles it for Chiu's ears).
4. **It runs on an ordinary machine:** < 4 GB VRAM, MLX on Apple Silicon. Generating 15 kept
   tracks out of ~100 tries is an afternoon.

**Its weak point is provenance:** the training data is described as licensed but no licensor is
named. That is why the experiment runs **Stable Audio 3 beside it**: Stability's AudioSparx
training data is the most defensible here. If Chiu hears them as close, **take Stable Audio 3**
— provenance beats a small quality edge for something bundled in a commercial app. If ACE-Step
is clearly better, take it and add the song-identification check (C3 rule 4) to every track.

**Against the obvious alternative — pay Suno for one month (US$10):** cheaper than anything, best
quality, and what Chiu already likes. It is not recommended as the source of bundled music
because (a) whether a Suno song may be embedded and redistributed inside an app is UNKNOWN, (b)
Universal and Sony are still suing, and the models are being replaced, and (c) rights now ride
on a download cap. If Chiu reads Suno's terms and they plainly allow in-app use, it becomes the
fastest route and this recommendation should be revisited — that reading costs ten minutes.

### D2. The first experiment Chiu can listen to — US$0, ~1 hour

This session could not run it: the container has no GPU and Hugging Face is blocked by the
proxy (VERIFIED: `nvidia-smi` absent, 4 CPUs, 15 GB RAM; `huggingface.co` refused). So it is
Chiu's to run, or a later session's with Hugging Face allowed.

1. Open the ACE-Step 1.5 demo (the official Space linked from `ace-step/ACE-Step-1.5` on GitHub;
   the README warns that look-alike domains are fake) and a Stable Audio 3 demo.
2. Generate the same three instrumental briefs on each, 2 tries per brief, 150 s:
   - `tropical`: "warm acoustic tropical pop, instrumental, 100 BPM, D major, nylon and steel
     guitars, light congas and shaker, bass guitar, bright piano, sunny road trip, uplifting,
     cinematic build to a big chorus, polished modern mix"
   - `cinematic`: "cinematic post-rock, instrumental, 90 BPM, piano and swelling strings,
     tremolo electric guitars, live drums entering at the build, vast Nordic landscape, grand and
     hopeful, polished mix"
   - `pop`: "feel-good indie pop road trip anthem, instrumental, 120 BPM, E major, strummed
     acoustic guitar, driving live drums, bass guitar, claps, synth pad, big singalong energy
     without vocals, polished modern mix"
3. Listen on the phone speaker and earphones, blind if someone can shuffle: each clip beside a
   round 4 loop and beside his Suno track. Score 1–10 against "壯闊有趣的公路旅行".
4. Write down: which model, which brief, the score. That decides the model (D1) and settles the
   A3 inference.

**Demo output is for listening only — never ship it.** Shipped tracks are generated locally with
pinned weights and recorded seeds, so their provenance is reproducible.

### D3. If the experiment passes, what follows (each step Chiu confirms first)

| step | cost | dependency |
|---|---|---|
| install ACE-Step 1.5 (or Stable Audio 3) on a Mac, outside the repo, weights pinned by hash | free; ~10 GB disk | desk-only dependency — **needs Chiu's confirmation** |
| generate ~6 tries × 5 moods × 3 tracks, keep 15; master to −14 LUFS | an afternoon | — |
| beat-track each kept track once; write a beatmap (BPM, offset, sections) | a desk tool, reusing `plan()` | — |
| identification check on every track; record prompt, seed, model hash in the repo (never the audio) | free | — |
| wire into the export: cut to length, snap turns, dip at stops, mux after `RecapVideoEncoder` | an implementation session | product change — **Chiu decides music ships, and in which tier** |

### D4. Open for Chiu

1. **Which source** — run D2, then choose (D1 names the default).
2. **Suno's terms** — ten minutes reading suno.com/terms for in-app use would change D1 if they
   allow it.
3. **Whether the film gets music at all, and in which tier** (ADR 2026-07-20: free silent,
   premium in-app). Not reopened here.
4. **The default mood** for countries outside the eight, and for two-country trips.
5. **Bundle or download** the 30–45 MB of tracks.
6. **Whether events move onto the beat** (≤ half a beat), which touches measured durations such
   as `crossing_beat_s` (carried over from `handoff-music.md`).

## Sources

Read directly (GitHub): `ace-step/ACE-Step-1.5` README; `magenta/magenta-realtime` README;
`multimodal-art-projection/YuE` README; `ASLP-lab/DiffRhythm` README. Through search results
only (primary pages unreachable from this session): Stable Audio 3 paper (arXiv 2605.17991) and
Stability's licence page; the Magenta RealTime 2 model card; Suno pricing captures
(usagepricing.com, 2026-09-07 and 2026-10-20) and reporting on the Warner settlement (Music
Business Worldwide, Rolling Stone); Udio's download shutoff (2025-10-29); Lyria 3 pricing
(Gemini API trackers); Eleven Music's Merlin/Kobalt deals (Music Business Worldwide); *Thaler v.
Perlmutter* cert denial (Holland & Knight, Baker Botts, 2026-03); YouTube Replace Song with
Lyria (Music Business Worldwide, 2026-05).
