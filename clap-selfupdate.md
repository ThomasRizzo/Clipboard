# Adding Self-Update to a Rust Clap CLI

**The most straightforward and robust approach is the `self_update` crate.** It handles downloading, verifying, extracting, and replacing the running binary (using `self_replace` under the hood for the tricky in-place replacement). It's designed exactly for Rust CLIs and works well with internal/on-prem setups.

## 1. Use `self_update` with GitLab backend (closest to Bitbucket)

Bitbucket doesn't have a dedicated backend like GitHub/GitLab, but **GitLab's** is very similar and often adaptable. You can:

- Host releases as downloads/artifacts in your on-prem Bitbucket repo (or a dedicated releases repo/project).
- Use the **GitLab backend** if you can mirror or expose via a GitLab-compatible API, or implement a thin wrapper.
- Or use the **custom backend** (`backends::custom`) by implementing the `ReleaseSource` trait. This is flexible for Bitbucket REST API (downloads endpoint) or any HTTP file listing.

Add to `Cargo.toml` (enable needed features):

```toml
[dependencies]
self_update = { version = "0.42", features = ["archive-tar", "archive-zip", "compression-flate2", "rustls"] }  # adjust as needed
clap = { version = "...", features = ["derive"] }
```

Basic integration with Clap (add a subcommand or `--update` flag):

```rust
use clap::Parser;
use self_update::cargo_crate_version;

#[derive(Parser)]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(clap::Subcommand)]
enum Commands {
    Update,
    // ... other commands
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cli = Cli::parse();

    match cli.command {
        Some(Commands::Update) => update_self()?,
        _ => { /* run normal CLI */ }
    }
    Ok(())
}

fn update_self() -> Result<(), Box<dyn std::error::Error>> {
    // Example with GitLab backend (adapt for Bitbucket)
    let status = self_update::backends::gitlab::Update::configure()
        .repo_owner("your-group")
        .repo_name("your-repo")
        .bin_name("your-cli-binary-name")  // e.g., "mytool"
        .current_version(cargo_crate_version!())
        .show_download_progress(true)
        // .no_confirm(true)  // for non-interactive/CI
        .build()?
        .update()?;

    println!("Updated to version: {}", status.version());
    Ok(())
}
```

See the [GitLab example](https://github.com/jaemk/self_update/tree/master/examples) in the repo for details.

## 2. Simpler: File share / HTTP endpoint (recommended for on-prem)

Use a network file share (SMB, NFS, HTTP static server on the file share) + the **S3-compatible backend** (if you expose it via MinIO/S3-like) or **custom** + plain HTTP.

- Build releases as `yourtool-{version}-{target}.tar.gz` or `.zip` (e.g., via GitHub Actions or your Bitbucket pipeline + artifacts).
- Place them in a predictable path on the file share (e.g., `\\fileserver\\releases\\yourtool\\` or `https://internal-artifacts.example.com/releases/`). 
- Use `self_update::Download` + `Extract` + `self_replace::self_replace` for full control, or implement a minimal `ReleaseSource`.

This avoids API token/auth complexity if the share is mounted/readable by the CLI users.

Example low-level flow (works with any URL or local path):

```rust
use self_update::{Download, Extract, get_target};
use std::path::Path;

fn update_from_fileshare() -> Result<(), Box<dyn std::error::Error>> {
    let latest_version = "1.2.3"; // Fetch from a version.txt or API
    let asset_url = format!("https://fileshare.example.com/releases/yourtool-{}-{}", 
                           latest_version, get_target());

    let tmp_dir = tempfile::Builder::new().prefix("self_update").tempdir()?;
    let tmp_file = tmp_dir.path().join("update.tar.gz");

    Download::from_url(&asset_url)
        .download_to(&std::fs::File::create(&tmp_file)?)?;

    let bin_name = "yourtool"; // or platform-specific
    Extract::from_source(&tmp_file)
        .archive(self_update::ArchiveKind::Tar(Some(self_update::Compression::Gz)))
        .extract_file(tmp_dir.path(), bin_name)?;

    let new_exe = tmp_dir.path().join(bin_name);
    self_replace::self_replace(new_exe)?;

    Ok(())
}
```

For file share paths on Windows (`\\server\\share\\...`), it often works directly with `std::fs` / URLs. On Linux, you may need mounting or `smbclient`/crates like `smb2`.

## Additional Recommendations

- **Versioning & Detection**: Use `cargo_crate_version!()` or embed a manifest. Compare against a `latest-version.txt` or metadata file on the share/Bitbucket.
- **CI Releases**: In your Bitbucket pipelines, build for targets (`x86_64-unknown-linux-gnu`, `x86_64-pc-windows-msvc`, etc.) and upload artifacts to the file share or repo downloads.
- **Safety**:
  - Verify checksums (`checksums` feature) or signatures.
  - Use temp dirs and atomic replace.
  - Handle permissions (running binary can't always overwrite itself on some OSes — `self_update` handles this).
- **Alternatives**:
  - Pure custom with `reqwest`/`ureq` + `self_replace` if `self_update` feels heavy.
  - For very controlled envs: `cargo install --git` your on-prem repo (but less "self-update" feel).
- **Testing**: Test on Windows/Linux; watch for locked files, AV interference, and cross-filesystem issues.

This setup integrates cleanly with Clap (as a subcommand or flag) and leverages your existing on-prem infrastructure without public GitHub dependency. Check the `self_update` docs/examples for your exact backend.

If you share more details (e.g., target platforms, auth requirements, or current build setup), the example code can be refined further!
