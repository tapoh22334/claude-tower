# Claude Tower Troubleshooting Guide

Solutions for common issues with Claude Tower.

## Installation Issues

### Plugin not loading

**Symptoms**: No keybindings registered, `prefix + t` does nothing.

**Solutions**:

1. Reload tmux configuration:
   ```bash
   tmux source ~/.tmux.conf
   ```

2. Verify keybindings are registered:
   ```bash
   tmux list-keys | grep tower
   ```

   Expected output:
   ```
   bind-key -T prefix t run-shell ...
   ```

3. Check if scripts are executable:
   ```bash
   ls -la ~/.tmux/plugins/claude-tower/tmux-plugin/scripts/*.sh
   ```

   If not executable:
   ```bash
   chmod +x ~/.tmux/plugins/claude-tower/tmux-plugin/scripts/*.sh
   ```

### tmux version too old

**Symptoms**: Errors about unsupported commands.

**Solution**: Upgrade tmux to 3.2 or later:

```bash
# macOS
brew install tmux

# Ubuntu/Debian
sudo apt install tmux

# Verify version
tmux -V
```

## Navigator Issues

### Navigator shows shell prompt instead of UI

**Cause**: Script failed to start properly.

**Solutions**:

1. Check for script errors:
   ```bash
   ~/.tmux/plugins/claude-tower/tmux-plugin/scripts/navigator.sh
   ```

2. Verify dependencies:
   ```bash
   which tmux git
   ```

3. Check debug output:
   ```bash
   CLAUDE_TOWER_DEBUG=1 ~/.tmux/plugins/claude-tower/tmux-plugin/scripts/navigator.sh
   ```

### Navigator server won't start

**Symptoms**: Error about socket or server.

**Solutions**:

1. Kill existing Navigator server:
   ```bash
   tmux -L claude-tower kill-server 2>/dev/null
   ```

2. Remove stale socket:
   ```bash
   rm -f /tmp/tmux-$(id -u)/claude-tower
   ```

3. Retry opening Navigator.

### View pane shows error or is blank

**Cause**: Selected session may not exist or be inaccessible.

**Solutions**:

1. Check if session exists:
   ```bash
   tmux list-sessions
   ```

2. Verify session state:
   ```bash
   cat /tmp/claude-tower/selected
   ```

3. Select a different session with `j`/`k`.

## Session Issues

### Sessions not appearing in list

**Cause**: Sessions may not have `tower_` prefix.

**Solutions**:

1. Check session names:
   ```bash
   tmux list-sessions
   ```

   Claude Tower only shows sessions named `tower_*`.

2. Check metadata directory:
   ```bash
   ls ~/.claude-tower/metadata/
   ```

### Session creation fails

**Symptoms**: Error when pressing `n`.

**Solutions**:

1. Check if worktree directory is writable:
   ```bash
   ls -la ~/.claude-tower/
   mkdir -p ~/.claude-tower/worktrees
   mkdir -p ~/.claude-tower/metadata
   ```

2. For workspace mode, verify git repository:
   ```bash
   git status
   ```

3. Check for name conflicts:
   ```bash
   tmux has-session -t tower_YOUR_NAME 2>/dev/null && echo "exists"
   ```

### Session restoration fails

**Symptoms**: Dormant sessions (○) won't restore.

**Solutions**:

1. Check metadata file exists:
   ```bash
   cat ~/.claude-tower/metadata/tower_SESSION_NAME
   ```

2. Verify worktree path (for workspace sessions):
   ```bash
   ls -la ~/.claude-tower/worktrees/SESSION_NAME
   ```

3. Manual restore:
   ```bash
   ~/.tmux/plugins/claude-tower/tmux-plugin/scripts/session-restore.sh tower_SESSION_NAME
   ```

## Git Worktree Issues

### Orphaned worktrees

**Symptoms**: Worktrees exist without corresponding sessions.

**Solution**:

```bash
# List orphans
~/.tmux/plugins/claude-tower/tmux-plugin/scripts/cleanup.sh --list

# Clean up
~/.tmux/plugins/claude-tower/tmux-plugin/scripts/cleanup.sh
```

### Worktree creation fails

**Symptoms**: Error during workspace session creation.

**Solutions**:

1. Check if in a git repository:
   ```bash
   git rev-parse --git-dir
   ```

2. Verify worktree permissions:
   ```bash
   mkdir -p ~/.claude-tower/worktrees
   touch ~/.claude-tower/worktrees/.test && rm ~/.claude-tower/worktrees/.test
   ```

3. Check for branch conflicts:
   ```bash
   git branch -a | grep tower/
   ```

## Debug Mode

Enable debug logging for detailed information:

```bash
export CLAUDE_TOWER_DEBUG=1
```

Then run Navigator or scripts. Debug output goes to stderr.

## Log File Locations

| Type | Location |
|------|----------|
| Runtime state | `/tmp/claude-tower/` |
| Metadata | `~/.claude-tower/metadata/` |
| tmux socket | `/tmp/tmux-$(id -u)/claude-tower` |

## Reset Claude Tower

If all else fails, reset to clean state:

```bash
# Kill Navigator server
tmux -L claude-tower kill-server 2>/dev/null

# Remove runtime state
rm -rf /tmp/claude-tower

# Optionally remove metadata (will lose dormant sessions)
# rm -rf ~/.claude-tower/metadata

# Reload tmux
tmux source ~/.tmux.conf
```

## Getting Help

- Check [SPECIFICATION.md](SPECIFICATION.md) for expected behavior
- Check [CONFIGURATION.md](CONFIGURATION.md) for settings
- Open an issue: https://github.com/tapoh22334/claude-tower/issues
