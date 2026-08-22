---
name: updating-my-zeron-build
description: Use when syncing this fork with the original zeronsh/comet project, rebuilding the Zeron macOS app from source, or installing a locally built Zeron.app over the one in /Applications.
---

# Updating my Zeron build

This is a personal fork of `zeronsh/comet` carrying local patches. This skill covers keeping it current with the original project, building the macOS app, and installing that build.

**Core principle:** the build is only as clean as the working tree it came from, and the install kills every agent session the running app hosts.

## Repo map

| Branch | Role | Sync method |
|---|---|---|
| `main` | Mirror of `upstream/main`. Never commit here. | `git reset --hard upstream/main` |
| `mine` | Personal integration branch. Build from this. | **merge** `upstream/main` in |
| feature branches | One per change, destined for an upstream PR | **rebase** onto `upstream/main` |

| Remote | Points at |
|---|---|
| `upstream` | `zeronsh/comet` (the original project) |
| `origin` | `tobi404/comet` (the fork) |

**Merge into `mine`, rebase feature branches.** `mine` accumulates several features and gets built from repeatedly; rebasing it rewrites history you already shipped to yourself and turns every sync into conflict archaeology. A feature branch is a clean stack destined for a PR, so rebase keeps it reviewable and force-push updates the PR.

## Phase 1: sync with the original project

**Decide about uncommitted work before anything else.** A merge can abort on, or entangle itself with, a dirty tree, and Phase 2 would build whatever is sitting there.

```bash
git status --short
```

Commit it, `git stash -u` it, or consciously accept it riding into the merge and the build. Say which you chose. The `-u` is not optional: untracked files are common here (new tests, Xcode state), and a plain `git stash` leaves them in the tree.

"Accept it riding" is only available when no dirty file also differs between `main` and `mine` - otherwise the `git checkout main` below refuses rather than clobber it, and the sync stops halfway. Check before choosing:

```bash
comm -12 <(git diff --name-only | sort) <(git diff --name-only main mine | sort)
```

Anything printed must be committed or stashed. It cannot ride.

**Then check `main` really is a mirror before resetting it.**

```bash
git fetch upstream
git log --oneline upstream/main..main    # MUST be empty
```

Anything listed is a commit that exists only on `main`, and `--hard` would orphan it to the reflog. Find out whether another branch carries it (`git branch --contains <sha>`) before continuing. If nothing does, `git branch rescue/main-<topic> main` first - a free safety net.

```bash
git checkout main && git reset --hard upstream/main
git checkout mine && git merge upstream/main
cargo test --workspace                                 # sync can break local patches
```

Conflicts land in the patches this fork carries. Resolve them in favour of upstream's structure, keeping the local behaviour.

A failing test on a dirty tree is ambiguous: the sync may have broken a local patch, or the uncommitted work may simply be unfinished. Check which files the failure touches before blaming the sync.

When a local patch has been merged upstream, its commits become ancestors and the merge quietly no-ops. Nothing to unwind.

Publishing is a separate decision. Nothing here pushes, so the fork on GitHub drifts from what is installed locally until you `git push origin mine`. Feature branches destined for a PR are pushed with `--force-with-lease` after a rebase.

`mine` tracks `upstream/main` so `git status` reports how far behind the original project you are, but its `pushRemote` is set to `origin`, so a bare `git push` lands on the fork rather than aiming at the original project's main. If `git config --get branch.mine.pushRemote` ever comes back empty, set it again before pushing anything.

## Phase 2: build

```bash
git status --short          # re-confirm the tree matches what you decided in Phase 1
scripts/package-macos.sh    # → target/package/Zeron.app (+ dmg, + tarball)
```

The script builds release, makes the iconset, and ad-hoc signs the bundle. Locally built bundles carry no `com.apple.quarantine`, so Gatekeeper does not prompt. The dmg is for redistribution; installing copies the `.app` directly.

Build before touching the installed app, so a failure leaves the working app alone.

## Phase 3: install

**STOP. Check whether you are running inside the app you are about to replace.**

```bash
pid=$$; for i in 1 2 3 4 5 6; do line=$(ps -o pid=,ppid=,comm= -p $pid) || break; echo "$line"; pid=$(echo "$line" | awk '{print $2}'); [ "$pid" = "1" ] && break; done
```

Zeron hosts coding-agent sessions. If `/Applications/Zeron.app` appears in that chain, **you are running inside it** and quitting it kills this session, mid-edit.

In that case do not run Phase 3. Hand the owner the commands and let them run it from a plain Terminal window.

Either way, report the blast radius before anyone quits - it is almost never one session:

```bash
app=$(ps -eo pid,comm | awk '/Zeron\.app\/Contents\/MacOS\/zeron/ {print $1; exit}')
ps -eo pid,ppid,ucomm | awk -v a="$app" '$2==a'
```

Each hosted session is a `node` child of the app process; `zsh` children are its terminals. List them and tell the owner the count, so quitting is a decision about all of them rather than a surprise.

**Use `ps`, not `pgrep`.** The app runs with a hardened runtime, so `pgrep` cannot read its argv or match it at all - `pgrep -f`, and even `pgrep -x zeron`, return nothing while `ps` lists it fine. A `pgrep`-based check reports zero children and makes quitting look free.

Name the backup for what it actually is. After the first local install, `/Applications/Zeron.app` is a previous **local** build, not the official release - check rather than assume:

```bash
codesign -dv /Applications/Zeron.app 2>&1 | grep -E "Signature|TeamIdentifier"
```

`Signature=adhoc` with no team identifier means a local build. A Developer ID signature means the official release. Either way a timestamped name never lies:

```bash
ditto /Applications/Zeron.app ~/Zeron-backup-$(date +%Y%m%d-%H%M).app   # rollback copy FIRST
osascript -e 'quit app "Zeron"'                                        # clean shutdown, not killall
rm -rf /Applications/Zeron.app
ditto target/package/Zeron.app /Applications/Zeron.app                 # ditto preserves the signature
open /Applications/Zeron.app
```

Rollback: quit, `rm -rf /Applications/Zeron.app`, `ditto ~/Zeron-backup-<stamp>.app /Applications/Zeron.app`. Once every backup is itself a local build, the only route back to the official release is a download from the project's releases page.

`~/.zeron` holds sessions, spaces, sign-in, and adapters. Replacing the bundle never touches it. There is no launchd service, so the bundle is the whole install.

## The auto-update trap

A local build reports the same version as the official release (`version` in the root `Cargo.toml`). Once upstream ships a higher version, the updater offers it, and **applying it overwrites the local build and silently drops every local patch.**

- **Decline the update.** Sync and rebuild instead - that is what Phases 1 and 2 are for.
- Signed in: the updater polls every 6 hours. `ZERON_AUTO_UPDATE` is off by default, so nothing applies itself unclicked.
- Local-only mode: the updater is never constructed (`edge_enabled` is false for `WorkspaceScope::Local`), so this cannot bite.

## Trying a build without installing

Run it against a throwaway profile, leaving the installed app and its sessions alone:

```bash
ZERON_DATA_DIR=~/.zeron-dev ZERON_IPC_PORT=27655 ./target/debug/zeron
```

The profile starts empty - no sign-in, no spaces, no chats - so add a folder as a space to test anything. `rm -rf ~/.zeron-dev` removes every trace. Both env vars are required: the engine's instance lock is per data dir, and the default port 27654 belongs to the installed app.

For an engine-only check with no window, `zeron headless` takes the same two variables.

## Common mistakes

| Mistake | What happens |
|---|---|
| Quitting Zeron from a session it hosts | Kills your own session and the owner's other sessions, mid-edit |
| Building with a dirty tree | Unfinished work ships into the app you use all day |
| Checking the tree only before the build | Too late - the Phase 1 merge already entangled or aborted on it |
| `git stash` without `-u` | Untracked new files stay in the tree and ride into the build anyway |
| Resetting `main` without checking it | Silently orphans anything committed there to the reflog |
| Rebasing `mine` | Rewrites history you already built from; every sync becomes conflict archaeology |
| Committing to `main` | It is a mirror; the next sync resets it away |
| Calling the backup "official" | After the first local install it is a local build, and rollback does not go where you think |
| Letting WIP "ride" when it collides with the main/mine diff | `git checkout main` refuses and the sync stops halfway |
| Checking only your own session before quitting | The app hosts several; report the count so the owner sees the blast radius |
| A bare `git push` on `mine` | Without `pushRemote`, tracking aims it at the original project's main |
| `cp -R` instead of `ditto` | Drops macOS metadata and can break the ad-hoc signature |
| Deleting the old app with no backup | No way back if the new build misbehaves |
| Accepting an offered update | Silently replaces the local build with the official one |
| Skipping tests after a sync | Upstream changes break local patches; the app is where you find out |
