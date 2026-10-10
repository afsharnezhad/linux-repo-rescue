# linux-repo-rescue

**A small, cautious Bash utility for diagnosing and temporarily working around unreachable `pacman` repository databases on Arch Linux.**

Your package manager can fail to install *any* package when a configured repository database cannot be downloaded. Repo Rescue detects the repository database named in the `pacman` error, asks before making changes, temporarily comments out that repository section in `/etc/pacman.conf`, performs the requested package transaction, and restores the original configuration automatically.

> This is a first version built around a real troubleshooting case. It is not a universal network repair tool and it cannot install packages that exist only in the repository it temporarily disables.

## Why this exists

Example failure:

```text
ryoku.db failed to download
error: failed retrieving file 'ryoku.db' from repo.ryoku.dev
error: failed to synchronize all databases
error: failed to prepare transaction (could not find database)
```

The script does not hard-code `ryoku`. It reads the failed `.db` name from `pacman` output and maps it to the corresponding repository section. The same idea can help with other named repositories, provided the error format is recognized and the repository is defined directly in `/etc/pacman.conf`.

## Features

- Detects repository database synchronization failures.
- Does not hard-code a specific repository name.
- Makes a timestamped backup of `/etc/pacman.conf`.
- Shows the candidate repository section(s) and asks for confirmation.
- Temporarily comments out only the identified section(s).
- Restores the original configuration on normal exit and most errors.
- Supports a dry-run mode.
- Keeps a backup for manual recovery.
- Does not delete repository definitions or package databases.

## Requirements

- Arch Linux or an Arch-based distribution using `pacman`.
- Bash 4+.
- `pacman`, `awk`, `sed`, `grep`, `tee`.
- Root privileges to edit `/etc/pacman.conf` and install packages.
- Repository sections must be declared in `/etc/pacman.conf` for the current version to modify them.

## Quick start

Clone the repository:

```bash
git clone https://github.com/YOUR-USERNAME/repo-rescue.git
cd repo-rescue
```

Make the script executable if needed:

```bash
chmod +x scripts/repo-rescue.sh
```

Check the plan without changing anything:

```bash
sudo ./scripts/repo-rescue.sh --dry-run xterm
```

Install a package:

```bash
sudo ./scripts/repo-rescue.sh xterm
```

Install several packages:

```bash
sudo ./scripts/repo-rescue.sh git curl jq
```

By default, the script runs a **full system upgrade** together with the requested install:

```bash
pacman -Syu --needed -- package...
```

This is the normal safer pattern on Arch Linux; partial upgrades are unsupported.

### Optional: skip full upgrade

```bash
sudo ./scripts/repo-rescue.sh --no-upgrade xterm
```

This uses `pacman -S --needed` and may result in an unsupported partial upgrade. Use it only if you understand the risk.

### Optional: leave failed repositories disabled

```bash
sudo ./scripts/repo-rescue.sh --keep-disabled xterm
```

This intentionally does not restore the original configuration automatically. The backup path is printed. Use this only when you deliberately want to keep the repository disabled.

## Recovery

The script creates a backup similar to:

```text
/etc/pacman.conf.repo-rescue.20261010-190000.bak
```

To restore manually, replace the path with the exact backup printed by the script:

```bash
sudo cp -a /etc/pacman.conf.repo-rescue.TIMESTAMP.bak /etc/pacman.conf
```

Then inspect and synchronize:

```bash
grep -n -A 2 '^\[.*\]' /etc/pacman.conf
sudo pacman -Syy
```

Do not restore an old backup blindly if you have made other intentional changes to `pacman.conf` since creating it.

## What it cannot fix

Repo Rescue does **not** fix:

- DNS failures or general network outages.
- Server-side downtime or routing/filtering issues.
- Invalid repository URLs.
- GPG signature or keyring errors.
- Mirror problems unrelated to the named failed repository database.
- A package that is only available from the repository being disabled.
- A failed repository configured indirectly through an included file such as `Include = ...` rather than as a direct section in `/etc/pacman.conf`.

If synchronization fails without a recognizable repository `.db` filename, the script stops without changing the configuration.

## Security and design notes

- Review the code before running it with `sudo`.
- It does not run arbitrary commands from repository configuration.
- It preserves the original config in a backup before editing.
- It asks for approval before disabling repositories.
- It restores the original config automatically unless `--keep-disabled` was selected.
- It cannot guarantee recovery after power loss, kernel crash, or forced termination; the timestamped backup exists for manual recovery.
- Repository disabling can change which package versions are available. Use only when you understand the implications.

## Project structure

```text
repo-rescue/
├── README.md
├── LICENSE
├── .gitignore
├── scripts/
│   └── repo-rescue.sh
└── docs/
    └── troubleshooting-notes.md
```

## Roadmap

- [ ] Add automated shell tests using a temporary fake `pacman.conf`.
- [ ] Improve parsing for more `pacman` error variants.
- [ ] Support repository definitions from included config files safely.
- [ ] Add structured logs and an optional `--verbose` mode.
- [ ] Test on clean Arch Linux and selected Arch-based distributions.
- [ ] Add CI shell linting with ShellCheck.

## Contributing

Issues and pull requests are welcome. Please include:
- Distribution and `pacman` version.
- The exact synchronization error with private information removed.
- Whether the failing repository is declared in `pacman.conf` or an included file.

Never post tokens, credentials, private mirror URLs, or other sensitive configuration.

## License

MIT — see [LICENSE](LICENSE).

---

**Project principle:** Diagnose first. Change the smallest possible surface area. Back up. Ask. Restore.
