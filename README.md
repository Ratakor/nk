# nekoweb
nekoweb is a CLI for [Nekoweb](https://nekoweb.org) using its [API](https://nekoweb.org/api).

## Installation

### [AUR](https://aur.archlinux.org/packages/nekoweb-bin) (Arch Linux)

```
git clone https://aur.archlinux.org/nekoweb-bin.git
cd nekoweb-bin
makepkg -si
```

### Manual Installation

Grab one of the [release](https://github.com/Ratakor/nekoweb/releases)
according to your system. Zsh completions are available [here](_nekoweb).

### Building

Requires zig 0.13.0.
```
git clone https://github.com/ratakor/nekoweb
cd nekoweb
zig build -Doptimize=ReleaseSafe
```

## Usage
```
Usage: nekoweb [command] [options]

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
