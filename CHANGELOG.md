# Changelog

All notable changes to Portain are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project aims to
follow [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-06-10

First public release.

### Containers
- Live list of all containers grouped into **Running** and **Stopped** sections.
- Containers nest under collapsible, Finder-style **Compose project** folders
  (Running folders expand by default, Stopped folders collapse).
- Single-line rows with status dot, name, image column, and published ports.
- Hover a row for inline start/stop actions.
- Native detail pane (Start · Stop · Restart · Kill · Logs · Remove) with a
  ports table, live CPU/memory, and a logs viewer.

### Ports
- Native table of every listening TCP port with process, PID, type, address,
  and user columns; the kill action stays pinned to the right at any width.
- Terminate (SIGTERM) or Force Kill (SIGKILL), single or multi-select.
- Ports cross-link to the Docker container that published them.

### Throughout
- Auto-refresh every 3s (toggleable), ⌘R to refresh now, live search.
- Built entirely with SwiftUI — native sidebar, materials, and SF Symbols.

[1.0.0]: https://github.com/wes/portain/releases/tag/v1.0.0
