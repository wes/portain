# Portain ⛵

A beautiful, native macOS app for **seeing what's running** — your Docker
containers and the processes holding your ports — and acting on them fast.
Think PortKiller × OrbStack, minus the orchestration: pure visualization plus
simple, safe actions.

Built entirely in Swift + SwiftUI. **Read-only by design** — it shells out to
`docker` and `lsof` and never installs or changes anything you didn't click.

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)
[![Release](https://img.shields.io/github/v/release/wes/portain?include_prereleases)](https://github.com/wes/portain/releases/latest)

> Replace `wes/portain` in the badges and links with your repository path.

<!-- Add a screenshot at docs/screenshot.png and uncomment:
![Portain](docs/screenshot.png)
-->

## Install

**Download (recommended)**

1. Grab the latest **`Portain-x.y.z.dmg`** from the
   [Releases page](https://github.com/wes/portain/releases/latest).
2. Open the `.dmg` and drag **Portain** into **Applications**.
3. First launch only: because the app is open-source and not notarized,
   right-click **Portain → Open**, then confirm. (Or run
   `xattr -dr com.apple.quarantine /Applications/Portain.app`.)

The app is a **universal binary** — it runs natively on Apple Silicon and Intel.

**Build from source**

```sh
swift run                 # dev build, runs immediately
bash scripts/bundle.sh    # → Portain.app (ad-hoc signed, with icon)
```

Requires macOS 14+ and the Swift toolchain. Docker is optional — the **Ports**
view works without it.

## Features

**Containers**
- All containers grouped into **Running** / **Stopped**, nested under
  collapsible, Finder-style **Compose project** folders.
- Single-line rows: status dot, name, image, published ports; hover for inline
  start/stop.
- Native detail pane — **Start · Stop · Restart · Kill · Logs · Remove** — with a
  ports table and live CPU / memory.

**Ports**
- Native table of every listening TCP port: process, PID, type, address, user.
- **Terminate (SIGTERM)** or **Force Kill (SIGKILL)**, one or many at once.
- Each port cross-links to the Docker container that published it.

**Throughout**
- Auto-refresh every 3s (toggleable), ⌘R to refresh now, live search.
- Native sidebar, materials, and SF Symbols — no Electron.

## How it works

| Concern    | Source                                          |
| ---------- | ----------------------------------------------- |
| Containers | `docker ps -a --format '{{json .}}'` + `docker stats` |
| Actions    | `docker start / stop / restart / kill / rm`     |
| Ports      | `lsof -nP -iTCP -sTCP:LISTEN -F`                 |
| Kill port  | `kill -TERM` / `-KILL`                           |

No daemons, no background agents. Killing a process owned by another user or the
system may require elevated permissions and reports a clear error.

## Releasing (maintainers)

```sh
scripts/release.sh 1.0.0        # universal build → dist/*.dmg, *.zip, SHA256SUMS.txt
```

Or let CI do it: push a tag and the
[`Release` workflow](.github/workflows/release.yml) builds the artifacts and
publishes a GitHub Release.

```sh
git tag v1.0.0 && git push origin v1.0.0
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Issues and PRs welcome.

## License

[MIT](LICENSE) © Joedesign.com
