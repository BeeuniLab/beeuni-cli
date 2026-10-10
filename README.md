# Beeuni CLI

This is the public distribution repository for the Beeuni command-line
client. The CLI source remains in a private repository; this repository only
contains the installer, release metadata, and prebuilt binaries attached to
GitHub Releases.

## Install

```sh
curl -fsSL https://beeuni.ai/install | bash
```

The installer detects macOS or Linux and downloads the matching binary for
`arm64` or `x64` from the latest stable release in this repository.

To install a specific version:

```sh
  curl -fsSL https://beeuni.ai/install | BEEUNI_VERSION=0.1.0 bash
```

The release assets are named:

```text
beeuni-darwin-arm64
beeuni-darwin-x64
beeuni-linux-arm64
beeuni-linux-x64
SHA256SUMS
```

## Desktop app

Desktop installers are attached to the [latest release](https://github.com/BeeuniLab/beeuni-cli/releases/latest).
The macOS download is a universal `.dmg` for Apple Silicon and Intel. Desktop
releases also include update metadata alongside the installers.
These desktop installers are unsigned; in-app automatic updates require signed builds.

## Usage

```sh
beeuni login
beeuni projects ls
beeuni projects link
beeuni --help
```

The CLI connects to the Beeuni platform API at `https://api.beeuni.ai` by default.
Use `beeuni login --help` to configure a different host or API endpoint.

## Releases

Releases are built from the private Beeuni source repository and published
here by the release workflow. This repository does not contain the CLI source
code or the private platform configuration.
