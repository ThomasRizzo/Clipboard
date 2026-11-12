# Keysight PNA-X AFR SCPI: A-model to B-model migration (for coding agents)

Instructions for agents porting Automatic Fixture Removal (AFR) code from PNA-X **A** models to **B** models. Every SCPI name below is taken from a Keysight page listed in [Sources](#sources). Do **not** invent command names. Where a fact is not confirmed in those pages, it is marked **unconfirmed** and the instrument check is given.

Researched 2026-11-12 from current Keysight help and firmware release notes.

## 1. Purpose and scope

**Purpose.** Existing code uses only the A-model AFR *functionality* (characterize a 1- or 2-sided fixture, save Touchstone files, de-embed them so the calibration plane sits at the DUT). This note tells an agent how that maps onto B-model SCPI, what must not be assumed, and how to keep the A path working.

**Instruments.**

| Family | Models (examples) | Firmware family | Last / first firmware (from Keysight release notes) |
|---|---|---|---|
| PNA-X A | N5241A, N5242A, N5244A, N5245A, N5247A (also N5249A and PNA/PNA-L N522xA / N523xA) | N52xxA | Latest in the A notes: **A.10.65.16** (32-bit, Windows 7) |
| PNA-X B | N5241B, N5242B, N5244B, N5245B, N5247B (also N5249B, N522xB, N523xB, N5264B; same firmware also runs NA5202A/04A/05A) | N52xxB | First B release **A.12.70.06**; first web release **A.12.80.07**. Current when checked: **A.20.82.01** (2026-10-06; Windows 10/11 only) |

**Option.** AFR on A models is **Option 007**. On B models it is **S93007B**. Keysight’s S93007B product page states S93007B “is equivalent to Option 007 on PNA/PNA-L/PNA-X Series A model network analyzers.” The current AFR SCPI help lists applicable models as “All with Automatic Fixture Removal Option **(S9x007A/B, 007)**.”

**Scope.** AFR characterization (`AFR:` tree) and applying the resulting fixture (AFR correction *or* Fixture Simulator de-embed). Not a general PNA-X A-to-B SCPI guide. Not PLTS (`N1930xB`) AFR, which is a different product with its own command pages.

## 2. The actual change (read this first)

Keysight did **not** publish an A-to-B AFR command *rename* table. The change is an **addition and later expansion** of a top-level `AFR:` SCPI subsystem on B firmware, plus a new Fixture Simulator “draft” API. Treating this as a 1:1 rename will produce wrong ports.

Facts from Keysight’s own “What’s New” and release notes:

1. **A.10.20** (A-model firmware): “Auto Fixture Removal” appears as a *product feature* (GUI wizard, Option 007). The A-model notes mention AFR bug fixes through A.10.x (launch failure, fixture-file save). A-model firmware **never passed A.10.65.16**.
2. **A.12.70** (first B firmware): “This firmware, and the ones listed above, will not work on ‘A’ models.”
3. **A.12.85** (B firmware, Nov 2017 What’s New): **“Automatic Fixture Removal (AFR) SCPI commands”** are introduced. Programming Commands History lists the initial `AFR:` set here (see §4). The A.12.85.04 notes also say “SCPI: Fixed numerous SCPI commands to ensure backwards compatibility with A models” — a general SCPI compatibility pass, **not** an AFR rename list.
4. Later B releases **add** AFR commands and change some behavior (A.14.80, A.15.30, A.17.00, A.19.30). They do not replace the A.12.85 names.

**Implication for A-model source code.** If the A-model program talks to a real N524xA on A.10.x firmware, it almost certainly does **not** send `AFR:` SCPI — that tree is documented as new in A.12.85, which A models never ran. Typical A-model patterns:

- Operator (or a COM/GUI helper) runs the AFR wizard and saves `.s2p` / Touchstone files; the program only **applies** those files with **legacy Fixture Simulator** SCPI (`CALC:FSIM:SEND:DEEM:PORT`, cited on the “Using Fixture Simulator” page).
- The program is already on B (or a B-firmware family instrument) and uses the A.12.85-era `AFR:` “core” set — “A functionality” in the sense of 2-port / 2X-Thru characterization, **not** the later N-port or `AFR:CORRection:` features.

**Unconfirmed:** whether any undocumented AFR remote API (COM-only, or unlisted SCPI) existed on A.10.x. Check the actual A instrument as in §3 and inventory the existing codebase as in §7 **before** rewriting anything.

## 3. Detect model and firmware at runtime

Parse `*IDN?`. A Keysight knowledge article quoting the N5245B help shows the form:

```text
*IDN?  ->  Keysight Technologies,<model>,<serial>,<firmware>
example: Keysight Technologies,N5245B,<serial>,A.15.75.22
```

| Field (1-based, comma-separated) | Use |
|---|---|
| 2. `<model>` | `N5245A` vs `N5245B` (and the other N524x / N522x / N523x A/B suffixes). Treat `NA520xA` as the **B firmware family**, not as a PNA-X A model. |
| 4. `<firmware>` | `A.major.minor.build` (e.g. `A.17.60.13`). Compare as four integers, not as strings. |

Recommended dispatch:

```
A-model path  := model matches /N52(21|22|24|25|27|31|32|34|35|39|41|42|44|45|47|49|64)A$/
                 OR firmware major.minor < 12.70
B-model path  := model matches the same stem with suffix B,
                 OR model is NA520xA,
                 OR firmware >= A.12.70
```

If `*IDN?` and the installed-firmware story disagree, **stop and ask**; do not guess.

**Option present?** The AFR help requires Option `007` or `S9x007A/B`. The exact query string is **unconfirmed** in the pages fetched for this note (`*OPT?` is IEEE 488.2 and is the usual Keysight option query, but this research did not fetch a PNA `*OPT?` page, and it is unconfirmed whether a B unit returns `007`, `S93007B`, or both). On the instrument: send `*OPT?`, and try sending `AFR:INITialize` then `SYST:ERR?`. A missing-option or undefined-header error means AFR is not licensed or the `AFR:` tree is absent.

**Other queries (use only those you can confirm on the box):**

| Query | What Keysight documents | Use |
|---|---|---|
| `SYST:ERR?` / `SYSTem:ERRor[:NEXT]?` | PNA SYSTem help, all models. Next error in the queue; `+0,"No error"` when empty. Also `SYST:ERR:COUNt?`. Queue clears on `*CLS`, power-on, or when emptied. | After **every** AFR / FSIM command while porting. |
| `CALCulate:FSIMulator:LEGacy?` | FSimulator help, all models. `TRUE` if only legacy fixture SCPI has been used; `FALSE` if the new GUI or new SCPI built a fixture. Default `TRUE`. | Before mixing de-embed styles (see §6). |
| `AFR:ADVanced:VERSion?` | AFR help; listed as **new** in A.19.30.xx. Returns a string. | AFR algorithm / UI version on new-enough B firmware. Expect an error on older B and on A. |
| `SYSTem:PRESet` | SYSTem help. Factory preset (not User Preset). Same as `*RST` except it does **not** reset `CALC:FORMAT` to ASCII. | Wipes the instrument. Do not use as a lightweight AFR reset; use `AFR:INITialize` or `AFR:ADVanced:RESet` for AFR only (A.14.80+ for `RESet`). |

**Unconfirmed on PNA** (do not assume they exist): `SYST:HELP:HEAD?`, `SYST:CAPability?` as an AFR probe. The current PNA `SYSTem` tree fetched for this note has a `CAPability` branch but no `HELP:HEADer`. If you need a command catalog, try the candidate command and read `SYST:ERR?`.

## 4. Old-to-new mapping

### 4.1 There is no A-model `AFR:` name to rename

For code that already runs on an A-model A.10.x box, the “old command” for characterization is **none in SCPI** (GUI / wizard / saved files). The “new command” on B is the `AFR:` tree, starting at A.12.85. The application path is the Fixture Simulator, which **did** change (legacy vs draft) — see §4.3 and §6.

### 4.2 `AFR:` commands by introduction (B firmware)

Sources: [Programming Commands History](https://helpfiles.keysight.com/csg/NA520xA/Programming/Programming_Commands_History.htm), [New Programming Commands](https://helpfiles.keysight.com/csg/NA520xA/Programming/New_Programming_Commands.htm), [What’s New](https://helpfiles.keysight.com/csg/NA520xA/Whats_New.htm), [N52xxB release notes](https://www.keysight.com/id/en/assets/9921-03284/release-notes/N52xxB-PNA-Firmware-Release-Notes.pdf), command details on the [AFR SCPI page](https://helpfiles.keysight.com/csg/NA520xA/Programming/GP-IB_Command_Finder/Automatic_Fixture_Removal_(AFR).htm).

**A.12.85.xx — initial AFR SCPI (core “A functionality”).** Same names still appear in current help. Parameters in the current help (cite that page for syntax):

| Command | Role (current help) | Notes for porters |
|---|---|---|
| `AFR:INITialize` | Restore default AFR settings. Write-only. | Start of every characterization sequence. |
| `AFR:FIXTure:INPuts` | `SENDed` \| `DIFFerential`. Default `SENDed`. | |
| `AFR:FIXTure:MEASurement` | Number of fixtures: **1, 2, or 4**. Default `2`. | |
| `AFR:FIXTure:CMATch[:STATe]` | Fixture match A ≠ B. | |
| `AFR:FIXTure:CLENgth[:STATe]` | Fixture length A ≠ B. | |
| `AFR:FIXTure:BLIMited[:STATe]` | DUT is band-limited. | |
| `AFR:FIXTure:CDUT[:STATe]` | Characterization fixture ≠ DUT measurement fixture. | Enables FDUT in the wizard. |
| `AFR:FIXTure:REFZ` | Cal reference Z0 after removal: `SYSZ`, `MEAZ`, `CUSTom[,<num>]`. Default `SYSZ`. | |
| `AFR:FIXTure:PREView` | Refresh preview data. Required before querying gate / length / impedance preview. | Current help: send this after `EDIT:FLENgth`. |
| `AFR:FIXTure:PREView:DATA[:IMPedance]?` / `:MARKer:Y?` | Read calculated fixture impedance profile. | |
| `AFR:STANdard:USE` | Choose standards: `THRU` (2X Thru), `STHRu`, `FDUT`, `AOPen`, `BOPen`, `ASHort`, `BSHort` [, ON\|OFF]. Query returns comma-separated used list. Default `'THRU'` ON. | |
| `AFR:STANdard:ALLOpen[:STATe]` / `ALLShort[:STATe]` | Select all OPEN / all SHORT standards. | |
| `AFR:STANdard:THRU` | `KNOWn` \| `UNKNown` [, user length]. Default `"KNOW,0"`. | Known / flush / user length vs unknown computed from reflects. |
| `AFR:STANdard:LOAD` | Load a standard from a file. File: **Touchstone 1.0, Touchstone 2.0, or CITIfile**. | Use when characterizing from saved measurements (common A-model workflow). |
| `AFR:STANdard:EDIT:FLENgth` | `<AFIXture\|BFIXture>, <ns>`. | See **behavior change** in A.17.00.05 below. |
| `AFR:STANdard:EDIT:GATE` | Gate position for the selected fixture. | |
| `AFR:STANdard:EDIT:IMPedance` / `:METHod` | Impedance and method for a selected term. | |
| `AFR:STANdard:DATA[:IMPedance]?` / `:MARKer:Y?` | Impedance profile of a measured standard. | |
| `AFR:SAVE:FILename` | Fixture A path [, Fixture B path]. Example: `'C:\fixA.s2p','C:\fixB.s2p'`. Default `"C:\fixA.s2p,C:\fixB.s2p"`. | This is a **path setting** (read-write), not by itself a documented “perform the save now” verb — **unconfirmed** whether setting the path also writes the files; verify on the instrument (`SYST:ERR?`, then check the filesystem). |
| `AFR:SAVE:TYPE` | `TSONe` (Touchstone), `TSTWo` (Touchstone 2), `CITifile`. Default `TSONe`. | **No `.afr` type is documented.** |
| `AFR:SAVE:PORTs` | Port assignment format: `PLTS`, `VNA`, `ADS`. Default `VNA`. | |

**A.14.80.xx — added (History).** Also the release that introduced the “Enhanced fixture simulator GUI.”

| Command | Role |
|---|---|
| `AFR:STANdard:MEASure` | Measure a standard live. `THRU` \| `STHRu` \| `FDUT` \| `AOPen` \| `BOPen` \| `ASHort` \| `BSHort` [, optional mapped PNA ports p1..p4]. Example: `AFR:STANdard:MEASure FDUT,1,2`. **Not in the A.12.85 list** — early B firmware (A.12.85–A.14.60) has no documented SCPI to trigger a live AFR standard measurement. |
| `AFR:ADVanced:RESet` | Reset AFR configuration (distinct from `AFR:INITialize` defaults — both exist; **unconfirmed** exact difference, check both on the box). |
| `AFR:ADVanced:MCONversion[:STATe]` | AFR mode conversion on/off. Default ON. |
| `AFR:ADVanced:TIME:STARt` / `TIME:STOP` | Manual start/stop time (ns). Defaults -0.2 / 5. |
| `AFR:ADVanced:WINDow:COEFficient` | `MAXWin` \| `WIDWin` \| `NORMWin` \| `MINWin`. Default `NORMWin`. |
| `AFR:ADVanced:WINDow:MANual[:STATe]` | Manual window coefficient on/off. Default OFF. |
| `AFR:FIXTure:SET:SYSZ[:STATe]` | Set “System Z0” as Calibration Reference Z0. |
| `AFR:FIXTure:USE:THRUs[:STATe]` | Use thrus for multi-port fixtures. |
| `AFR:SAVE:IMPedance:NORMalize[:STATe]` | Normalize port impedances when saving fixture files. |

**A.15.30.xx — What’s New:** “AFR Config and 2X Thru for N port” (a **licensed** / support-contract feature; A.15.65.19 notes a bug “Unable to use support contract feature: ‘AFR Config and 2X Thru for N Port’”) and “Updates to Fixture Simulator.” The `AFR:STANdard:NPORt:*` commands in current help (`LOAD`, `LOAD:FDUT`, `MEASure`, `MEASure:FDUT`, `USE`, `USE:CATalog?`) match this feature. **Unconfirmed** that A.15.30 is exactly when those SCPI names appeared (they are absent from Programming Commands History and from “New Programming Commands” A.16.20–A.20.80). Do not use N-port AFR SCPI unless the B unit has that license and `SYST:ERR?` stays clean.

**A.17.00.05 (3 May 2023) — behavior change, same command name.** Release notes: “AFR – Updated the SCPI command `AFR:STANdard:EDIT:FLENgth` to support 2X thru.” Current help text: “For the selected fixture, this command **reads** the fixture length for both 1X or 2X AFR, or **sets** the fixture length for 1X AFR.” History’s A.12.85 blurb had said “for 1X AFR only.” After a set, send `AFR:FIXTure:PREView`. If porting code that *sets* length on a 2X-Thru setup, verify on firmware ≥ A.17.00.05 and on older B; do not assume a set works for 2X on every revision.

**A.19.30.xx — What’s New: “Automatic Fixture Removal 2025 updates.”** New Programming Commands lists (among others): `AFR:ADVanced:DUTGate:DOMain`, `DUTGate:ILFitting:MANual[:STATe]`, `FIXTure:IMPedance:FTUNe[:STATe]`, `AUTO:ITERate:METHod:CHECk[:STATe]`, `AUTO:ITERate:REFZ:SET[:STATe]`, `AFR:ADVanced:VERSion?`, `REFLection:GATing:MODE` (and `:CUSTom:POSition`, `:MINimum:NVALue`), `REFLection:GATing:SPIKe:TOLerance`, `REFLection:ILFitting:LOW|HIGH:STARt|STOP|MCENter|MSPan`. These are **B-only later firmware**. They are not required to reproduce A-model 2-port AFR. Leave them alone unless the user asks for the 2025 behavior.

### 4.3 Applying the fixture (this is the real A-to-B SCPI change)

| A-model / legacy (still valid on B if the fixture was built only with legacy SCPI) | B recommended (firmware A.14.40+ “new fixture generator”) | Parameter / behavior notes | Source |
|---|---|---|---|
| `CALC:FSIM:SEND:DEEM:PORT` (legacy-specific; full sub-tree not re-listed on the overview page) | `CALC:FSIM:DRAFt:CIRCuit<n>:ADD FIL,<fixt_ports>` then `:VNA:PORTs`, `:EMBed:TYPE DEEM`, `:FILE "<path>"`, `:STATe ON`, optional `:FILE:EXTRapolate` | “In many cases, `CALC:FSIM:DRAF:CIRC` can replace the legacy-specific SCPI such as `CALC:FSIM:SEND:DEEM:PORT`.” Blocks default to de-embed; send `:EMBED:TYPE EMBED` only to embed. Build **right to left**. | [Using Fixture Simulator](https://helpfiles.keysight.com/csg/NA520xA/Programming/Using_Fixture_Simulator.htm) |
| `CALC<cnum>:FSIM:SEND:DEEM:PORT<n>:SNP:REVerse ON\|OFF` (and `...:SNP:REVerse?`) — reverse the ports of the 2-port fixture file being de-embedded. Keysight marks it **Superseded**. | `CALC<cnum>:FSIM:DRAFt:CIRCuit<n>:DEVice:PORTs:REVerse ON\|OFF` (short: `CALC:FSIM:DRAF:CIRC:DEV:PORT:REV ON`). Read back the active fixture with `CALC<cnum>:FSIM:CIRCuit<n>:DEVice:PORTs:REVerse?` (read-only). | Boolean, `ON`/`1` reverses and `OFF`/`0` does not. Help text: “Sets whether or not to reverse the ports on an existing S2P file.” Set it on the draft circuit **after** `:FILE` and **before** `CALC:FSIM:APPLy`. For more than 2 ports, use `CALC:FSIM:DRAFt:CIRCuit<n>:DEVice:PORTs <list>` (an even count matching the fixture ports), which “can be used to reverse or change the order of ports in an SNP file.” Legacy `PORT<n>` is the **VNA port** number, while draft `CIRCuit<n>` is the **circuit block** number, so map them through `:VNA:PORTs` instead of copying the index. | [FSimulatorSend (legacy, Superseded)](https://helpfiles.keysight.com/csg/NA520xA/Programming/GP-IB_Command_Finder/Calculate/FSimulatorSend.htm); [FSimulatorDraft](https://helpfiles.keysight.com/csg/NA520xA/Programming/GP-IB_Command_Finder/Calculate/FSimulatorDraft.htm); [FSimulatorActive](https://helpfiles.keysight.com/csg/NA520xA/Programming/GP-IB_Command_Finder/Calculate/FSimulatorActive.htm) |
| `CALC:FSIM:APPLy` | **Same command** (`CALC:FSIM:APPLy`) — documented as an exception that is “same as legacy.” Validates the draft and copies it to the active fixture. | After building the draft. | same |
| `CALC:FSIM:STATe ON\|OFF` | **Same.** Turns de-embed / port matching / impedance conversion on or off for all ports on the channel. Does not affect port extensions. Default OFF. | | [FSimulator](https://helpfiles.keysight.com/csg/NA520xA/Programming/GP-IB_Command_Finder/Calculate/FSimulator.htm) |
| *(no draft discard)* | `CALC:FSIM:DRAFt:DISCard` — copies **active** fixture to the draft (discards scratch changes). Start a new build with this. | | Using Fixture Simulator |
| *(preset fixture)* | `CALC:FSIM:RESet` — preset the fixture. The official AFR example also uses `CALC:FSIM:DRAFt:CIRCuit:RESet` and `CALC:FSIM:DRAFt:CIRCuit:NEXT?`. | Exact relationship of `RESet` vs `DRAFt:CIRCuit:RESet` **unconfirmed** beyond the example and the “Preset the fixture” sentence. | Using Fixture Simulator; Keysight AFR programming-example article |
| `CALC:FSIM:SNP:EXTRapolate` | **Superseded** by `CALCulate:FSIMulator:CIRCuit:FILE:EXTrapolate` (FSimulator help). The AFR example uses `CALC:FSIM:DRAFt:CIRCuit<n>:FILE:EXTRapolate`. | Do not add a second extrapolation style; pick one and `SYST:ERR?`. | FSimulator help (“Superseded”) |
| *(no AFR-native apply)* | `AFR:CORRection:APPLy` — apply AFR correction after characterization is complete. Optional targeting: `AFR:CORRection:METHod CHAN\|CSET` (default `CHANnel`); `AFR:CORRection:CHANnel "<1,2>"` (empty = active channel); `AFR:CORRection:CSET "..."`; `:CSET:CATalog?`, `:CHANnel:CATalog?`; `:CSET:NEW`, `:CSET:NEW:NAME`, `:CSET:OTHers`; `:PORT`, `:PORT:APPLy`; `:EXTRapolate`; `:PCOMpensate`; `:UNDo`. Then optional `AFR:SAVE:DUT <file>,<chan>` to save fixture-corrected DUT S-parameters. | **Introduction firmware unconfirmed** (not in History A.12.85 / A.14.80, not in New Commands A.16.20–A.20.80). Verify with `SYST:ERR?` on the target B revision. Not a drop-in for legacy FSIM if other fixture blocks already exist — **unconfirmed** interaction. | AFR SCPI page |

**Incompatibility (critical).** From Using Fixture Simulator, firmware A.14.40+: “Legacy SCPI commands will continue to work, but they are incompatible with the new features. There will be an error if legacy SCPI commands are sent **after** new SCPI commands are sent and/or **after** the new GUI is used to build the fixture.” A.15.40.08 release notes: “AFR: Fix error of ‘Cannot send legacy fixture commands’.” Query `CALC:FSIM:LEGacy?` before choosing a path. **Do not mix.**

**Official B-model sequence** (Keysight knowledge article, tested on PNA **N5222B** firmware **A.17.60.13** and ENA-X E5081A A.19.00.09; Command Expert 2022). Live fetch of that page was Cloudflare-blocked on 2026-11-12; the sequence below is the article’s published command list, and every `AFR:` / `CALC:FSIM:` name also appears on the help pages cited above:

```text
:SYSTem:PRESet
:AFR:INITialize
:AFR:FIXTure:INPuts SENDed
:AFR:FIXTure:MEASurement 2
:AFR:FIXTure:CMATch:STATe 1
:AFR:FIXTure:CLENgth:STATe 1
:AFR:FIXTure:BLIMited:STATe 1        ! only if the DUT is band limited
:AFR:FIXTure:CDUT:STATe 1            ! only if char. fixture ≠ DUT fixture
:AFR:STANdard:USE THRU
:AFR:STANdard:USE STHRu              ! if a second 2X Thru is used
:AFR:STANdard:USE FDUT               ! if CDUT is on
:AFR:STANdard:MEASure THRU           ! A.14.80+
:AFR:STANdard:MEASure STHRu
:AFR:STANdard:MEASure FDUT,1,2
:AFR:SAVE:FILename "D:\fixA.s2p","D:\fixB.s2p"
:CALCulate:FSIMulator:DRAFt:DISCard
:CALCulate:FSIMulator:DRAFt:CIRCuit:RESet
:CALCulate:FSIMulator:DRAFt:CIRCuit:NEXT?     ! returns a free circuit number
:CALCulate:FSIMulator:DRAFt:CIRCuit1:ADD FIL,2
:CALCulate:FSIMulator:DRAFt:CIRCuit1:VNA:PORTs 1
:CALCulate:FSIMulator:DRAFt:CIRCuit1:EMBed:TYPE DEEM
:CALCulate:FSIMulator:DRAFt:CIRCuit1:FILE "D:\fixA.s2p"
:CALCulate:FSIMulator:DRAFt:CIRCuit1:STATe 1
:CALCulate:FSIMulator:DRAFt:CIRCuit1:FILE:EXTRapolate 1
:CALCulate:FSIMulator:DRAFt:CIRCuit:NEXT?
:CALCulate:FSIMulator:DRAFt:CIRCuit2:ADD FIL,2
:CALCulate:FSIMulator:DRAFt:CIRCuit2:VNA:PORTs 2
:CALCulate:FSIMulator:DRAFt:CIRCuit2:FILE "D:\fixB.s2p"
:CALCulate:FSIMulator:DRAFt:CIRCuit2:STATe 1
:CALCulate:FSIMulator:DRAFt:CIRCuit2:FILE:EXTRapolate 1
:CALCulate:FSIMulator:APPLy
:CALCulate:FSIMulator:STATe 1
```

Calibrate at the fixture connectors *before* AFR (AFR UI help). Fixture characterization must be finished before `AFR:CORRection:APPLy`.

### 4.4 Unchanged (same name, still in current help)

- All A.12.85 `AFR:` names in §4.2 — **not renamed** on B. Use them for A-equivalent functionality.
- `CALC:FSIM:APPLy`, `CALC:FSIM:STATe` — same names; `APPLy` is explicitly “same as legacy.”
- Legacy `CALC:FSIM:SEND:DEEM:PORT` — still works **until** new FSIM SCPI or the new fixture GUI is used.

### 4.5 Reading back the full de-embedding configuration (B model)

Use this to capture the fixture setup that is currently on the instrument, for logging, auditing, or rebuilding it later. Every query below is listed on Keysight's [FSimulatorActive](https://helpfiles.keysight.com/csg/NA520xA/Programming/GP-IB_Command_Finder/Calculate/FSimulatorActive.htm) page (the **active**, applied fixture, all read-only) or the [FSimulatorDraft](https://helpfiles.keysight.com/csg/NA520xA/Programming/GP-IB_Command_Finder/Calculate/FSimulatorDraft.htm) page (the **draft**, the unapplied scratch copy).

**Active vs draft.** Read the **active** tree (`CALC<cnum>:FSIM:CIRCuit<circN>:...?`) to see what is actually being applied to measurements. Most draft queries mirror it with `:DRAFt:` inserted (`CALC<cnum>:FSIM:DRAFt:CIRCuit<circN>:...?`). The draft only matches the active fixture after `CALC:FSIM:APPLy`, or after `CALC:FSIM:DRAFt:DISCard`, which copies active into draft. To read the draft without accidentally losing unapplied edits, do not send `DISCard`.

**Step 0: which command family is in use.**

| Query | Returns | Notes |
|---|---|---|
| `CALC<cnum>:FSIM:LEGacy?` | Boolean | If true, the fixture was built with the legacy `SEND:DEEM:PORT<n>` commands. Read it with the legacy queries on [FSimulatorSend](https://helpfiles.keysight.com/csg/NA520xA/Programming/GP-IB_Command_Finder/Calculate/FSimulatorSend.htm) (for example `CALC<cnum>:FSIM:SEND:DEEM:PORT<n>:SNP:REVerse?`) instead of this section. |
| `CALC<cnum>:FSIM:STATe?` | Boolean | Master on/off for de-embed, port matching, and impedance conversion on the channel. |
| `CALC<cnum>:FSIM:SECTion:CIRCuit:ENABle?` | Boolean | All circuit blocks on or off. Note that the help's query syntax line spells it `SECTionCIRCuit` with no colon, which looks like a typo; use `SECT:CIRC:ENAB?` as in its example. |
| `CALC<cnum>:FSIM:SECTion:EXTension:ENABle?` | Boolean | Port-extension section on or off. |
| `CALC<cnum>:FSIM:SECTion:ZCONversion:ENABle?` | Boolean | Impedance-conversion section on or off. |
| `CALC<cnum>:FSIM:POWer:COMPensate:MODE?` | `ALL` \| `DEEMbed` | Source-power compensation through all fixture blocks or de-embed blocks only. |

**Step 1: list the circuit blocks.**

| Query | Returns |
|---|---|
| `CALC<cnum>:FSIM:CIRCuit:CATalog?` (draft: `CALC<cnum>:FSIM:DRAFt:CIRCuit:CATalog?`) | Comma-separated string of circuit (block) numbers. |
| `CALC<cnum>:FSIM:DRAFt:CIRCuit<circN>:SECTion?` | Draft only. The circuit section the block sits in, meaning the section whose nodes its left-side connectors attach to. Use it to recover block order. |

**Step 2: for each `<circN>` in the catalog, read its settings.**

| Query (active form; insert `:DRAFt` for draft) | Returns | Valid for |
|---|---|---|
| `CALC<cnum>:FSIM:CIRCuit<circN>:STATe?` | Boolean | All blocks |
| `CALC<cnum>:FSIM:CIRCuit<circN>:EMBED:TYPE?` | `EMBed` \| `DEEMbed` | All blocks |
| `CALC<cnum>:FSIM:CIRCuit<circN>:VNA:PORTs?` | VNA port list | All blocks |
| `CALC<cnum>:FSIM:CIRCuit<circN>:DEVice:PORTs[:ARRay]?` | Device port list (in, out) | All blocks. The active page's query-syntax line shows the `:DRAFt:` form; its example shows the active form `CALC:FSIM:CIRC:DEV:PORT?`. |
| `CALC<cnum>:FSIM:CIRCuit<circN>:DEVice:PORTs:REVerse?` | Boolean, whether the S2P ports are reversed | File blocks |
| `CALC<cnum>:FSIM:CIRCuit<circN>:FILE?` | File path string | `FILe`, `D4PFile`, `FGLoop` |
| `CALC<cnum>:FSIM:CIRCuit<circN>:FILE:EXTRapolate?` | Boolean | File blocks |
| `CALC<cnum>:FSIM:CIRCuit<circN>:FILE:LABel?` | String (default `"User"`) | File blocks |
| `CALC<cnum>:FSIM:CIRCuit<circN>:FILE:MODify?` | `NONE` \| `NREFlect` \| `NXTalk` | File blocks |
| `CALC<cnum>:FSIM:CIRCuit<circN>:PARameter:{R\|L\|C\|G\|R2\|L2\|C2\|G2}?` | Numeric (ohms, henries, farads, siemens) | Lumped-element blocks, for example `SLPC`, `PCSL`, `PLSC`, `SCPL`, `PLPC`, `SCPC`, `PCSC`, `SLPL`, `PLSL`, and the `*GLoop` types |
| `CALC<cnum>:FSIM:CIRCuit<circN>:PARameter:{Z0\|DELay\|LOSS:VALue}?` | Numeric | `ILIN` (ideal line) |
| `CALC<cnum>:FSIM:CIRCuit<circN>:PARameter:{RIN\|ROUT}?` | Numeric | Blocks that use them (see the help page per parameter) |

Keysight documents that a query for a parameter the block does not use has no effect, so a dumper can query everything and keep only meaningful values. Check `SYST:ERR?` after each query on the target firmware, because whether an unused parameter returns `0` or raises an error is **unconfirmed**.

**Gap: block type.** Neither page lists a query that returns a block's type (the `<block type>` given to `CALC:FSIM:DRAFt:CIRCuit<n>:ADD`, such as `FILe` or `SLPC`). To rebuild a fixture exactly, record block types when your code creates them, or infer them from which parameters are meaningful (a non-empty `FILE?` means a file block). Confirm on the instrument whether firmware exposes a type query; Keysight's [SCPI command tree](https://helpfiles.keysight.com/csg/NA520xA/Programming/GP-IB_Command_Finder/SCPI_Command_Tree.htm) is the place to look.

**Step 3: port extensions and impedance conversion (per VNA port `<pnum>`).**

| Query (active form) | Notes |
|---|---|
| `CALC<cnum>:FSIM:EXTension:PORT<pnum>[:STATe]?` | Port extension on or off |
| `CALC<cnum>:FSIM:EXTension:PORT<pnum>:DELay?` | Seconds |
| `CALC<cnum>:FSIM:EXTension:PORT<pnum>:DISTance:VALue?`, `CALC<cnum>:FSIM:EXTension:PORT:DISTance:UNIT?` | Distance and its unit |
| `CALC<cnum>:FSIM:EXTension:PORT<pnum>:LOSS<n>[:STATe]?`, `:LOSS<n>:VALue?`, `:LOSS<n>:FREQuency?`, `:DCLoss:VALue?` | Loss model |
| `CALC<cnum>:FSIM:EXTension:PORT<pnum>:MEDium?`, `:VELocity:FACtor?`, `:VELocity:COUPle?`, `:WAVEguide:FCUToff?`, `:WAVEguide:COUPle?` | Medium and velocity |
| `CALC<cnum>:FSIM:ZCONversion:SENDed:PORt:STATe?`, `:SENDed:PORt<pnum>:COMPlex?`, `:SENDed:PORT<pnum>:SCALer?` | Single-ended impedance conversion |
| `CALC<cnum>:FSIM:ZCONversion:DIFFerential:STATe?`, `:DIFFerential:{BPORt\|LPORt}<pnum>:{COMPlex\|SCALer}?` | Differential-mode impedance |
| `CALC<cnum>:FSIM:ZCONversion:COMMonmode:{BPORt\|LPORt}<pnum>:{COMPlex\|SCALer}?` | Common-mode impedance |
| `CALC<cnum>:FSIM:COMMonmode:DIFFerential:STATe?` | Listed on FSimulatorActive |

The draft tree has the same extension and ZCONversion queries under `CALC<cnum>:FSIM:DRAFt:...` (for example `CALC<cnum>:FSIM:DRAFt:EXTension:PORT<pnum>:DELay?`). The spellings `PORt`, `SCALer` and `COMPlex` are copied from the help; SCPI is case-insensitive, so they only matter for the short form.

**Step 4 (optional): snapshot the combined fixture as data.**
- `CALC<cnum>:FSIM:SAVE "<path>"` saves an SNP file of the entire **active** fixture.
- `CALC<cnum>:FSIM:DRAFt:SAVE "<path>"` does the same for the draft.

Both append `.sNp` based on port count. This captures the combined fixture response, not the block structure, so keep it alongside the Step 1–3 dump rather than instead of it.

**Agent recipe (dump to JSON).**
1. Send `*IDN?`, then `CALC<cnum>:FSIM:LEGacy?`, then the Step 0 queries.
2. Parse `CIRCuit:CATalog?`, which is a quoted comma list that may be empty, and loop over the circuits running the Step 2 queries.
3. Loop over the VNA ports (`1..N`, using the count from the instrument) running the Step 3 queries.
4. Send `SYST:ERR?` after each query. Store any error alongside the key instead of aborting.
5. Write `{idn, firmware, channel, legacy, master_state, sections, circuits:[...], ports:[...]}`. Optionally also save the SNP from Step 4 and record its path.

To restore, replay the dump with the draft **set** commands (`ADD`, `VNA:PORTs`, `DEVice:PORTs`, `EMBED:TYPE`, `FILE`, `PARameter:*`, `STATe`), then `CALC:FSIM:APPLy` and `CALC:FSIM:STATe`. Remember the block-type gap above.

## 5. Behavioral differences (not just names)

**Calibration plane.** AFR UI help: perform a calibration at the connectors of the test fixture first; AFR then removes the fixture so displayed results are the DUT. That procedure is the same idea on A (wizard) and B (wizard or SCPI). On B, `AFR:CORRection:METHod CHAN` applies to channels (empty list = active channel) and `CSET` applies to cal sets; `AFR:CORRection:PORT` / `:PORT:APPLy` select which VNA ports receive the correction. How that interacts with an existing error-term cal set compared with FSIM de-embed is **unconfirmed** — measure a known thru / verify residual after both methods.

**De-embed flow.** A-model: wizard → Touchstone files → legacy FSIM de-embed on the chosen ports. B-model: `AFR:` characterize → `AFR:SAVE:FILename` → either (a) FSIM draft de-embed of those files, or (b) `AFR:CORRection:APPLy`. Keysight’s published programming example uses (a), not (b).

**File formats.** Documented `AFR:SAVE:TYPE` values are `TSONe`, `TSTWo`, `CITifile`. Defaults and examples use `.s2p` (two-port). `AFR:SAVE:DUT` examples use `.s4p`. `AFR:STANdard:LOAD` accepts Touchstone 1.0, 2.0, or CITIfile. **`.afr` as a save format is unconfirmed** (not in `SAVE:TYPE`). `AFR:SAVE:PORTs` chooses PLTS / VNA / ADS **port assignment**, not a different electrical model. A.19.10.06 notes an AFR “SNP formatting issue when EU format selected” (fixed).

**Port mapping.** `AFR:STANdard:MEASure` and the N-port commands take optional PNA port numbers. The 2-fixture example measures `FDUT,1,2` and de-embeds fixture A on VNA port 1, fixture B on port 2. `AFR:FIXTure:MEASurement` allows 1, 2, or 4 fixtures. Do not assume A-model port order; make mapping explicit.

**State / setup files.** The VNA State Converter (N52xxB and other current platforms) **does not support S9x007B AFR**. Do not expect an A-model state, `.cst`, or converter `.hrs` file to restore AFR settings on B. Recreate AFR from SCPI or the wizard. Preference settings and most calibration/correction settings are also not transferred.

**Windows / bitness.** A-model firmware is 32-bit Windows 7. B firmware moved to 64-bit and, as of A.20.82.01, Windows 10/11 only (Windows 7 support terminated). File paths on the instrument (`C:\` vs `D:\`) differ by unit; do not hard-code from the examples.

**Licensing.** N-port “AFR Config and 2X Thru for N port” is a licensed feature on B. Core Option 007 / S93007B is still required for the `AFR:` tree.

## 6. Pitfalls

- **Do not mix legacy and draft FSIM.** Error “Cannot send legacy fixture commands” (fixed but still the documented incompatibility). If `CALC:FSIM:LEGacy?` is `FALSE`, stay on draft SCPI or `SYST:PRES` / `CALC:FSIM:RESet` and start clean (**confirm** on the box that Reset returns you to a legacy-compatible state — unconfirmed).
- **Do not send `AFR:` to an A-model A.10.x unit** and expect it to work. If it errors, that is expected.
- **Do not send A.19.30 advanced commands or N-port commands** as part of a “just make A work on B” port. They are later additions and/or licensed.
- **`AFR:STANdard:MEASure` needs A.14.80+.** On earlier B firmware, only `AFR:STANdard:LOAD` is in the documented set. Gate live measure with a firmware check.
- **`SYST:PRESet` is a full factory preset**, not an AFR-only reset. It will wipe traces, channels, and cal. Use `AFR:INITialize` for AFR defaults.
- **`AFR:SAVE:FILename` is documented as setting paths.** Verify that files actually appear.
- **State converter will not move AFR.** Recreate.
- **S93007B is a paid option.** A B-model without it has no AFR tree.
- **Power compensation** (`AFR:CORRection:PCOMpensate`, and FSIM `CALC:FSIM:POWer:...`) is separate from S-parameter de-embed. A.15.30 What’s New also mentions “Compensate Only For De-Embeds (Fixture Generator).” Do not turn these on as a silent default.
- Current AFR help HTML has a few typos (e.g. example `AFR:ADVanced:RESet5`, “Turns ON of OFF”). Trust the command heading and `SYST:ERR?`, not obvious typos.

## 7. Step-by-step instructions for a porting agent

### 7.1 Inventory the existing code (do this first)

Search the repo for AFR and fixture-simulator SCPI. Suggested patterns (case-insensitive, allow optional spaces and shortened keywords — SCPI is case-insensitive and accepts prefixes):

```regex
AFR\s*:
AFR:(INIT|FIXT|STAN|SAVE|CORR|ADV)
CALC(?:ulate)?\s*:*\s*FSIM
FSIMulator
SEND\s*:\s*DEEM
DRAFt\s*:\s*CIRC
007|S93007|S9x007|fixture removal|\.s2p|\.s4p|\.s1p|citi
```

Also search COM / driver wrappers (`ScpiStringParser`, `Parse(`, visa `write`, `ask`) and any `.s2p` path builders. Classify each hit:

| Class | Meaning | Port action |
|---|---|---|
| Legacy FSIM (`SEND:DEEM`, etc.) | A-style apply | Keep for A path. On B, either keep **if** `FSIM:LEGacy?` is TRUE and the new GUI was never used, or replace with the draft sequence in §4.3. Never mix. |
| Core `AFR:` (INITialize, FIXTure:*, STANdard:USE/LOAD/THRU/EDIT, SAVE:*) | Already B A.12.85+ (or copied from B help) | Keep names. Gate `MEASure` on firmware ≥ A.14.80. |
| `AFR:CORRection:*`, `AFR:STANdard:NPORt:*`, `AFR:ADVanced:` (post-A.14.80 / A.19.30) | Later B | Do not require these for A-equivalent behavior. Optional B-only path. |
| GUI-only / file-only | A wizard produced files | B can keep consuming those files via FSIM; optionally add `AFR:` characterization. |

### 7.2 Add a model-dispatch shim; keep the A path

```
idn = query("*IDN?")
model, fw = parse(idn)          # fields 2 and 4

def afr_available(fw, model):
    return is_B_family(model) and fw >= (12, 85, 0)

if is_A_model(model):
    run_existing_A_path()       # do not rewrite this path
elif afr_available(fw, model):
    run_B_afr_path()            # core AFR: + FSIM draft (or AFR:CORR:APPL if verified)
else:
    fail("Unexpected model/firmware; do not guess")

# After every SCPI write on the new path:
err = query("SYST:ERR?")
if not err.startswith("+0"):
    fail(cmd, err)
```

Keep the A path **byte-for-byte** unless a bug is proven on an A unit. The B path is additive.

On B, prefer the **documented example** (characterize with `AFR:`, save `.s2p`, de-embed with `CALC:FSIM:DRAFt:...`, `APPLy`, `STATe ON`) for A-equivalent functionality. Treat `AFR:CORRection:APPLy` as an alternate B API: implement only after it is verified on the target firmware, and do not remove a working FSIM path until then.

### 7.3 Test checklist (on the real B instrument, Option S93007B installed)

1. `*IDN?` — model is N524xB (or agreed B-family), firmware recorded.
2. `*OPT?` (or the confirmed option query) shows AFR; `AFR:INITialize` then `SYST:ERR?` is `+0,"No error"`.
3. Firmware gates: `MEASure` only if ≥ A.14.80; advanced / N-port only if intended and licensed.
4. `CALC:FSIM:LEGacy?` recorded before and after the de-embed sequence.
5. Full characterize → save → de-embed (or `AFR:CORR:APPL`) with `SYST:ERR?` after **each** command. Empty the error queue first (`*CLS` or drain `SYST:ERR?`).
6. Files exist at the `AFR:SAVE:FILename` paths and open as Touchstone (or the chosen `SAVE:TYPE`).
7. Electrical check: a thru or a known DUT, before vs after AFR, residual consistent with the A-model result (same fixture, same cal plane).
8. Port mapping: fixture A / B landed on the intended VNA ports (inspect with the Fixture Simulator GUI, as Keysight recommends).
9. Repeat after `SYST:PRES` and after a power cycle (AFR settings are not assumed to persist — **unconfirmed** persistence).
10. Regression: the **A-model path** still passes on an A unit (or a recorded A-unit transcript). Do not “unify” by deleting it.
11. If using cal-set apply (`AFR:CORR:METH CSET`), confirm the intended cal set is the one corrected (`AFR:CORR:CSET:CAT?`).

## 8. Sources

Fetched or downloaded 2026-11-12:

- AFR SCPI command reference (current, applies to S9x007A/B and 007): https://helpfiles.keysight.com/csg/NA520xA/Programming/GP-IB_Command_Finder/Automatic_Fixture_Removal_(AFR).htm
- AFR UI / wizard (cal at fixture connectors, correction methods, licensed N-port): https://helpfiles.keysight.com/csg/NA520xA/S3_Cals/Auto_Fixture_Removal.htm
- Programming Commands History (A.12.85 and A.14.80 AFR lists): https://helpfiles.keysight.com/csg/NA520xA/Programming/Programming_Commands_History.htm
- New Programming Commands (A.19.30 AFR list; A.16.20–A.20.80): https://helpfiles.keysight.com/csg/NA520xA/Programming/New_Programming_Commands.htm
- What’s New (A.10.20 Auto Fixture Removal; A.12.85 AFR SCPI; A.15.30 N-port AFR / FSIM updates; A.19.30 AFR 2025 updates): https://helpfiles.keysight.com/csg/NA520xA/Whats_New.htm
- Using Fixture Simulator (legacy vs draft, A.14.40+, incompatibility, `SEND:DEEM:PORT`): https://helpfiles.keysight.com/csg/NA520xA/Programming/Using_Fixture_Simulator.htm
- FSimulator (`LEGacy?`, `STATe`, superseded `SNP:EXTRapolate`): https://helpfiles.keysight.com/csg/NA520xA/Programming/GP-IB_Command_Finder/Calculate/FSimulator.htm
- SYSTem (`ERRor[:NEXT]?`, `PRESet`): https://helpfiles.keysight.com/csg/NA520xA/Programming/GP-IB_Command_Finder/SYSTem.htm
- State Converter (AFR not transferred): https://helpfiles.keysight.com/csg/pxivna/S5_Output/State_Converter.htm
- S93007B product page (equivalent to Option 007): https://www.keysight.com/us/en/product/S93007B/s93007b-automatic-fixture-removal.html
- N52xxB PNA firmware release notes (A.12.70 first B; A.17.00.05 `EDIT:FLENgth`; AFR fixes; current A.20.82.01): https://www.keysight.com/id/en/assets/9921-03284/release-notes/N52xxB-PNA-Firmware-Release-Notes.pdf
- N52xxA PNA firmware release notes (latest A.10.65.16; AFR feature fixes): https://www.keysight.com/pr/en/assets/9921-03300/release-notes/N52xxA-PNA-Firmware-Release-Notes.pdf
- N52xxB firmware download page: https://www.keysight.com/us/en/lib/software-detail/instrument-firmware-software/n52xxb-pna-series-network-analyzer-firmware.html
- AFR programming example (N5222B A.17.60.13). Live HTTP fetch was Cloudflare-blocked; command list taken from Keysight’s published article text: https://docs.keysight.com/kkbopen/programming-example-for-afr-automatic-fixture-removal-with-de-embedding-on-the-keysight-vnas-929572476.html
- `*IDN?` form (`Keysight Technologies,N5245B,<serial>,A.15.75.22`): https://docs.keysight.com/kkbopen/what-is-the-scpi-command-to-query-the-source-power-calibration-offset-array-for-the-latest-keysight-vector-network-analyzer-families-771299696.html

## 9. Unconfirmed checklist (resolve on the instrument)

- Any AFR SCPI or COM API on A-model firmware A.10.x — send `AFR:INITialize` / inventory COM type libraries; expect failure for `AFR:`.
- Exact `*OPT?` (or other) string for Option 007 vs S93007B.
- `SYST:HELP:HEAD?` / `SYST:CAP?` as a PNA command catalog (not found in the SYSTem tree fetched here).
- Firmware that introduced `AFR:CORRection:*`, `AFR:SAVE:DUT`, `AFR:FIXTure:USE:THRUs:SAME`, `AFR:ADVanced:THRU:GATE:ALGorithm`, and `AFR:STANdard:NPORt:*` (N-port *feature* is What’s New in A.15.30; SCPI date unconfirmed).
- Whether `AFR:SAVE:FILename` also writes the files, or only sets the path.
- Whether `.afr` files exist as an AFR format (not in `SAVE:TYPE`).
- Difference between `AFR:INITialize` and `AFR:ADVanced:RESet`; whether `CALC:FSIM:RESet` restores `FSIM:LEGacy?` TRUE.
- Interaction of `AFR:CORRection:APPLy` with existing FSIM blocks and with error-term cal sets vs FSIM de-embed of the same `.s2p`.
- Persistence of AFR settings across preset / power cycle / state save.
- `AFR:STANdard:EDIT:FLENgth` *set* on 2X-Thru for firmware just after A.17.00.05 vs current help (“sets … for 1X AFR”).
