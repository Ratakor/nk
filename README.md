# nk
nk is a CLI for [Nekoweb](https://nekoweb.org) using its [API](https://nekoweb.org/api).

## Installation

### [AUR](https://aur.archlinux.org/packages/nk-bin) (Arch Linux)

```
git clone https://aur.archlinux.org/nk-bin.git
cd nk-bin
makepkg -si
```

### Manual Installation

Grab one of the [release](https://github.com/Ratakor/nk/releases)
according to your system. Zsh completions are available [here](_nk).

### Building

Requires zig 0.13.0.
```
git clone https://github.com/ratakor/nk
cd nk
zig build -Doptimize=ReleaseSafe
```

## Usage
```
Usage: nk [command] [options]

Commands:
  info       | Display information about a Nekoweb website
  create     | Create a new file or directory
  upload     | Upload files to your Nekoweb website
  delete     | Delete file or directory from your Nekoweb website
  move       | Move/Rename a file or directory
  list       | List files from your Nekoweb website
  logout     | Remove your API key from the save file
  help       | Display information about a command
  version    | Display program version
```
