# The Epic Saga of Apollo iOS: A Tale of GraphQL, Race Conditions, and Redemption

**Last updated: January 2026**

*A dramatic retelling of the commit history that shaped an SDK*

---

## Prologue: In the Beginning, There Was v0.23.0

Once upon a time, in the mystical land of iOS development, a brave group of engineers at Apollo set out on a noble quest: to bring the glory of GraphQL to the Apple ecosystem. Little did they know, this journey would span *over 70 releases*, countless ROADMAP.md updates, and an eternal war against race conditions.

The early days (v0.23.x - v0.34.x) were wild and uncharted. Like settlers building a new world, the team laid the foundations for what would become the industry-leading GraphQL client. Changelogs from this era read like ancient scrolls—mysterious artifacts from before the Great 1.0 Migration.

---

## Act I: The Long March to 1.0 (2023)

After approximately *one billion* beta releases (okay, technically v1.0.4 through v1.0.7 and then v1.1.0-beta.1), Apollo iOS finally reached the promised land of **version 1.0**.

This was the era of:
- Code generation that actually worked
- Normalized caching that normalized things (most of the time)
- A general sense of optimism about the future

The team celebrated. The users celebrated. Everything was perfect.

*Narrator: Everything was not perfect.*

---

## Act II: The Race Condition Wars (2024-2025)

If there's one thing the Apollo iOS commit history teaches us, it's that **race conditions are the final boss of mobile development**. Observe the carnage:

| Date | Commit | What Went Wrong |
|------|--------|-----------------|
| Jan 2025 | `b6c8087` | "fix: WebSocket data race crash" - *WebSockets decided to party on multiple threads simultaneously* |
| Feb 2025 | `720622d` | "Fix data race for subscribers property" - *Subscribers were subscribing to chaos* |
| Apr 2025 | `69f09c7` | "Fix potential data race" - *The word "potential" doing heavy lifting here* |
| Sep 2025 | `9575a6e` | "Portola network error cleanup + race condition fixes" - *The race never ends* |
| Sep 2025 | `b3d4e76` | "Do not crash if readStack is empty" - *Revolutionary advice, honestly* |

One can only imagine the internal Slack conversations:

> **Engineer 1:** "Hey, users are reporting random crashes in production."
>
> **Engineer 2:** "Let me guess... WebSockets?"
>
> **Engineer 1:** "WebSockets."
>
> **Engineering Lead:** *sighs in @Atomic*

---

## Act III: The Great SQLite.swift Divorce (April 2025)

For years, Apollo iOS maintained a dependency on `SQLite.swift`. It was a good relationship—until it wasn't.

On April 29, 2025, in commit `52c5a41`, the team delivered the fateful message:

> **"feature: Remove SQLite.swift"**

In one swift (pun intended) motion, Apollo iOS replaced the third-party dependency with direct interaction with the SQLite C API. It was like watching someone trade in their comfortable sedan for building their own car from scratch.

Was it more work? Absolutely.
Was it worth it? The reduced dependency chain says yes.
Did anyone cry? We'll never know.

By June 2025, the team followed up with custom `SQLiteDatabase` implementations (`b0007f9`), proving that independence is just the beginning of a beautiful new chapter.

---

## Act IV: The @defer Directive Chronicles (2024)

The GraphQL community had been asking for `@defer` support for approximately *forever*. Apollo iOS finally delivered it as an experimental feature in v1.14.0.

`@defer` allows queries to receive data for specific fields asynchronously—perfect for when your backend developer designed a schema where one field takes 47 seconds to resolve while everything else is instant.

The implementation required:
- Code generation changes
- Partial incremental execution
- Partial and incremental caching
- Local cache mutations
- An unhealthy amount of coffee

Current status: Still waiting for Selection Set Initializers. Some say we'll get them when Half-Life 3 releases.

---

## Act V: The ROADMAP.md Update Saga (Ongoing)

No story of Apollo iOS is complete without acknowledging the true hero of this repository: **ROADMAP.md**.

Let's count the ROADMAP updates in the commit history:

```
2024-12-10  Update ROADMAP.md
2025-01-07  Update ROADMAP.md
2025-01-21  Update ROADMAP.md
2025-02-11  Update ROADMAP.md
2025-02-18  Update ROADMAP.md
2025-03-04  Update ROADMAP.md
2025-03-18  Update ROADMAP.md
2025-04-01  Update ROADMAP.md
2025-04-16  Update ROADMAP.md
2025-04-29  Update ROADMAP.md
2025-05-13  Update ROADMAP.md
2025-05-27  Update ROADMAP.md
2025-06-24  Update ROADMAP.md
2025-07-22  Update ROADMAP.md
2025-08-05  Update ROADMAP.md
2025-09-03  Update ROADMAP
```

That's 16 roadmap updates in less than a year. At this point, "Update ROADMAP.md" should have its own keyboard shortcut.

Legend has it that on quiet nights, if you listen closely, you can hear a PM whispering: *"We should update the roadmap..."*

---

## Act VI: Xcode's Revenge (March 2025)

Just when things were going smoothly, Xcode 16.3 showed up uninvited and broke the CLI installation (`4294a65`).

The commit message reads simply: **"fix: Xcode 16.3 CLI installation"**

But we all know the real story is something like:

> "Dear Apple,
>
> Thank you for changing the execution directory for plugins without warning.
> We definitely weren't using that in production. Love, everyone."

Classic Apple. Classic iOS development. Classic pain.

---

## Act VII: The March to 2.0 (Present Day)

As of this writing, Apollo iOS is charging toward version 2.0, which promises:

- **Swift 6 compatibility** (because Swift versions are like Pokémon—gotta catch 'em all)
- **Improved Concurrency Model** (finally making sense of async/await in networking)
- **Better caching APIs** (the caching rework RFC has been opened, bets are being placed)

The beta is live. The GraphQLQueryWatcher is pending. ApolloWebSocket is scheduled for 2.1.

The roadmap remains ever-changing, like the tides of the ocean or Apple's design guidelines.

---

## Hall of Fame: Notable Version Highlights

| Version | Release Date | Claim to Fame |
|---------|--------------|---------------|
| v1.0.4 | The Beginning | First stable release (allegedly) |
| v1.12.1 | Mid-2024 | "Rebuilt the CLI binary" - when your release artifact has the wrong version |
| v1.12.2 | Mid-2024 | "Rebuilt the CLI binary with the correct version number" - second time's the charm! |
| v1.14.0 | Late 2024 | @defer finally arrives, angels sing |
| v1.15.0 | 2025 | Fragment field merging can be disabled (rejoice, you five people who needed this) |
| v1.16.1 | Jan 2025 | WebSocket race condition fix #47 (estimated) |
| v1.21.0 | Apr 2025 | SQLite.swift dependency removed, independence achieved |
| v1.23.0 | Jun 2025 | The most recent stable release, featuring non-optional mock fields |

---

## Epilogue: The Moral of the Story

What have we learned from this journey through Apollo iOS's git history?

1. **Race conditions never truly die.** They just hibernate until your most important demo.

2. **Dependencies are a double-edged sword.** Sometimes you love SQLite.swift. Sometimes you rewrite the entire SQLite layer yourself.

3. **Roadmaps exist to be updated.** And then updated again. And once more for good measure.

4. **"Do not crash if X is empty"** is always a valid commit message.

5. **The community is everything.** From `@tahirmt` fixing data races to `@x-sheep` adding typePolicy directives, Apollo iOS is built by the people who use it.

---

## Credits

**Maintained by the brave souls at Apollo GraphQL:**
- Anthony Miller (@anthonymdev)
- Calvin Cestari (@calvincestari)
- Jeff Auriemma (@bignimbus)
- Zach FettersMoore (@bobafetters)

**And countless contributors** who filed issues, submitted PRs, and kept the dream of type-safe GraphQL on iOS alive.

---

*"In GraphQL we trust. In race conditions, we fix."*

— Ancient Apollo iOS Proverb

---

**P.S.** If you're reading this and you just hit a WebSocket crash, check if there's a new patch release. There probably is.

**P.P.S.** Don't forget to update the ROADMAP.md.
