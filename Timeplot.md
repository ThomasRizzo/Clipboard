**egui_plot** is the official immediate-mode 2D plotting library for the `egui` Rust GUI framework. It is lightweight, performant for typical use cases, and fully interactive (pan, zoom, hover, etc.). It is an excellent fit for your real-time temperature-over-time plot.

### Key Capabilities Relevant to Your Use Case
- **Line plots for time series**: Use `Line::new(name, PlotPoints)` where `PlotPoints` is a collection of `[f64; 2]` points (x = time, y = temperature). It supports thousands of points efficiently and renders only the visible portion.
- **X-axis as local time**: X values are always `f64`. You store time as a numeric value (e.g., Unix timestamp in seconds via `chrono::Local::now().timestamp()` or seconds since app start). Then use a **custom formatter** on the X-axis to display human-readable local time (HH:MM:SS, or full date if needed). Ticks and hover labels are fully customizable.
- **Fixed 2-hour scrollable window**: 
  - Enable drag-to-pan, mouse-wheel scroll/zoom (per-axis if desired).
  - Set a default/fixed width of 7200 seconds (2 hours) while allowing the user to scroll through the full 24-hour history.
  - Common pattern: maintain full history + a “follow latest” / live mode that keeps the 2-hour window sliding forward automatically. Add a toggle/button so the user can pause and scroll back freely. Double-click (default) resets view.
- **Data volume & real-time updates**:
  - 1 sample/second → ~7 200 points in the 2-hour window, ~86 400 points for a full 24-hour dataset. This is perfectly manageable (low memory, good frame rate on desktop/web).
  - For even better performance with very dense data, you can optionally downsample only the visible range before creating `PlotPoints` (e.g., using a simple mip-map / min-max binning technique that many users implement).
  - Real-time: append points every second (use a `Vec` or `VecDeque`, or thread + channel to feed data into the UI). `egui` will repaint as needed.

### Recommended Dependencies
```toml
egui = "0.30"          # or latest
egui_plot = "0.30"     # or latest (check crates.io)
eframe = "0.30"        # for the app window
chrono = { version = "0.4", features = ["clock"] }  # for local time
```

### High-Level Code Structure
```rust
use egui_plot::{Line, Plot, PlotPoints, PlotUi};
use chrono::{DateTime, Local};
use std::sync::{Arc, Mutex};

// In your App struct
struct MyApp {
    data: Arc<Mutex<Vec<(f64, f64)>>>,  // (time_seconds, temperature)
    follow_latest: bool,
    last_time: f64,                     // latest timestamp
}

// Called every frame
fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
    egui::CentralPanel::default().show(ctx, |ui| {
        let data = self.data.lock().unwrap();  // or use RwLock / channel for real-time

        if data.is_empty() { return; }

        let latest_time = data.last().unwrap().0;

        // Decide visible X range (fixed 2-hour window)
        let x_min = if self.follow_latest {
            latest_time - 7200.0
        } else {
            // user-controlled via previous pan/zoom; you can store view state if needed
            // for simplicity we let the plot remember bounds via its internal memory
            latest_time - 7200.0  // fallback
        };
        let x_max = x_min + 7200.0;

        let plot = Plot::new("temperature_plot")
            .view_aspect(2.0)                    // wider than tall
            .x_axis_label("Local Time")
            .y_axis_label("Temperature (°C)")
            .default_x_bounds([x_min, x_max])    // initial/fixed width
            .allow_drag(true)                    // scrollable / pan
            .allow_scroll(true)
            .allow_zoom(egui::Vec2b { x: true, y: true })  // or disable x-zoom if you want strictly fixed width
            .allow_double_click_reset(true)
            .x_axis_formatter(|mark: egui_plot::GridMark, _range| {
                // Convert f64 (unix seconds) → local time string
                let dt: DateTime<Local> = DateTime::from_timestamp(mark.value as i64, 0)
                    .unwrap_or_default()
                    .with_timezone(&Local);
                dt.format("%H:%M:%S").to_string()   // or "%m-%d %H:%M" for multi-day
            })
            .label_formatter(|name, value| {
                format!("{}: {:.1} °C at {}", name, value.y, {
                    let dt = DateTime::<Local>::from_timestamp(value.x as i64, 0)
                        .unwrap_or_default().with_timezone(&Local);
                    dt.format("%H:%M:%S").to_string()
                })
            });

        plot.show(ui, |plot_ui: &mut PlotUi| {
            let points: PlotPoints = data
                .iter()
                .filter(|(t, _)| *t >= x_min && *t <= x_max)  // optional visible cull
                .map(|&(t, temp)| [t, temp])
                .collect();

            let line = Line::new("Temperature", points)
                .stroke(egui::Stroke::new(2.0, egui::Color32::from_rgb(0, 180, 255)))
                .fill(0.0);  // optional area fill under curve

            plot_ui.line(line);
        });
    });

    // Real-time data append (example)
    ctx.request_repaint_after(std::time::Duration::from_secs(1));
}
```

### Tips & Best Practices
- **Live sliding window**: When `follow_latest` is true, the window automatically advances. When the user drags/zooms, set `follow_latest = false`. Add a “Follow” button that re-enables it and jumps to the latest 2 hours.
- **Data storage**: Use a `VecDeque` with a max length of ~86 400 if you want to drop very old data automatically.
- **Performance**: 86 k points is fine on modern hardware. If you ever see lag, pre-filter to visible range (as shown) or implement simple down-sampling (bin the visible X-range into ~1 000–2 000 points and take min/max per bin).
- **Threading**: Capture data in a background thread and send it via `std::sync::mpsc` or `crossbeam-channel` to keep the UI responsive.
- **Demo / examples**: Run the official demo locally (`cargo run -p demo` after cloning the egui_plot repo) – it shows interactive lines and axis customization. Community YouTube tutorials also demonstrate real-time sensor plots with egui.

This setup gives you exactly what you asked for: a clean, responsive, real-time temperature plot with a fixed-width 2-hour local-time window that is fully scrollable through a typical 24-hour dataset. Let me know if you want a complete minimal `eframe` example, down-sampling code, or help with the data-collection thread!
