<div align="center">

<img src="OpenWriting/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="132" alt="OpenWriting app icon" />

# OpenWriting

### A native macOS workspace for long-form fiction

**Bring outline, memory, foreshadowing, pacing, review, and AI-assisted drafting into one professional story system.**

<p>
  <a href="README.zh-CN.md">简体中文</a> ·
  <strong>English</strong>
</p>

<p>
  <a href="https://www.apple.com/macos/"><img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111827?style=for-the-badge&logo=apple&logoColor=white&labelColor=000000"></a>
  <a href="https://swift.org/"><img alt="Swift" src="https://img.shields.io/badge/Swift-5.9-F05138?style=for-the-badge&logo=swift&logoColor=white&labelColor=1f2937"></a>
  <a href="https://developer.apple.com/xcode/swiftui/"><img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-Native%20Experience-0A84FF?style=for-the-badge&logo=swift&logoColor=white&labelColor=1f2937"></a>
  <img alt="License GPL v3" src="https://img.shields.io/badge/License-GPL%20v3-10B981?style=for-the-badge&labelColor=1f2937">
</p>

<p>
  <a href="#product-vision">Product Vision</a> ·
  <a href="#core-systems">Core Systems</a> ·
  <a href="#architecture">Architecture</a> ·
  <a href="#comparison">Comparison</a> ·
  <a href="#quick-start">Quick Start</a>
</p>

</div>

---

## Product Vision

OpenWriting is built for a very specific and very hard writing scenario: an author is working on a long-form novel, the chapter count keeps growing, character relationships become more complex, foreshadowing spans dozens of chapters, and the AI cannot forget a rule established in chapter 8 when drafting chapter 80.

Most AI writing tools treat long-form writing as a context stuffing problem. OpenWriting takes a more systematic position: long-form fiction is not just a prompt problem. It is a product and engineering problem that needs structured memory, prewrite constraints, postwrite review, pacing control, reference retrieval, and project sync working together.

| Writing pressure | Typical tool behavior | OpenWriting approach |
| --- | --- | --- |
| AI forgets earlier canon | Keep appending more context | 7-bucket structured memory with lifecycle-aware persistence |
| Chapters drift away from the outline | Ask the author to manually reread notes | Chapter tree, story contracts, and Strand Weave constraints |
| Characters act out of character | Hope the author catches it after generation | Prewrite validation, nine-dimension review, and blocking issue classification |
| Foreshadowing gets abandoned | Track it in notes or in the author's head | Structured openLoop, readerPromise, and PlotThread tracking |
| References become too large to use | Manually copy the relevant material | BM25 retrieval plus ContextRanker before context injection |

> OpenWriting is not trying to write the entire book for the author. It gives the author a professional workspace that can preserve story continuity over time.

---

## Product Surface

| Surface | Purpose | Design intent |
| --- | --- | --- |
| Home workspace | Project overview, navigation, account state, materials, and writing spaces | Return to the active project fast, without management overhead |
| Writing desk | Draft editing, chapter saving, AI continuation, and context refresh | Writing stays primary; tools are close but not intrusive |
| Outline workspace / 章节树工作区 | Outline hierarchy, chapter structure, global memory, and long-form support panels | Make long-form structure visible, maintainable, and safe to write back |
| Quality review dashboard | Dimension scores, blocking issues, and non-blocking suggestions | Turn "something feels wrong" into actionable review items |
| Genre template library | Webnovel genres such as fantasy, urban, romance, suspense, and composites | Templates act as writing parameters, not simple labels |
| Settings and sync | Appearance, model connection, Apple ID, and CloudKit | Native macOS account isolation and private project sync |

---

## Core Systems

### 1. 7-Bucket Structured Memory

OpenWriting splits long-form memory into seven categories, each with its own priority, deduplication strategy, and lifecycle. The AI no longer depends on one giant history dump. It receives the facts that matter for the current chapter.

```text
worldRule        Priority 0   Physics of the setting: rules, limits, factions
characterState   Priority 1   Character state: power, wounds, identity, emotion
relationship     Priority 2   Relationship changes: mentor, rival, ally, romance
storyFact        Priority 3   Plot facts: events, discoveries, decisions
openLoop         Priority 4   Unresolved foreshadowing: mysteries and promises
readerPromise    Priority 5   Reader-facing expectations: reveals and payoffs
timeline         Priority 6   Timeline: seasons, jumps, historical events
```

Every memory item has a lifecycle: `active`, `outdated`, `contradicted`, and `tentative`. New facts do not simply overwrite old ones. The historical trail remains available for conflict detection and later review.

### 2. The Three Anti-Hallucination Laws

| Law | Product meaning | Engineering anchor |
| --- | --- | --- |
| Outline is law | AI should not improvise without an outline or chapter goal | `PrewriteValidator.checkOutline()` |
| Setting is physics | World rules take priority over fluent generation | `PrewriteValidator.checkSettings()` |
| Inventions must be identified | New characters, places, and rules must enter the project system | `PrewriteValidator.checkEntityTracking()` |

These laws are not just prompt copy. They act as prewrite gates before body text generation begins.

### 3. Nine-Dimension Quality Review

After drafting, OpenWriting reviews a chapter with a 100-point penalty model. Critical issues become blocking issues.

| Dimension | Review focus | Why it matters |
| --- | --- | --- |
| High-point density | Payoff density and quality | Reader momentum |
| Canon consistency | Power scale, location, timeline, and rule conflicts | Prevents setting collapse |
| Character OOC | Whether behavior breaks characterization | Keeps characters believable |
| Pacing ratio | Main plot, relationship line, and world expansion balance | Prevents reader fatigue |
| Narrative continuity | Scene transitions and causal flow | Preserves immersion |
| Read-on force | Hooks, expectation management, ending energy | Drives the next chapter |
| AI texture check | Template phrasing and vague generated prose | Reduces generated feel |

```text
critical  -35   Blocking issue
high      -15   Severe issue
medium     -6   Medium issue
low        -2   Minor issue

score = max(0, 100 - totalPenalty)
pass  = no critical issues && score >= 60
```

### 4. Strand Weave Pacing

OpenWriting tracks chapter rhythm through three narrative strands, so a long novel does not collapse into only main-plot advancement or lose its relationship and worldbuilding lines for too long.

| Strand | Target ratio | Represents |
| --- | ---: | --- |
| Quest | 60% | Main objective, conflict progression, stage wins |
| Fire | 20% | Relationship heat, emotional pull, character bonds |
| Constellation | 20% | Worldbuilding, factions, history, rules |

Example red lines:

- Quest runs for more than 5 consecutive chapters: the main plot may be overloaded.
- Fire is absent for more than 10 chapters: relationship energy may be cooling.
- Constellation is absent for more than 15 chapters: the world may feel thin.
- After at least 10 tracked chapters, any strand drifting more than 50% from target triggers a pacing warning.

### 5. Genre Templates and Anti-Patterns

OpenWriting includes 37 genre templates and supports up to two merged genres. Each template is a structured writing parameter set, not a simple category label.

```text
Genre Template
├─ HookStrategy          crisis / mystery / desire / emotion / choice
├─ CoolPointPattern      reveal / underdog reversal / identity drop / payoff
├─ Rhythm Parameters     stagnationThreshold / setupTolerance
├─ Writing Directives    positive guidance
├─ Anti Patterns         anti-AI writing patterns
└─ CBN Nodes             Chapter Beginning / Progression / Ending
```

### 6. 3-Pass AI Writing Pipeline

OpenWriting does not treat AI continuation as a single generation call. It breaks drafting into more controllable stages.

```text
Plan       temperature 0.42   Generate beats first, before prose
Write      temperature 0.82   Generate candidate prose with creative range
Revise     temperature 0.34   Refine while reducing drift
Supplement temperature 0.72   Extend when the draft is too short
```

Context injection is ranked by relevance and includes the current draft, structured memory, global memory snapshots, chapter-tree focus, Strand state, genre constraints, anti-patterns, and retrieved reference material.

---

## Architecture

OpenWriting is a native macOS app built with SwiftUI and AppKit. SwiftUI carries the main interface, while AppKit coordinates window lifecycle, toolbar behavior, and macOS-level experience details.

```text
OpenWritingApp
  └─ AppWindowCoordinator
      └─ AppRuntime
          ├─ AppState
          │   ├─ ProjectFileStore
          │   ├─ ICloudProjectStore
          │   ├─ AIWritingService
          │   └─ ModelConnectionConfigurationStore
          ├─ AppRootView
          │   ├─ HomeDashboardView
          │   ├─ WritingDeskView
          │   ├─ OutlineWorkspacePanel
          │   └─ QualityReviewDashboardView
          └─ Domain Layer
              ├─ NovelProject / ChapterDraft / ReferenceDocument
              ├─ WritingMemoryBuckets
              ├─ StrandWeaveTracker
              ├─ ChapterQualityReviewer
              ├─ ContextRanker
              └─ LongformStorySystem
```

### Technical Highlights

| Module | File | Highlight |
| --- | --- | --- |
| AI service and BM25 | `OpenWriting/AIWritingService.swift` | Custom Okapi BM25 with CJK unigram / bigram / trigram support |
| Context ranking | `OpenWriting/ContextRanker.swift` | Freshness, entity overlap, and signal-strength scoring |
| Memory buckets | `OpenWriting/WritingMemoryBuckets.swift` | Bucket-specific dedup keys and lifecycle-aware updates |
| Quality review | `OpenWriting/ChapterQualityReviewer.swift` | Severity penalty model and blocking issue classification |
| Story contracts | `OpenWriting/LongformStorySystem.swift` | master / volume / chapter / review / prewrite / writingBrief |
| Memory extraction | `OpenWriting/MemoryExtractionService.swift` | One LLM call extracts seven types of structured memory |
| Genre templates | `OpenWriting/GenreTemplateEngine.swift` | 37 genre templates and composite genre parsing |
| Project export | `OpenWriting/ProjectExportService.swift` | Backup JSON, Markdown, DOCX, and EPUB book files |
| CloudKit sync | `OpenWriting/AccountSync.swift` | Apple ID state detection and private database snapshots |

---

## Comparison

### Compared With General AI Writing Tools

| Capability | OpenWriting | Notion AI | Scrivener | Sudowrite | NovelCrafter |
| --- | :---: | :---: | :---: | :---: | :---: |
| Native macOS workspace | Yes | Web | Desktop | Web | Web |
| Structured long-form memory | 7 buckets + lifecycle | No | No | Partial | Partial |
| Prewrite anti-hallucination gates | Yes | No | No | No | Partial |
| Nine-dimension quality review | Yes | No | No | Partial | Partial |
| Strand pacing monitor | Yes | No | No | No | No |
| Foreshadowing lifecycle | Yes | No | Manual | No | Partial |
| Parameterized genre templates | 37 templates | No | No | Limited | Partial |
| BM25 reference retrieval | Built in | No | No | No | Partial |
| Private iCloud sync | CloudKit | No | Manual | No | No |

### Technical Depth

| Area | OpenWriting | Common implementation |
| --- | --- | --- |
| Memory management | Categories, dedup, lifecycle, compression, conflict detection | Appended text snippets |
| Context selection | BM25 + ContextRanker + project-state signals | Recent history text |
| Writing flow | Plan / Write / Revise / Supplement | One-shot generation |
| Quality model | Dimension review + severity penalty | Vague suggestions |
| Long-form constraints | Story contracts + three laws + blocking gates | Prompt-only constraints |
| Native experience | SwiftUI, AppKit, CloudKit, Apple ID | Web UI or generic editor |

---

## Quick Start

### Requirements

- macOS 14.0+
- Latest stable Xcode
- Apple Developer Team for Sign in with Apple and iCloud/CloudKit capabilities

### Run Locally

```zsh
git clone https://github.com/dashitongzhi/OpenWriting.git
cd OpenWriting
open OpenWriting.xcodeproj
```

In Xcode:

1. Select the `OpenWriting` target.
2. In `Signing & Capabilities`, confirm `Team`, `Sign In with Apple`, `iCloud`, and `CloudKit`.
3. Select `My Mac`, then run.

### Command Line Build

```zsh
./scripts/build-debug.sh
```

Common scripts:

| Command | Purpose |
| --- | --- |
| `./scripts/build-debug.sh` | Debug build |
| `./scripts/run-debug.sh` | Run the Debug app |
| `./scripts/git-preflight.sh` | Local Git ref/default-branch preflight |
| `./scripts/run-smoke-checks.sh` | Smoke checks |
| `./scripts/run-longform-quality-checks.sh` | Long-form quality checks |
| `./scripts/run-longform-evals.sh` | Long-form pipeline evaluations |
| `./scripts/run-all-checks.sh` | Aggregated checks |

### Backup and Sync Safety

- Project backups are exported as a directory containing `manifest.json`, `project.json`, Markdown, DOCX, and EPUB. Import validates the manifest and rejects unsafe paths, duplicate identifiers, and malformed payloads before adding a project.
- iCloud is an account-scoped CloudKit snapshot. A newer remote snapshot, including an empty snapshot after deletions, is authoritative for that account; switching or signing out cancels the previous account's pending sync work.
- When local project indexes are incomplete or corrupted, automatic persistence and iCloud sync stop instead of treating missing records as user deletions. Use the in-app storage recovery/diagnostic export flow before continuing.
- Custom model endpoints require HTTPS. `http://localhost` / `127.0.0.1` / `::1` is retained only for local development proxies, so API keys are not sent to remote cleartext endpoints.

---

## Repository Map

```text
OpenWriting/
├─ OpenWriting.xcodeproj
├─ OpenWriting/
│  ├─ OpenWritingApp.swift
│  ├─ AppWindowCoordinator.swift
│  ├─ AppState.swift
│  ├─ AppRootView.swift
│  ├─ HomeDashboardView.swift
│  ├─ WritingDeskView.swift
│  ├─ OutlineWorkspacePanel.swift
│  ├─ QualityReviewDashboardView.swift
│  ├─ AIWritingService.swift
│  ├─ AIWritingService+Enhanced.swift
│  ├─ AIWritingService+Prompts.swift
│  ├─ DomainModels.swift
│  ├─ WritingMemoryBuckets.swift
│  ├─ StrandWeaveTracker.swift
│  ├─ ChapterQualityReviewer.swift
│  ├─ ContextRanker.swift
│  ├─ LongformStorySystem.swift
│  ├─ MemoryExtractionService.swift
│  ├─ GenreTemplateEngine.swift
│  ├─ ProjectExportService.swift
│  └─ AccountSync.swift
├─ LongformEvals/
├─ Tests/
├─ scripts/
├─ INDEX.md
├─ README.md
└─ README.zh-CN.md
```

For a maintained source guide, see [`INDEX.md`](INDEX.md).

---

## Roadmap

| Phase | Status | Focus |
| --- | :---: | --- |
| Core Workspace | Done | Multi-form fiction projects, writing desk, chapter tree, references, iCloud sync |
| Structured Memory | Done | 7-bucket memory, lifecycle, dedup, conflict detection, compression |
| Anti-Hallucination | Done | Three laws, prewrite validation, nine-dimension review, blocking classification |
| Longform Intelligence | Done | Strand Weave, genre templates, anti-patterns, story contracts, ContextRanker |
| Evaluation | Active | Long-form pipeline evaluations, quality scripts, regression seeds |
| Publishing | Planned | Fuller EPUB / PDF / DOCX export and book production flow |
| Ecosystem | Planned | Character relationship graph, community templates, plugins, companion apps |

---

## Contributing

Issues and pull requests are welcome. The most valuable feedback usually comes from real long-form pressure:

- Where memory still breaks in the middle or late stages of a long project.
- Which review results are inaccurate or not actionable enough.
- Which genre templates lack key payoffs, hooks, or anti-patterns.
- Which native macOS workflows still feel awkward.

Before contributing, read:

- [`INDEX.md`](INDEX.md)
- [`Tests/README.md`](Tests/README.md)

---

## License

OpenWriting is released under GPL v3.

---

<div align="center">

**OpenWriting is built for writers who think in chapters, arcs, promises, and consequences.**

<sub>Made for long-form creators with SwiftUI, CloudKit, and a stubborn respect for story continuity.</sub>

</div>
