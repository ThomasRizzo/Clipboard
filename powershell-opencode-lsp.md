**To set up PowerShell LSP (Language Server Protocol) with OpenCode**, you need to configure a **custom LSP server** because PowerShell is **not** one of OpenCode’s built-in LSPs (which cover languages like Python, TypeScript, Rust, C#, etc.).

OpenCode uses **PowerShellEditorServices** (the same LSP that powers the official PowerShell VS Code extension) in stdio mode. Here’s the exact step-by-step process:

### 1. Prerequisites
- Install **PowerShell 7+** (`pwsh`) if you don’t have it:  
  [Download from Microsoft](https://aka.ms/powershell) (or via your package manager).
- Make sure `pwsh` is in your PATH.

### 2. Download and place PowerShellEditorServices (PSES)
1. Go to the latest release:  
   [https://github.com/PowerShell/PowerShellEditorServices/releases/latest](https://github.com/PowerShell/PowerShellEditorServices/releases/latest)
2. Download **PowerShellEditorServices.zip**.
3. Extract it to a permanent folder. Recommended location (works on Windows/macOS/Linux):  
   `~/.opencode-lsp/pses/`  
   After extraction, you should have:  
   `~/.opencode-lsp/pses/PowerShellEditorServices/Start-EditorServices.ps1`
4. Create the logs directory:  
   ```bash
   mkdir -p ~/.opencode-lsp/pses/logs
   ```

### 3. Configure OpenCode’s LSP
OpenCode looks for config in two places (project-level takes precedence):
- **Project-specific**: `opencode.json` in your project root (recommended for per-project setup).
- **Global**: `~/.config/opencode/opencode.json` (or equivalent on your OS).

Create or edit the file and add the `lsp` section:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "lsp": {
    "powershell": {
      "command": [
        "pwsh",
        "-NoLogo",
        "-NoProfile",
        "-Command",
        "& '~/.opencode-lsp/pses/PowerShellEditorServices/Start-EditorServices.ps1' -Stdio -HostName OpenCode -HostVersion 1.0.0 -BundledModulesPath '~/.opencode-lsp/pses' -LogPath '~/.opencode-lsp/pses/logs' -LogLevel Normal"
      ],
      "extensions": [".ps1"]
    }
  }
}
```

**Important notes on the config**:
- Use **forward slashes** (`/`) in paths, even on Windows.
- Replace `~/.opencode-lsp/pses` with your actual absolute path if you used a different location.
- The `-HostName OpenCode` tells PSES it’s running under OpenCode.

### 4. Test it
1. Restart OpenCode (or just run `opencode` again in your project).
2. Open a `.ps1` file.
3. OpenCode will automatically detect the `.ps1` extension, start the PowerShell LSP server, and feed diagnostics/intellisense to the LLM.

You can verify it’s running with:
```bash
opencode debug lsp diagnostics path/to/your/script.ps1
```

### Optional enhancements
- **Add more options** (e.g., environment variables or initialization options) using the same LSP config format shown in the official docs.
- **Disable other LSPs** if you only want PowerShell: `"lsp": { "powershell": { ... }, "typescript": { "disabled": true } }` etc.
- If you also work with Bicep (`.bicep` files), the same config file can include both (see the example script in the blog linked below).

This setup is based on the exact pattern used in the community for custom LSPs in OpenCode (including the Bicep + PowerShell example).

If you run into path issues, permission problems, or the server doesn’t start, check the logs in `~/.opencode-lsp/pses/logs/` and share the error here for troubleshooting. OpenCode’s LSP integration is very flexible once the command array is correct!