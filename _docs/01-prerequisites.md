---
title: Prerequisites
order: 1
description: What you need installed and configured before starting.
duration: 15 minutes
---

# TODO

This is typically the first section readers actually do, and the
section with the most platform-specific quirks. A few patterns that
worked on the project this skeleton was extracted from:

## Always have separate Fedora and macOS instructions

Even when the commands are similar, readers want to see "their"
platform's commands, not commands for the other platform. Use side-
by-side blocks or platform-specific subheadings:

```markdown
### On Fedora

\`\`\`bash
sudo dnf install -y podman podman-compose
\`\`\`

### On macOS

\`\`\`bash
brew install podman podman-compose
podman machine init
podman machine start
\`\`\`
```

## Verify with a sanity check command

After install, give readers one command to confirm everything
worked:

```bash
podman --version && podman info --format='{{.Host.OS}} {{.Host.Arch}}'
```

This is more useful than just `podman --version` because it
exercises the whole stack (config files, machine on macOS, etc.).

## Note rootless vs. rootful

If your tutorial uses Podman, default to rootless. Note explicitly
that all commands work without `sudo`. If the tutorial does need
rootful for any reason (port binding < 1024, host-network access),
call that out section by section.

## SELinux note for Fedora users

If your tutorial mounts host directories into containers, mention
the `:Z` (or `-Z`) flag for SELinux relabeling. It's a no-op on
non-SELinux systems but required on Fedora — call this out once
here so readers don't hit "Permission denied" surprises later.

---

Replace this stub with the actual prerequisites for your tutorial.
The reconciliation plan should track the verification status of
each install command — `unverified` until you've tested it on a
fresh VM.
