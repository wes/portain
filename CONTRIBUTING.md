# Contributing to Portain

Thanks for your interest! Portain is a small, focused SwiftUI app — contributions
that keep it fast, native, and read-only are very welcome.

## Getting set up

Requirements: macOS 14+ and the Swift toolchain (Xcode or the Swift command-line
tools).

```sh
git clone https://github.com/wes/portain.git
cd portain
swift run                 # build and launch the dev app
```

To produce a bundled, double-clickable app locally:

```sh
bash scripts/bundle.sh    # → Portain.app (ad-hoc signed)
```

## Project layout

```
Sources/Portain/
  App/        — @main entry, app delegate, About panel
  Models/     — DockerContainer, ListeningPort, value types
  Services/   — DockerService, PortService, parsers, ProcessRunner
  State/      — AppState (ObservableObject coordinating refresh + actions)
  Views/      — SwiftUI views (Containers, Ports, detail panes, components)
scripts/      — bundle.sh, release.sh, icon generator, Info.plist
```

## Guidelines

- **Native first.** Prefer standard SwiftUI controls (`Form`, `Table`,
  `LabeledContent`, `.bordered` buttons) over bespoke "web-like" UI.
- **Read-only by design.** Portain visualizes and performs simple lifecycle
  actions; it must never install software or mutate state the user didn't click.
- **Match the surrounding style.** Keep comment density and naming consistent.
- Run a `swift build` before opening a PR, and describe the user-facing change.

## Reporting issues

Open a GitHub issue with your macOS version, Docker runtime (Docker Desktop /
OrbStack / Colima), and steps to reproduce. Screenshots help for UI reports.
