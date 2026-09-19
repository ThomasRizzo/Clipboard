---
name: embassy-pio
description: Embassy-rs PIO on RP2040/RP2350 — pio_asm!, StateMachine, DMA/IRQ, pio_programs, and official examples/rp235x links. Use when writing Embassy firmware that uses PIO.
---
# Embassy PIO (embassy-rp)

Reference for Embassy’s PIO stack on RP2040 / RP2350. Prefer docs for your pinned `embassy-rp` version (e.g. https://docs.embassy.dev/embassy-rp/).

## Crate map

| Crate | Role |
|-------|------|
| **`pio`** (crates.io, prefer **0.3**) | Core assembler types: `Program`, `ProgramWithDefines`, `Assembler`, instruction builders. Used at compile time and runtime. |
| **`pio_proc`** | Legacy proc-macro crate providing `pio_asm!`. **Do not add separately** in modern Embassy apps — Embassy re-exports the macro. |
| **`pio-rs`** | Informal name for the `rp-rs` / `pio` ecosystem; the published crate is **`pio`**. |
| **`embassy-rp`** | HAL: `Pio`, `Common`, `Config`, `StateMachine`, `Pin`, `Irq`, FIFO TX/RX, DMA helpers, and `pio_programs::*` drivers. |
| Re-export path | `embassy_rp::pio::program::{pio_asm, pio_file, …}` and types from `pio`. |

Cargo pattern (typical):

```toml
embassy-rp = { version = "0.x", features = ["rp2040"] } # or rp235xa / rp235xb
# pio is pulled transitively; pin `pio = "0.3"` only if you call Assembler yourself
```

## Mental model

1. **PIO block** (`PIO0` / `PIO1`, RP2350 also `PIO2`) owns instruction memory (~32 instr) and 4 state machines.
2. **`Pio::new(periph)`** → `(Common, Sm0, Sm1, Sm2, Sm3, Irq)`.
3. Assemble a **`Program`** (`pio_asm!` or `Assembler`).
4. **`common.load_program(&prog)`** → `LoadedProgram` (instruction memory allocation).
5. Build **`Config`**: clock divider, pin mappings, shift/FIFO, wrap/sideset from the loaded program.
6. **`sm.set_config(&cfg)`**, set pin dirs/levels, **`sm.set_enable(true)`**.
7. Feed data via **`sm.tx()` / `sm.rx()`** (async wait or DMA).

## Assembling programs

### Compile-time: `pio_asm!`

```rust
use embassy_rp::pio::program::pio_asm;

let prog = pio_asm!(
    ".wrap_target",
    "    out pins, 1",
    "    nop [1]",
    ".wrap",
);
// prog.program : Program<32>
```

- Supports labels, `.wrap` / `.wrap_target`, `.side_set`, defines.
- Output is a `ProgramWithDefines` (or equivalent); use `.program` for `load_program`.

### File include: `pio_file!`

Same crate path; assemble from a `.pio` source file at compile time when you want C-SDK-style sources.

### Runtime: `pio::Assembler`

```rust
use pio::{Assembler, SideSet};

let mut a = Assembler::<32>::new_with_side_set(SideSet::new(true, 1, false));
// a.push(...); a.out(...); etc.
let program = a.assemble_program();
```

Use when instruction sequences are built dynamically.

## Loading and configuring

```rust
use embassy_rp::pio::{Common, Config, Direction, FifoJoin, ShiftDirection, StateMachine};

let mut cfg = Config::default();
let loaded = common.load_program(&prog.program);
cfg.use_program(&loaded, &[]);          // or with side-set Pin refs
cfg.clock_divider = /* FixedU32<U8> */ clock_div;
cfg.set_out_pins(&out_pin);             // helpers map GPIO → PIO pin base/count
cfg.shift_out.direction = ShiftDirection::Left;
cfg.shift_out.auto_fill = true;
cfg.shift_out.threshold = 32;
cfg.fifo_join = FifoJoin::Tx;           // double TX depth when RX unused
sm.set_config(&cfg);
sm.set_pin_dirs(Direction::Out, &[&out_pin]);
sm.set_enable(true);
```

**`Common`** also: `try_load_program`, unload/free slots, IRQ flags shared across SMs.

**`Config` knobs** (names vary slightly by version): `clock_divider`, `use_program`, `set_in_pins` / `set_out_pins` / `set_set_pins` / `set_jmp_pin`, shift in/out (`direction`, `auto_fill`/`auto_push`, `threshold`), `fifo_join`, wrap from program.

## StateMachine API (high-signal)

| Area | Methods |
|---------|---------|
| Lifecycle | `set_config`, `set_enable`, `is_enabled`, `restart`, `clkdiv_restart`, `clear_fifos` |
| Pins | `set_pin_dirs`, `set_pins` (pauses SM, runs SET, restores sticky) |
| FIFO handles | `tx()`, `rx()`, `rx_tx()` |
| DMA wiring | `tx_fifo_ptr`, `rx_fifo_ptr`, `tx_treq`, `rx_treq` |
| Thresholds | `set_tx_threshold`, `set_rx_threshold`, `set_thresholds` |
| Clock | `set_clock_divider` |
| Exec | `exec_instr`, `exec_jmp`, unsafe scratch `set_x`/`get_x`/`set_y`/`get_y`, `set_pin`/`set_pindir`/`set_out_pin` |
| Status FIFO modes | `get_rxf_entry` / `set_rxf_entry` with `FifoJoin::RxAsStatus` / `RxAsControl` |

### TX / RX (async + DMA)

`StateMachineTx` / `StateMachineRx`:

- Blocking-style async: `wait_push(word)`, `wait_pull()` (await space/data).
- DMA: `dma_push(ch, buf)`, `dma_pull(ch, buf)` — uses FIFO pointer + TREQ; pair with `embassy_rp::dma`.
- Sync helpers: `try_push` / `try_pull`, fullness checks as available on your version.

Pattern for continuous streams: join FIFO to TX or RX, enable autopull/autopush, drive with DMA, keep SM enabled.

## Pin configuration helpers

- Wrap a GPIO as **`pio::Pin`** via `PioPin` / `common.make_pio_pin(gpio)` (name per version).
- **`Config::set_*_pins`**: maps consecutive GPIO bases and counts into SM pin ctrl registers (OUT/SET/IN/sideset).
- **`StateMachine::set_pin_dirs` / `set_pins`**: safe init of direction and idle levels before enable.
- Side-set pins passed into `use_program(&loaded, &[side_pin])`.

Always configure dirs **before** `set_enable(true)` for output protocols.

## IRQ integration

- `Pio::new` yields **`Irq`** (or `IrqFlags`) shared by the block.
- PIO instruction `irq` / `wait irq` raises flags; Embassy exposes **`irq.wait(n)`** (async) and clear/status helpers.
- Use for frame sync (e.g. end-of-transfer), SM-to-CPU handshake, or coordinating two SMs — not for per-bit data (use FIFO/DMA for that).

## DMA integration

1. Ensure autopull (TX) or autopush (RX) + correct threshold.
2. Optional `FifoJoin::Tx` or `::Rx` for 8-deep FIFO.
3. `sm.tx().dma_push(dma_ch, &buf).await` or `sm.rx().dma_pull(...)`.
4. Or raw: `Transfer` with `sm.tx_fifo_ptr()` / `tx_treq()` if writing custom DMA loops.

Word size is typically `u32` FIFO entries; pack protocol bits in software or in the PIO program (`out` width).

## Built-in `embassy_rp::pio_programs`

Ready-made wrappers (load program + config + SM):

| Module | Use |
|------|-----|
| `ws2812` | Addressable LED timing (GRB bitstream) |
| `i2s` | I2S audio in/out |
| `spi` | PIO SPI (bitbang-class, flexible pins) |
| `uart` | PIO UART TX/RX |
| `pwm` | Extra PWM via PIO |
| `clk` / `clock_divider` | Clock generation / division |
| `onewire` | 1-Wire |
| `ir_nec` | NEC IR |
| `hd44780` | Character LCD |
| `rotary_encoder` | Quadrature decode |
| `stepper` / `step_dir` | Stepper / step-dir motion |

Prefer these before hand-rolling when they match the protocol. Read the module for exact constructor signatures (`new(common, sm, pin, clock, dma?)`).

## Common patterns

### WS2812

Use `pio_programs::ws2812` or copy its `pio_asm` + clock divider from sysclk so T0H/T1H match datasheet. Push GRB `u32` (often left-aligned 24-bit) via TX DMA; latch with >50 µs idle after the buffer.

### I2S

`pio_programs::i2s`: BCLK/LRCK/DOUT (or DIN) pin groups, clock_div from sample rate × bits × channels. Continuous `dma_push`/`dma_pull` with double-buffering.

### SPI bitbang / soft SPI

`pio_programs::spi`: useful when hardware SPI pins are exhausted or need non-standard mode. CPOL/CPHA encoded in program + sideset for SCK; MOSI via `out pins`, MISO via `in pins`.

### Custom protocol checklist

1. Write / steal `.pio` timing diagram → `pio_asm!`.
2. Size program ≤ remaining instruction memory (share one `LoadedProgram` across SMs if identical).
3. Pick clock_div: `sysclk / (desired_sm_clk)` as `FixedU32<U8>` (8 fractional bits).
4. Map SET/OUT/IN/sideset bases; set dirs.
5. Autopull/autopush thresholds match `out`/`in` bit counts.
6. IRQ only for rare events; DMA for bulk.

## RP2040 vs RP2350

- Same Embassy API surface (`embassy_rp::pio`); enable the right chip feature.
- RP2350: more PIO blocks / instructions in some configs — still treat instruction RAM as scarce; check `load_program` errors.
- PIO ISA is largely compatible; verify sideset and `mov` variants against the datasheet for the chip you target.

## Official Embassy examples (RP2350 / `examples/rp235x`)

Live tree on `main`: https://github.com/embassy-rs/embassy/tree/main/examples/rp235x/src/bin

Verified against `embassy-rs/embassy` `main` (directory listing + file headers). Prefer these over the RP2040 `examples/rp` twins when targeting RP2350.

| Example | What it demonstrates |
|---------|----------------------|
| [pio_async.rs](https://github.com/embassy-rs/embassy/blob/main/examples/rp235x/src/bin/pio_async.rs) | Raw `pio_asm!`, `Common`/`Config`/`StateMachine`, autopull serial OUT, multi-SM async tasks + IRQ wait |
| [pio_dma.rs](https://github.com/embassy-rs/embassy/blob/main/examples/rp235x/src/bin/pio_dma.rs) | PIO ↔ DMA loopback (`dma_push`/`dma_pull` style), shift config, joined FIFO throughput |
| [pio_ws2812.rs](https://github.com/embassy-rs/embassy/blob/main/examples/rp235x/src/bin/pio_ws2812.rs) | `pio_programs::ws2812` + DMA rainbow on a LED strip |
| [pio_i2s.rs](https://github.com/embassy-rs/embassy/blob/main/examples/rp235x/src/bin/pio_i2s.rs) | `PioI2sOut` / `PioI2sOutProgram` — DAC TX at 48 kHz / 16-bit with DMA |
| [pio_i2s_rx.rs](https://github.com/embassy-rs/embassy/blob/main/examples/rp235x/src/bin/pio_i2s_rx.rs) | `PioI2sIn` — mic/ADC RX, L/R buffers, pull-down caveat note for RP2350 boards |
| [pio_uart.rs](https://github.com/embassy-rs/embassy/blob/main/examples/rp235x/src/bin/pio_uart.rs) | Duplex `PioUartTx`/`PioUartRx` bridged to USB CDC ACM |
| [pio_pwm.rs](https://github.com/embassy-rs/embassy/blob/main/examples/rp235x/src/bin/pio_pwm.rs) | `PioPwm` / `PioPwmProgram` basic PWM via PIO |
| [pio_servo.rs](https://github.com/embassy-rs/embassy/blob/main/examples/rp235x/src/bin/pio_servo.rs) | Servo pulse builder on top of `PioPwm` (1–2 ms / 20 ms frame) |
| [pio_hd44780.rs](https://github.com/embassy-rs/embassy/blob/main/examples/rp235x/src/bin/pio_hd44780.rs) | HD44780 character LCD via `pio_programs::hd44780` + DMA (+ bias PWM) |
| [pio_ir_nec.rs](https://github.com/embassy-rs/embassy/blob/main/examples/rp235x/src/bin/pio_ir_nec.rs) | NEC IR TX + RX (`PioIrNecTx`/`PioIrNecRx`), multi-SM |
| [pio_onewire.rs](https://github.com/embassy-rs/embassy/blob/main/examples/rp235x/src/bin/pio_onewire.rs) | 1-Wire search + DS18B20 (externally powered) |
| [pio_onewire_parasite.rs](https://github.com/embassy-rs/embassy/blob/main/examples/rp235x/src/bin/pio_onewire_parasite.rs) | Same stack in parasite-power mode |
| [pio_rotary_encoder.rs](https://github.com/embassy-rs/embassy/blob/main/examples/rp235x/src/bin/pio_rotary_encoder.rs) | Quadrature decode via `pio_programs::rotary_encoder` |
| [pio_rotary_encoder_rxf.rs](https://github.com/embassy-rs/embassy/blob/main/examples/rp235x/src/bin/pio_rotary_encoder_rxf.rs) | Custom `pio_asm!` encoder using **RX FIFO as status** (`FifoJoin` RX-as-status) — RP2350-flavored pattern |
| [pio_stepper.rs](https://github.com/embassy-rs/embassy/blob/main/examples/rp235x/src/bin/pio_stepper.rs) | 5-wire stepper (`PioStepper`), full/half step, cancel-by-drop |
| [pio_step_dir.rs](https://github.com/embassy-rs/embassy/blob/main/examples/rp235x/src/bin/pio_step_dir.rs) | STEP/DIR driver (`PioStepDir`), pulse timing + IRQ pacing |

**Also useful (RP2040 tree, same patterns):** https://github.com/embassy-rs/embassy/tree/main/examples/rp/src/bin — includes `pio_spi.rs` / `pio_spi_async.rs` and `pio_clk.rs` which are **not** present under `rp235x` at the time of writing; port by swapping the `examples/rp235x` board crate.

**Wrappers source of truth:** https://github.com/embassy-rs/embassy/tree/main/embassy-rp/src/pio_programs

## Debugging tips

- If SM “runs but no edges”: clock_div too slow/fast, wrong pin base, or dirs not set.
- FIFO stall: autopull off or threshold ≠ bits per `out`.
- `load_program` fail: instruction memory full — unload unused programs or shrink ASM.
- Use `get_addr()` and `exec_instr` only when SM is stopped or in a known wait; arbitrary exec can desync wrap.

## Relates to

Pair with low-level PIO ISA knowledge (RP2350/RP2040 PIO programming notes) for instruction-level timing; this skill covers **Embassy’s Rust API and crate layout**.
