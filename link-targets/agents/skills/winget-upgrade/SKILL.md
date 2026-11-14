---
name: winget-upgrade
description: List and apply winget package upgrades on Windows with a single UAC approval, leaving out packages the user wants to keep. Use for requests such as `wingetで更新して` (upgrade with winget), `wingetのアップデート` (winget updates), or listing apps that winget can upgrade. Not for aqua-managed CLI tools, editing `winget.json`, or non-Windows hosts.
---

# winget upgrade

Windows only. This skill changes installed software, so act only within what the user asked for. When the user asked only for a list, stop after step 2.

## 1. List upgrades and pins

```powershell
winget upgrade --disable-interactivity --accept-source-agreements
winget pin list --disable-interactivity
```

Present a table with name, ID, installed version, and available version, and mention how many packages a pin holds back. If a column is truncated (an ID ending in `…`), get the full ID with `winget show --name "<name>"` before using it.

## 2. Check overlaps with aqua

Run this step when `~/.dotfiles/aqua.yaml` exists.

- An `aqua.yaml` entry alone does not make a winget package a duplicate. Check which executable actually runs with `(Get-Command <exe> -All).Source` and `aqua which <exe>`. It is a real duplicate only when aqua provides the executable on Windows, that is, the resolved path is under `aquaproj-aqua`.
- Some aqua packages are unavailable on Windows x64 and fall back to the winget installation (for example AWS CLI and aws-vault). Those stay winget-managed.
- `chezmoi apply` reinstalls packages listed in `~/.dotfiles/winget.json`. Do not uninstall such a package unless the user also wants `winget.json` changed, which is a separate repository change.
- Report real duplicates. Uninstall one only when the user asks, with `winget uninstall --id <id> --exact`, and then confirm the aqua executable resolves first.

## 3. Decide what to leave out

- **One-off exclusion:** leave the package out of the ID list in step 4. Do not add a temporary pin for this: an interrupted run would leave the pin behind, and it would be indistinguishable from a lasting one.
- **Lasting hold** (for example a version a product depends on): add `winget pin add --id <id> --exact --blocking` only when the user asks for it.
- Never remove an existing pin unless the user asks.

## 4. Upgrade in one elevated run

Tell the user that one UAC prompt will appear, then run the bundled script in the background, because installs can outlast the tool timeout:

```powershell
pwsh -NoProfile -File "$HOME/.agents/skills/winget-upgrade/scripts/Invoke-WingetUpgrade.ps1" -PackageId <Id1>,<Id2>
```

The script:

- starts one elevated PowerShell process for all packages (or runs in-process when the caller is already elevated) and upgrades them one at a time;
- writes one UTF-8 log per package to a new `winget-upgrade-*` directory under the temporary directory, and prints a summary with the status of each package: `Upgraded`, `NoUpgradeAvailable`, `BlockedByPin`, `NotInstalled`, or `Failed`;
- reports the error and the packages already finished when the elevated process stops partway.

Exit codes: `0` when every package was upgraded or had no applicable upgrade, `1` when at least one package is `BlockedByPin`, `NotInstalled`, or `Failed` or the run stopped partway, and `2` for invalid input, declined elevation, or no result at all. When `pwsh` comes from aqua, a following `aqua failed ... exit status 1` (or `2`) line only repeats the script's exit code.

The script does not retry. For a `Failed` package, read its log first. If the log shows the installer refused to run elevated, rerun only that package from a non-elevated shell with `winget upgrade --id <id> --exact`, and tell the user it may show its own UAC prompt.

Do not stop the script or winget while a package is installing. Stopping an installer midway can leave the package half-installed.

## 5. Verify and report

- Run `winget upgrade` again. An app whose log says it must restart to finish the upgrade (Microsoft Teams, for example) keeps showing the old version until it restarts. Report that instead of upgrading again.
- Report the result for each package from the summary. For a `Failed` package, read its log and report the cause.
- Delete the log directory after reporting unless the user asks to keep it.
