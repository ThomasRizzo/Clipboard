---
name: rp2350-pio-programming
description: Dense RP2350 PIO ISA quirks reference from the datasheet — use when writing or debugging PIO assembly (JMP/WAIT/IN/OUT/PUSH/PULL/MOV/IRQ/SET, sideset, wrap, autopull/push, FIFO, stalls, EXEC).
---
# RP2350 PIO Programming

Dense quirk/edge-case reference for writing `.pio` against RP2350. Prefer this over skimming Ch.11 when something “should work.”

**Source:** RP2350 Datasheet Chapter 11, build-date 2025-07-29  
**Scope:** Non-obvious behaviour, encoding traps, stall/side-set/autopull races, RP2350 deltas vs RP2040.

---

## 0. Mental model (30 seconds)

- 3 PIO blocks × 4 SMs; shared 32-instruction IMEM (1W/4R). §11.1
- Every instruction: **1 SM cycle** base + optional delay (0–31) + possible **stall**. Delay starts **after** the instruction completes (including after a stall clears). §11.2.2, §11.2.5
- **Side-set always fires on cycle 1** of the instruction — even while stalled. §11.2.5, §11.5.1
- Five independent pin map groups: **OUT / IN / SET / side-set / JMP pin**. Ranges may overlap. §11.2.6
- Shift counters (OSR/ISR) are first-class: autopull/push, `PULL IFEMPTY` / `PUSH IFFULL`, `JMP !OSRE` all key off them. §11.2.4.2, §11.5.4

---

## 1. RP2350 vs RP2040 (§11.1.1)

### New registers / controls
|| Feature | Gotcha |
|---|---|
| `DBG_CFGINFO.VERSION` = 1 (was reserved-0) | Runtime PIO feature detect |
| `GPIOBASE` | Still only **32 GPIOs visible per PIO**; base selects which window |
| `CTRL.NEXT_PIO_MASK` / `PREV_PIO_MASK` + `NEXTPREV_*` | Cross-PIO SM enable/disable + `CLKDIV_RESTART` |
| `SHIFTCTRL.IN_COUNT` | Masks unused IN bits to 0 (esp. `MOV x, PINS`) |
| IRQ0/1_INTE | **All 8** SM IRQ flags → system IRQs (RP2040: lower 4 only) |
| `RXFx_PUTGETy` | Random access to RX FIFO storage |
| `FJOIN_RX_PUT` / `FJOIN_RX_GET` | Soft status/control regs; both set → SM-only scratch, **no system access** |

### New instruction features
- `WAIT jmppin (+0..3)` — WAIT on JMP-pin map + offset, independent of IN map
- `MOV PINDIRS, src` — bulk direction change (`NULL` / `~NULL`)
- `MOV x, STATUS` can source **SM IRQ flags** (not just FIFO levels)
- IRQ/WAIT IdxMode **PREV/NEXT** — cross-PIO IRQ, **no delay penalty** (visible next cycle)
- `MOV rxfifo[y|idx], isr` (put) / `MOV osr, rxfifo[y|idx]` (get)

### Security / misc
- Non-secure PIO sees only Non-secure GPIOs (Secure GPIO read → 0)
- Cross-PIO IRQ / CTRL_NEXTPREV **severed** across Secure ↔ Non-secure PIO
- 2 → **3** PIO blocks (8 → 12 SMs); better GPIO I/O delay/skew; DREQ latency −1 cycle

---

## 2. Instruction encoding cheat (§11.4.1)

16-bit instructions. Bits 12:8 = **Delay/side-set** (budget shared: up to 5 bits total).

|| Op | 15:13 | Notes |
|---|---|---|
| JMP | `000` | Cond[7:5] Addr[4:0] |
| WAIT | `001` | Pol[7] Src[6:5] Index[4:0] |
| IN | `010` | Src[7:5] Bitcount[4:0] (**0 = 32**) |
| OUT | `011` | Dst[7:5] Bitcount[4:0] (**0 = 32**) |
| PUSH | `100` + bit7=0, bit4=0 | IfF[6] Blk[5] |
| PULL | `100` + bit7=1, bit4=0 | IfE[6] Blk[5] |
| MOV→RX (put) | `100` + `0xx1x` | Needs `FJOIN_RX_PUT` |
| MOV←RX (get) | `100` + `1xx1x` | Needs `FJOIN_RX_GET` |
| MOV | `101` | Dst[7:5] Op[4:3] Src[2:0] |
| IRQ | `110` | Clr[6] Wait[5] IdxMode[4:3] Index[2:0] |
| SET | `111` | Dst[7:5] Data[4:0] |

**Gotcha:** PUSH/PULL and the RP2350 RX FIFO MOV encodings share the `100` major opcode; distinguished by mid-field bits. Wrong assembler / hand encoding → silent wrong instruction.

## 3. Per-instruction quirks

### 3.1 JMP (§11.4.2)

**Encoding:** Cond[2:0] + absolute 5-bit address in IMEM.

|| Cond | Meaning | Gotcha |
|---|---|---|
| `000` | Always | |
| `001` | `!X` | X == 0 |
| `010` | `X--` | Branch if **pre-decrement** X ≠ 0; **always decrements** (even if X was 0 → wraps to 0xFFFFFFFF) |
| `011` | `!Y` | |
| `100` | `Y--` | Same as X-- |
| `101` | `X!=Y` | |
| `110` | `PIN` | Level of `EXECCTRL_JMP_PIN` (high → taken). **Independent of IN map** |
| `111` | `!OSRE` | Bits shifted since last PULL **vs** `PULL_THRESH` (same thresh as autopull) |

**Gotchas**
- Delay on JMP **always runs**, taken or not; delay is **after** condition eval + PC update. §11.4.2.2
- Address is **absolute IMEM** — relocating a program requires rewriting JMPs (SDK does this; **OUT EXEC / hand-encoded JMPs do not**). §11.4.2.3
- `X--`/`Y--` with X=0: decrement still happens → long countdown if you loop on it by mistake
- Side-set on a not-taken JMP still applies (first cycle)

### 3.2 WAIT (§11.4.3)

Stall until Polarity matches Source[Index].

|| Source | Index meaning | Gotcha |
|---|---|---|
| `00` GPIO | Absolute GPIO # | **Ignores** IN map / `GPIOBASE` window caveats — absolute in SM-visible space |
| `01` PIN | IN_BASE + Index (mod 32) | Uses IN mapping |
| `10` IRQ | IdxMode decode (see IRQ) | **WAIT 1 IRQ x clears the flag** when condition met |
| `11` JMPPIN | JMP_PIN + (0..3), mod 32 | RP2350; other Index values reserved |

**Gotchas**
- Delay does **not** start until wait completes. §11.4.3.2
- Side-set still asserts on the **first** stall cycle (and stays — pins don’t re-toggle each stall cycle; level already set). §11.2.5, §11.4.3.2
- **CAUTION:** `WAIT 1 IRQ x` must **not** use flags that are also routed to the NVIC — race with ISR clearing. §11.4.3.2
- IRQ index decode matches IRQ instruction: DIRECT / PREV / REL / NEXT (§11.4.3.2, §11.4.11)
- REL: SM_ID added to Index[1:0] mod 4; **bit 2 of Index unchanged** — two banks of 4 relative flags

### 3.3 IN (§11.4.4)

Shift `Bit count` bits from Source into ISR; ISR shift count += count (sat 32).

|| Source | Notes |
|---|---|
| PINS | IN map; always takes **LSBs of mapped bus**, bit order **independent of shift direction** |
| X / Y / NULL / ISR / OSR | NULL useful to right-align after LSB-first serial IN |
| Reserved | 100, 101 |

**Gotchas**
- Bit count **1..32; 00000 encodes 32**. §11.4.4.2
- Autopush: if count ≥ `PUSH_THRESH`, push+clear ISR+clear count in **same cycle**; stall if RX full. IN still “one cycle” when not stalled. §11.4.4.2, §11.5.4.1
- After right-shift UART RX: data sits in ISR[31:24] → either `IN NULL, 24` or **byte-read FIFO+3**. §11.4.4.2, §11.6.4
- `IN_COUNT` (RP2350): pins beyond count forced 0 on IN/MOV PINS/WAIT PIN. Register 0 means… check SDK; field is 5-bit width of unmasked pins. §11.1.1, SHIFTCTRL

### 3.4 OUT (§11.4.5)

Shift `Bit count` out of OSR → Destination; OSR count += count (sat 32). OSR fills with 0s as bits leave.

|| Dest | Gotcha |
|---|---|
| PINS / PINDIRS | OUT map |
| X / Y / NULL | NULL discards (still advances count — useful flush) |
| PC | Unconditional jump to shifted address |
| ISR | Also **sets ISR shift counter = Bit count** (not 0!) |
| EXEC | Execute shifted data as instruction **next cycle** |

**Gotchas**
- Bit count **1..32; 0 encodes 32**. §11.4.5.2
- Value written: lower Bit count bits from OSR (right-shift) or MSBs (left-shift); **upper bits of destination write are 0**. §11.4.5.2
- Autopull stall if OSR already at threshold and TX empty — see §5. §11.5.4.2
- **OUT EXEC:** OUT takes 1 cycle; executee next cycle. **Delay on the OUT is ignored**; executee may delay. No restriction on executee type. §11.4.5.2
- Only **one OUT** can be in flight per cycle — nested OUT-from-EXEC is one OUT. §11.5.7

### 3.5 PUSH (§11.4.6)

ISR → RX FIFO (32-bit); clear ISR to 0; clear ISR shift count.

|| Flag | Default (asm) | Behaviour |
|---|---|---|
| IfFull | off | If 1: no-op unless ISR count ≥ `PUSH_THRESH` |
| Block | **on** | If 1: stall on RX full. If 0: **don’t stall**; ISR still cleared; `FDEBUG_RXSTALL` set; FIFO unchanged (data lost) |

**Gotchas**
- Non-blocking full push = **silent data loss** + sticky debug flag. §11.4.6.2
- **Undefined** if `FJOIN_RX_PUT` or `FJOIN_RX_GET` set — use put/get MOV instead. §11.4.6.2
- Autopush must also be off in those modes. §11.5.4.1

### 3.6 PULL (§11.4.7)

TX FIFO → OSR; clears OSR shift count on success.

|| Flag | Default | Behaviour |
|---|---|---|
| IfEmpty | off | If 1: no-op unless OSR count ≥ `PULL_THRESH` |
| Block | **on** | If 1: stall on TX empty. If 0: **copy X → OSR** |

**Gotchas**
- Non-blocking empty pull ≡ `MOV OSR, X`. Pattern: preload X, or `MOV X, OSR` after each noblock pull to recycle last word (I2S). §11.4.7.2
- **With autopull enabled: PULL is a no-op if OSR is full** (fence vs DMA race). To discard OSR: `OUT NULL, 32`. §11.4.7.2, §11.5.4.2
- `PULL IFEMPTY` relocates the stall vs autopull-on-OUT (SPI clock-idle polarity). §11.5.4

### 3.7 MOV (general) (§11.4.10)

Copy Source → Destination with optional `~` / `::` (bit-reverse).

|| Dest | Side effect |
|---|---|
| PINS / PINDIRS | OUT map. **PINDIRS dest = RP2350 only** |
| X / Y | |
| EXEC | Like OUT EXEC: MOV 1 cycle, executee next; **MOV delay ignored** |
| PC | Unconditional jump |
| ISR | **ISR shift count ← 0** (empty) |
| OSR | **OSR shift count ← 0** (full / “nothing shifted out”) |

|| Source | Notes |
|---|---|
| PINS | IN map, masked by `IN_COUNT` (RP2350) |
| STATUS | All-1s or all-0s per `STATUS_SEL` / `STATUS_N` |
| NULL / X / Y / ISR / OSR | |

**STATUS_SEL** (§11.7 EXECCTRL): TXLEVEL / RXLEVEL / **IRQ** (RP2350). For IRQ: `STATUS_N` selects flag; high bits select **this / PREV PIO / NEXT PIO**.

**Gotchas**
- `MOV OSR/ISR, …` clears the corresponding shift counter — interacts with autopull/push. §11.2.4.2
- With autopull: `MOV from OSR` is **undefined** (race vs DMA refill); `MOV to OSR` won’t be overwritten (counter updated) but may clobber a just-autopulled word. §11.5.4.2
- `nop` ≡ `MOV Y, Y` — vehicle for side-set/delay. §11.3.7

### 3.8 MOV RX FIFO put/get (RP2350) (§11.4.8–11.4.9)

|| Mode | Instruction | System access |
|---|---|---|
| `FJOIN_RX_PUT` only | `MOV rxfifo[y\|imm], isr` | System **read** via `RXFx_PUTGETy` (status regs) |
| `FJOIN_RX_GET` only | `MOV osr, rxfifo[y\|imm]` | System **write** (control regs) |
| Both | put + get | **No** system access; 4 scratch words for SM |
| Index | Imm (IdxI=1) or Y[1:0] (IdxI=0) | Non-zero Index with IdxI=0 = **reserved/undefined** |

**Gotchas**
- Single R/W port each — exclusive to system **or** SM. §11.4.8.2
- Setting either FJOIN_RX_* clears classic `FJOIN_TX`/`FJOIN_RX`. §11.7
- PUSH/autopush undefined in these modes

### 3.9 IRQ (§11.4.11)

Set or clear IRQ flag; optional wait-for-clear.

|| IdxMode | Meaning |
|---|---|
| `00` | This PIO, Index[2:0] |
| `01` PREV | Next-lower PIO (wrap) |
| `10` REL | Index[1:0] += SM_ID (mod 4); bit2 fixed |
| `11` NEXT | Next-higher PIO (wrap) |

**Gotchas**
- Clear=1 → Wait ignored. §11.4.11.2
- Wait=1 → Delay starts **after** flag clears. §11.4.11.2
- Cross-PIO IRQ: **observable next cycle**, no penalty. Clocks must match + `NEXTPREV_CLKDIV_RESTART` if divided. Severed across security domains. §11.1.1, §11.4.11.2
- All 8 flags can hit IRQ0/IRQ1 via INTE (RP2350). §11.1.1
- Asm aliases: `irq` / `irq set` / `irq nowait` = set no-wait; `irq wait`; `irq clear`

### 3.10 SET (§11.4.12)

5-bit immediate → PINS / PINDIRS / X / Y.

**Gotchas**
- SET X/Y: **only 5 LSBs set; upper bits cleared** → values 0..31 only. Enough for 32-iter loop. §11.4.12.2
- SET and OUT maps are **independent** — may overlap (UART start/stop via SET, data via OUT on same pin). §11.4.12.2
- Side-set vs SET/OUT same pin same cycle → **side-set wins**. §11.2.6, §11.5.1

---

## 4. Side-set (§11.5.1)

Concurrent GPIO level/dir write packed in Delay/side-set field.

**Config**
- `SIDESET_COUNT` (0..5): MSBs of delay field consumed. Count=5 → **no delay bits**. Count=0 → no side-set.
- `SIDE_EN`: steal 1 more MSB as optional enable. If clear, **every** instruction side-sets when count≠0.
- `SIDESET_BASE`, `SIDE_PINDIR` (levels vs directions)

**Gotchas**
- Stall: side-set **still applies immediately** on first cycle. Classic SPI trick: stall with clock in desired idle state. §11.2.5, §11.5.1
- Overlap with OUT/SET on same GPIO → side-set priority (per SM); across SMs: **highest-numbered SM wins** (level and direction separately). §11.2.6, §11.5.6.1
- Delay budget: optional side-set costs `count+1` bits from the 5. Max delay = `31 >> sideset_bits`.
- I2C mapping pattern: side-set→SCL, OUT→SDA, SET→SDA — arbitrary pin pair without clock-stretch wait map constraints (stretch needs SCL = SDA+1 for WAIT PIN). §11.5.1, §11.6.7

---

## 5. Autopull / Autopush (§11.5.4)

### Counters (§11.2.4.2, §11.5.4)
|| Event | OSR count | ISR count |
|---|---|---|
| Reset / `SM_RESTART` | **32** (empty/exhausted) | **0** (empty) |
| Successful PULL / autopull | 0 | — |
| Successful PUSH / autopush | — | 0 |
| `MOV OSR, …` | 0 | — |
| `MOV ISR, …` | — | 0 |
| `OUT ISR, n` | — | **n** |
| OUT / IN | += bitcount (sat 32) | += bitcount (sat 32) |

`PULL_THRESH` / `PUSH_THRESH`: register **0 means 32**. §11.7

### Autopush (§11.5.4.1)
On IN: shift → bump count → if ≥ thresh: push or **stall if RX full**. All in one cycle if no stall.

### Autopull (§11.5.4.2) — the subtle one
- **Between OUTs:** if count ≥ thresh and TX not empty → refill anytime (async to program).
- **On OUT:** if already ≥ thresh: try pull; else: stall (cannot fill empty OSR and OUT same cycle). Else: OUT, shift, bump; then opportunistic refill.
- OUT is a **data fence** — never OUTs data you didn’t put in the FIFO.
- Autopull enabled ⇒ `PULL` no-op when OSR full; `MOV from OSR` undefined.
- **Do not enable autopush** with FJOIN_RX_PUT/GET. §11.5.4.1

### Sticky empty / mid-stream disable
- After drain: OSR count returns to 32 → next OUT stalls until TX data appears (auto_push_pull example). §11.5.4 fig.50
- Disabling autopull mid-stream: leftover count/OSR state persists — explicit PULL/`OUT NULL,32`/`SM_RESTART` to sanitize
- Threshold vs program bit width: same 2-instr SPI bitbang can do 8/16/32-bit frames by only changing thresh. §11.6.1

---

## 6. Wrap (§11.5.2)

After each instruction, PC update priority:
1. If JMP and condition true → Target  
2. Else if PC == `WRAP_TOP` → `WRAP_BOTTOM`  
3. Else PC+1, or 0 if PC was 31  

**Gotchas**
- Wrap is a **free (0-cycle) unconditional jump** — no IMEM slot, no extra cycle. §11.5.2
- `.wrap_target` / `.wrap` → WRAP_BOTTOM / WRAP_TOP; defaults: start of program / after last instr. §11.3.1
- Fields are **absolute IMEM addresses** — must add load offset. §11.5.2
- JMP true **overrides** wrap at WRAP_TOP
- Odd lengths fine; wrapping at instr 31→0 is the implicit fallback if WRAP not used
- Side-set/delay on wrapped instruction behave normally

---

## 7. FIFO join modes (§11.5.3, §11.7)

|| Mode | TX | RX | Notes |
|---|---|---|---|
| Default | 4 | 4 | |
| `FJOIN_TX` | 8 | 0 | RX always FULL+EMPTY; PUSH stalls |
| `FJOIN_RX` | 0 | 8 | TX always FULL+EMPTY; PULL stalls |
| Both classic joins | 0 | 0 | Both unavailable |
| `FJOIN_RX_PUT` | 4 | repurposed | SM put; system read (unless also GET) |
| `FJOIN_RX_GET` | 4 | repurposed | SM get; system write (unless also PUT) |
| PUT+GET | 4 | SM scratch | No system RX access |

**Gotchas**
- **Changing FJOIN flushes FIFOs** — drain first. §11.5.3
- 8 deep enough for 1 word/clk DMA if no bus contention. §11.5.3
- pioasm `.fifo txput|txget|putget` — version 1 only. §11.3.1

---

## 8. Timing / cycles

|| Case | Cycles |
|---|---|
| Normal instruction | 1 |
| + delay field | +0..31 (after completion) |
| Stall (WAIT, blocking FIFO, autopull empty, autopush full, IRQ wait) | 1 + N stall; delay after clear |
| Side-set on stall | Applies on stall cycle 1 |
| `OUT EXEC` / `MOV EXEC` | 1 (setup) + 1 (executee); setup delay ignored |
| Forced `SMx_INSTR` | Immediate; **ignores delay and clkdiv**; PC does not advance unless instr changes PC |
| Cross-PIO IRQ observability | Next cycle |

**Forced INSTR caveats (§11.5.7)**
- May stall → latched; `EXECCTRL_EXEC_STALLED`. Clear via SM restart or write NOP.
- Stalling INSTR shares latch with OUT/MOV EXEC — **if using EXEC instructions, forced INSTR must not stall** (CAUTION). §11.5.7
- SM disabled: still executes INSTR writes. §11.7 SM_ENABLE

---

## 9. Clock dividers (§11.5.5, §11.7 CTRL)

- 16.8 fixed-point; divisor ∈ [1, 65536]; frac via 1st-order ΔΣ  
- `freq = clk_sys / (INT + FRAC/256)`; INT=0 with FRAC=0 → special **65536**  
- Enables SM on clock-enable pulses; SM idle when enable low; FIFOs still accessible  
- Fractional jitter bad for small INT — prefer even divisors / 1 Mbaud multiples for fast async serial.

**CLKDIV_RESTART (§11.7)**
- Restarts divider from phase 0  
- Same divisor + simultaneous restart → **lockstep** SMs  
- `SM_ENABLE` does **not** stop the divider — disable/reenable keeps sync  
- Safe to restart while running after on-the-fly divisor change  
- Cross-PIO: `NEXTPREV_CLKDIV_RESTART` + masks

---

## 10. GPIO mapping & conflicts (§11.2.6, §11.5.6)

|| Group | Base / Count | Used by |
|---|---|---|
| OUT | OUT_BASE, OUT_COUNT | OUT, MOV PINS/PINDIRS |
| SET | SET_BASE, SET_COUNT (≤5) | SET |
| IN | IN_BASE (+ IN_COUNT mask) | IN, WAIT PIN, MOV PINS |
| Side-set | SIDESET_BASE, SIDESET_COUNT | side-set |
| JMP | JMP_PIN (+0..3 WAIT) | JMP PIN, WAIT JMPPIN |

**Gotchas**
- Maps wrap mod 32 within PIO’s GPIO window (`GPIOBASE` selects window on RP2350)
- Same-cycle priority: side-set > OUT/SET (same SM); across SMs: **SM3 > SM2 > SM1 > SM0**
- No writer → pin level/dir **hold** previous value (sticky by inertia)
- `OUT_STICKY`: continuously reassert last OUT/SET. + `INLINE_OUT_EN`: enable bit in OUT data; enable=0 **deasserts** sticky write — masking vs higher-priority SMs. §11.7 EXECCTRL
- Input: 2FF synchronizers (+2 cycle latency). Bypass via `INPUT_SYNC_BYPASS` for sync protocols (SPI) — metastability risk.
- Secure GPIO from Non-secure PIO reads as 0. §11.1.1

---

## 11. IRQ system summary

- 8 flags per PIO; any SM can set/clear/wait any flag
- Uses: system IRQ (wait for ack) **or** SM↔SM sync (incl. cross-PIO)
- Relativized (`rel` / IdxMode REL): same program on multiple SMs without patching flag numbers
- `WAIT 1 IRQ` auto-clears — don’t share with NVIC-handled flags
- `IRQ_FORCE` affects PIO state (unlike INTF, which only asserts CPU IRQ line). §11.7
- `MOV STATUS` can sample IRQ (this/prev/next PIO). §11.1.1, §11.7
- SM_RESTART clears waiting-on-IRQ state. §11.7

---

## 12. SM_RESTART clears (§11.7)

Clears: ISR contents; ISR+OSR **shift counters**; delay counter; IRQ-wait state; stalled INSTR/EXEC latch; OUT_STICKY asserted write.  
**Does not clear:** OSR data, X, Y.

---

## 13. Example-derived quirk lessons (§11.6)

### SPI (§11.6.1)
- Autopull+autopush; frame size = threshold only
- CPHA0: stall on `OUT` with side-set clock **low** (side-set on stall)
- CPHA1: stall on `OUT x` with clock deasserted, then `MOV PINS, x` (MOV uses **OUT** mapping)
- CPOL via GPIO output override invert — not PIO
- Bypass MISO synchronizer for sync SPI
- Narrow FIFO access for left-justified MSB-first free via bus replication

### WS2812 (§11.6.2)
- Side-set still runs when `OUT x,1` stalls on empty (reset gap / first bit timing)
- Autopull thresh 24; software left-shift pixel `<<8` for MSB-first non-power-of-2
- Or thresh=8 + DMA byte writes (replication → both ends of OSR)

### UART TX (§11.6.3)
- Side-set optional; OUT and side-set **same pin** (data vs start/stop constants)
- Stall on `PULL` with line idle high (side-set)
- Shift right (LSB first); FIFO join TX
- clkdiv = sys / (8 × baud) for 8 cycles/bit

### UART RX (§11.6.4)
- Mini version: autopush@8; stuck-low → spam NULs
- Full: explicit PUSH only on good stop; `JMP PIN` for stop; `IRQ REL` sticky framing/break; `WAIT 1 PIN` until idle
- Dual map: IN base + JMP pin both on RX GPIO
- Right-shift → data in top byte; read `*(uint8_t*)&rxf + 3` or `IN NULL,24`

### Manchester / BMC (§11.6.5–11.6.6)
- Branch on bit via `OUT x,1` + `JMP !x`; autopull “don’t care” threshold if always shifting 1
- RX: `WAIT` resync on mid-bit transition every symbol (clock drift)
- Preload X/Y with 1/0 via `pio_sm_exec` SET; park in WAIT before enable
- BMC: dual copies of drive logic for prior line state; `PULL` blocking before enable holds idle

### I2C (§11.6.7)
- `OUT EXEC` escapes: Instr count in FIFO word embeds Start/Stop/Restart as raw instructions
- Autopull@16, autopush@8; halfword TX writes so OSR filled immediately
- Side-set pindirs → SCL; SET/OUT pindirs → SDA; OE **inverted in GPIO override** (open-drain)
- Clock stretch: `WAIT 1 PIN, 1` requires SCL = SDA+1
- NAK → `IRQ WAIT REL`; resume = drain TX + EXEC jump to wrap_bottom + clear IRQ
- `MOV ISR, NULL` after start to clear ISR count after writes

### PWM (§11.6.8)
- `PULL NOBLOCK` + `MOV X, OSR`: empty FIFO recycles last duty
- ISR as period config via forced `PULL`+`OUT ISR,32` while SM disabled
- Dual-path cycle matching (`JMP` + `NOP`) for constant loop period

### Addition (§11.6.9)
- No autopush/pull; explicit; `~(~x - y)` via `JMP x--` / `JMP y--` side effects

---

## 14. Forced / EXEC’d instructions (§11.2.2, §11.5.7)

Sources mixed freely: IMEM | `SMx_INSTR` | `MOV EXEC` | `OUT EXEC`.

|| Mechanism | Delay | Clkdiv | PC |
|---|---|---|---|
| IMEM | obeyed | obeyed | advances / wrap / jmp |
| INSTR write | **ignored** | **ignored** (runs now) | unchanged unless instr moves PC |
| MOV/OUT EXEC | setup delay ignored; executee OK | obeyed | PC frozen on executee cycle |

I2C embeds control ops in TX stream via OUT EXEC — instructions in FIFO words. §11.2.2

---

## 15. Shift-direction field of view

|| | OUT_SHIFTDIR=1 (right) | =0 (left) |
|---|---|---|
| Bits taken from OSR | LSBs | MSBs |
| Serial UART/SPI LSB-first | typical | — |
| WS2812 MSB-first | — | typical |

IN shiftdir: right ⇒ data enters from left (ISR MSB side) — UART LSB-first wire → top of ISR.

OSR fills with zeros as bits shift out; ISR shifted to make room then new bits copied into gap (wire bit order **not** flipped by shiftdir). §11.4.4.2

---

## 16. Quick “why is it broken?” checklist

1. Stall + side-set → pin already at side-set value (often desired for CLK idle).  
2. Delay not happening → still stalled, or used OUT/MOV EXEC / INSTR path (delay stripped).  
3. Autopull “missing” data → OUT of empty OSR stalls; refill can’t dual-issue with first OUT.  
4. `PULL` ignored → autopull on and OSR full (fence).  
5. `JMP X--` infinite → X started at 0 (decremented to −1).  
6. Wrap not looping → forgot offset adjust on WRAP_TOP/BOTTOM; or JMP overriding.  
7. IRQ wait never returns → flag cleared by other SM / WAIT 1 IRQ / NVIC handler race.  
8. PUT/GET nonsense → FJOIN bits wrong; PUSH still in program; autopush left on.  
9. Cross-PIO sync drifts → unmatched clkdiv or skipped `NEXTPREV_CLKDIV_RESTART`.  
10. Pin fight → lower SM overwritten by higher SM; or side-set vs OUT same cycle.  
11. Non-blocking PUSH “worked” but data gone → RX full, ISR cleared, RXSTALL set.  
12. `MOV OSR` under autopull → raced with DMA.  
13. Absolute `WAIT GPIO` vs `WAIT PIN` — wrong index space.  
14. Secure/Non-secure PIO — cross-IRQ dead; GPIO reads 0.

---

## 17. Section index (datasheet)

|| Topic | § |
|---|---|
| Overview / RP2350 changes | 11.1, 11.1.1 |
| Control flow, stall, pins, IRQ | 11.2.2–11.2.8 |
| Assembler directives | 11.3 |
| Instruction set | 11.4 |
| Side-set / wrap / FIFO join | 11.5.1–11.5.3 |
| Autopush/pull | 11.5.4 |
| Clkdiv / GPIO / synchronisers | 11.5.5–11.5.6 |
| Forced & EXEC | 11.5.7 |
| Examples | 11.6 |
| Registers (OUT_STICKY, FJOIN_*, STATUS, CLKDIV_RESTART, …) | 11.7 |

---

*End of reference. Keep open while editing `.pio`; when surprised, re-read the cited § before “fixing” the program.*