# Portain TUI

A terminal companion to the native Portain app, built with [OpenTUI](https://github.com/anomalyco/opentui). The Swift app is untouched.

## Install and run

Requires [Bun](https://bun.sh), Docker for the Containers tab, and `lsof` for Ports.

```sh
bunx portain
```

Or install globally:

```sh
bun add --global portain
portain
```

From a checkout:

```sh
cd tui
bun install
bun run start
```

The package is a Bun CLI, so Bun must be installed even when using `bunx` or a global install. Docker is optional if you only need the Ports tab.

## Controls

- `Tab` / `←` / `→` switch between Containers and Ports
- `↑` / `↓` or `j` / `k` select an item
- Containers: `s` start/stop, `r` restart, `d` remove
- Ports: `x` terminate (SIGTERM), `Shift+x` force kill (SIGKILL)
- Ports: `r` refresh, `q` or `Esc` quit

The view refreshes automatically every five seconds. Destructive actions ask for confirmation.

## Publish (maintainers)

From this directory, bump the version and publish the public package:

```sh
npm version patch
npm publish --access public
```

The package name is `portain`.
