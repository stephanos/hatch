# hatch

`hatch` is a macOS app and CLI for git workspace management.

It helps you create, switch, and resume task-focused git workspaces from a Spotlight-style launcher or the command line.

## Install

Download the latest packaged build from GitHub Releases:

- https://github.com/stephanos/hatch/releases/latest

Then:

1. Download `Hatch.app.zip`
2. Unzip it
3. Move `Hatch.app` to `/Applications`
4. Open `Hatch.app`

On first launch, macOS may ask you to confirm opening the app.

## Development

To build from source, you need:

- `mise`

From this directory:

```sh
mise trust
mise install
mise run install
```

The install task builds `Hatch.app`, copies it to `/Applications/Hatch.app`, and launches it.

For local development:

```sh
mise run run
```

To build and open the packaged app bundle instead:

```sh
mise run open
```

## Configuration

On first launch, hatch writes TOML config files in:

- `~/.config/hatch/config.toml`
- `<workspace>/.hatch/config.toml`

Project configuration is also TOML-only at `<project>/hatch.toml`.

Full configuration, hook lifecycle, and environment variable documentation lives in [docs/configuration.md](/Users/stephan/Workspace/hatch/docs/configuration.md).

## Development Tasks

```sh
mise run fmt
mise run check
mise run test
mise run build
mise run bundle
```

- `fmt` formats the Swift sources with `swift-format`
- `check` runs strict formatting checks and builds the app
- `test` runs the hatch regression test suite
- `build` builds the SwiftPM executable
- `bundle` builds `dist/Hatch.app`
