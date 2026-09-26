# dotfiles

Personal macOS configuration in [GNU Stow](https://www.gnu.org/software/stow/) package layout.
Cloning this repo changes nothing on your machine. `install.sh` is an explicit full-workstation
setup, including the Brewfile; you do not need to run it to use a few skills or scripts.

## Use individual tools

```sh
git clone https://github.com/SamJUK/dotfiles.git ~/dotfiles
```

Add this to your shell rc to use the scripts:

```sh
export PATH="$PATH:$HOME/dotfiles/bin"
```

Link just the skills you want. For example:

```sh
mkdir -p ~/.agents/skills
skill_target="$HOME/.agents/skills/bkt"
if [ ! -e "$skill_target" ] && [ ! -L "$skill_target" ]; then
  ln -s "$HOME/dotfiles/agents/.agents/skills/bkt" "$skill_target"
fi
```

For Claude Code, link the same skill into `~/.claude/skills` too, unless that directory already
points to `~/.agents/skills`. Keep existing entries when names clash. Skills and scripts may
need their own dependencies; see their instructions or usage text.

A shallow clone (`git clone --depth 1 ...`) is optional. It reduces downloaded Git history,
not which files are installed. There are no automatic clone or pull hooks.

## Full workstation setup

```sh
xcode-select --install
# After the command-line tools finish installing, ensure python3 is available.
git clone https://github.com/SamJUK/dotfiles.git ~/dotfiles
~/dotfiles/install.sh --check
~/dotfiles/install.sh
~/dotfiles/macos.sh
```

`--check` previews links and integration changes without installing dependencies or writing to
your home. It returns a nonzero status for conflicts. The full installer plans the public repo,
any `~/dotfiles-private` overlay and any `~/Projects/bed/dev-tools` checkout together. Override
those locations with `DOTFILES_PRIVATE` and `BED_DEV_TOOLS`.

Conflicting paths offer **keep existing** (the default), **diff**, **back up and replace**, or
**quit**. Multiple conflicts can also be kept or backed up together before the final confirmation.
Duplicate ownership between overlays and file/directory collisions must be resolved
in the repos first. Nothing is linked until you confirm the combined plan. `--yes` skips the
confirmation only when there are no unresolved conflicts; it never means overwrite.

After confirmation, the full installer installs Homebrew dependencies, fetches the pinned
third-party code (including Oh My Zsh and its theme/plugins, see below), then links
configuration and installs the global Composer lockfile. Shell startup tolerates missing
optional dependencies.

Existing Git and agent instruction files receive marked integration blocks. Existing symlinks
to other files require a decision before being replaced by local files; their targets are not
edited. Existing skills/rules directories, including custom directory symlinks, receive
individual entries rather than being replaced wholesale.

Changed files and replaced symlinks are backed up under `~/.local/state/dotfiles/backups/`.
Each run's `manifest.json` records original paths and backup locations. File permissions are
preserved. On a link failure, the installer attempts to restore backed-up paths; new links may
remain. Homebrew and Composer changes are not rolled back.

## Third-party code

Anything we use but don't own (Oh My Zsh, Powerlevel10k, zsh plugins, upstream agent skills) is
pinned to an exact commit in `vendor.ini`. The private overlay can add its own `vendor.ini`:

```ini
[bkt]
url    = https://github.com/avivsinai/bitbucket-cli
commit = 226f53b93996009b089c8cd5ee6a14173b13eb5f
path   = skills/bkt           # optional: folder to fetch, default whole repo
link   = .agents/skills/bkt   # optional: where to link it, default fetch only
track  = latest-release       # optional: branch or latest-release, default the repo's default branch
```

`install.sh` fetches only `path` at that commit into `~/.local/share/dotfiles/vendor/<name>`,
verifies it, and links it to `link`. Unknown keys are rejected, so typos fail loudly.
Vendor skills follow the same one-home rule as ours, so a name clash stops the install.

```sh
scripts/vendor-update.py --check   # list entries with newer upstream commits
scripts/vendor-update.py           # review the diff for each, and re-pin on a yes
```

Re-pinning only edits the manifest. Commit it, then run `install.sh` to fetch the new commit.
Don't `git pull` inside a vendor checkout: the installer refuses checkouts with local changes.

## Private overlay

```sh
gh auth login
gh repo clone SamJUK/dotfiles-private ~/dotfiles-private
~/dotfiles-private/install.sh --check
~/dotfiles-private/install.sh
~/dotfiles-private/bin/pull-sensitive-files <old-host>
```

The private entry point uses the same combined planner, but only applies links and integrations.
It requires Python 3, Stow and the public checkout. Set `DOTFILES_PUBLIC` if that checkout is
not at `~/dotfiles`. It does not install or upgrade workstation dependencies.

Secrets (SSH keys, VPN profiles, cloud and registry credentials, Claude settings) stay outside
either repo. `pull-sensitive-files` copies them over SSH from the old machine.

Overlay extension points:

- `~/.config/zsh/conf.d/*.zsh` is sourced at the end of `.zshrc`.
- `~/dotfiles-private/bin` is on PATH when present.
- `~/.agents/skills/<name>` holds private skills.
- `~/.agents/rules/<name>.md` holds additional agent instructions.

Every skill and script has one home across the public repo, private overlay and work tooling.
Move an item to promote it; do not copy it between repos. The combined planner rejects duplicate
skill names even when the two copies contain different filenames.

## Git profiles

The installer keeps `~/.gitconfig` as a local file and adds includes for shared settings in
`~/.config/git/shared.gitconfig` and the optional `~/.config/git/personal.gitconfig`. Keep your
name, email, signing and credential settings in the personal file, supplied by your private
overlay or created locally. The public config requires an explicit identity and does not enable
signing for you.

The personal file can conditionally include `work.gitconfig` for work remotes or a work directory.
Repository-local settings still take precedence. From inside a repository, check:

```sh
git var GIT_AUTHOR_IDENT
git config --show-origin --get user.email
```

## Updating

```sh
~/dotfiles/update.sh
```

Fetches configured repos, shows incoming commits and offers the full diff before asking to
fast-forward. Most files are symlinked into their working trees, so that fast-forward makes
changes live. Afterwards the installer previews and confirms installation changes separately.

The secret-scanning hook is opt-in. Run `pre-commit install` in each repo you maintain.

## Layout

| Package | Target |
|---|---|
| `zsh` | `.zshrc`, `.zprofile`, `.p10k.zsh`, `.config/zsh/{conf.d,p10k}` |
| `git` | `.config/git/{shared.gitconfig,ignore}`; `.gitconfig` supplies the local integration block |
| `ansible` | `.ansible.cfg` |
| `nvim`, `btop`, `warp`, `ghostty`, `sublime`, `vscode` | their live config paths |
| `agents` | `.agents/AGENTS.md`, `.agents/skills/*`, `.agents/rules/*`; known skills/rules also linked into Claude's directories |
| `claude` | `.claude/statusline-command.sh`; `.claude/CLAUDE.md` supplies the integration instruction |
| `composer` | `.composer/composer.{json,lock}` |
| `bin` | scripts added to PATH, not stowed; built binaries belong in `~/go/bin` or `~/.local/bin` |
| `iterm2`, `alfred` | import-only iTerm2 profile and Alfred snippets, not stowed |
| `scripts`, `tests` | installer implementation and regression tests, not stowed |

Stow uses `--no-folding` to keep application state out of the package trees. Existing custom
directory symlinks and agent integrations are handled by the planner instead of forcing Stow
to replace them.

## Verification

```sh
python3 -m unittest discover -s tests -v
shellcheck install.sh update.sh scripts/install-dependencies.sh
zsh -n zsh/.zprofile zsh/.zshrc
```

Tests use temporary homes and real Stow for link behaviour. Homebrew and shell dependency
clones are stubbed. These checks do not establish that the full Brewfile installs on a fresh Mac.
