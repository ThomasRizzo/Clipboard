# Claude Chrome Extension CRX Download URL

Unofficial CRX download endpoint for the official Anthropic Claude in Chrome extension (for offline / air-gapped install).

**Extension ID:** `fcoeoabgfenejglbffodgkkbkcdhcgfn`

**CRX URL** (update `prodversion` to a recent Chrome version if needed):

```
https://clients2.google.com/service/update2/crx?response=redirect&prodversion=131.0.0.0&acceptformat=crx3&x=id%3Dfcoeoabgfenejglbffodgkkbkcdhcgfn%26uc
```

## Notes

- Official install is only via the Chrome Web Store: https://chromewebstore.google.com/detail/claude/fcoeoabgfenejglbffodgkkbkcdhcgfn
- Requires a paid Claude plan (Pro / Max / Team / Enterprise).
- After downloading the `.crx`, rename to `.zip`, extract, and load as unpacked in `chrome://extensions/` (Developer mode).
- Manually loaded extensions do not auto-update.
- The extension still needs network access at runtime to reach Anthropic servers.

Added 2026-10-19.
