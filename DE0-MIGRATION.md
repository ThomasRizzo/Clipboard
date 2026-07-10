# DE0 to DE0-Nano (Cyclone IV) Migration Guide

## TL;DR
- Physical 40-pin IDC headers are compatible for plug-in (same two 40-pin expansion headers).
- Main task: Update pin assignments in Quartus (FPGA pin mapping changes).
- Target device: EP4CE22F17C6N.
- Expected time: 1-8 hours depending on project complexity.

## TODO
- [ ] Download DE0-Nano User Manual & schematic from Terasic
- [ ] Create new Quartus Prime project targeting Cyclone IV EP4CE22F17C6N
- [ ] Remap all pins for the two 40-pin headers
- [ ] Regenerate IP cores, PLLs, and Nios II system (if used)
- [ ] Compile, run Timing Analysis, and fix issues
- [ ] Program and test incrementally
- [ ] Update any scripts or documentation referencing old pinouts

## Detailed Steps

### 1. Gather Resources
- Download the **DE0-Nano User Manual** and **schematic** from Terasic (Resources section on the product page).
- Keep your original DE0 documentation for comparison.

### 2. Set Up Quartus
- Use the latest **Quartus Prime Lite** (free).
- Open or create a new project.

### 3. New Project Configuration
- **File → New Project Wizard**
- Device family: **Cyclone IV E**
- Specific device: **EP4CE22F17C6N**
- Add all your existing HDL source files (.v, .vhdl, top-level, constraints, etc.).
- Most pure RTL code will work with minimal or no changes.

### 4. Pin Assignments (Critical Step)
- Open **Assignments → Pin Planner** or edit the `.qsf` file.
- For every signal connected to the 40-pin headers:
  - Look up the physical header pin number in the DE0-Nano manual.
  - Assign the corresponding FPGA pin from the DE0-Nano pin table.
- Remove old DE0 pin assignments.
- Also remap any onboard resources (LEDs, switches, clocks, reset) used in your design.
- Save and run **Analysis & Synthesis** to validate.

### 5. IP Cores, Megafunctions & Nios II
- Regenerate any Altera IP (PLLs, memory, etc.) via the **IP Catalog**.
- For **Nios II** (if used):
  - Regenerate the system in **Platform Designer**.
  - Update and rebuild the BSP in Nios II Software Build Tools.

### 6. Compile & Verify Timing
- Run full compilation.
- Review **Timing Analyzer (TimeQuest)** reports.
- Add or adjust SDC constraints as needed (Cyclone IV timing is similar to Cyclone III).

### 7. Generate & Program
- Create `.sof` (JTAG) or `.pof` (flash) files.
- Program via the onboard USB-Blaster (same as DE0).

### 8. Testing & Debugging
- Start with a simple test design (e.g., LED blinker or I/O loopback on headers).
- Use **SignalTap II** for internal debugging.
- Verify all header I/O, voltages (3.3V), and clocks.
- Incrementally integrate the rest of your design.

## Common Issues & Tips
- Pin conflicts or I/O standard mismatches — double-check voltage (3.3V) and direction.
- Resource usage: DE0-Nano has more LEs (~22k vs original ~15k), so most designs will fit.
- Power: Test with your daughter cards; regulators differ slightly.
- Clocks: Confirm oscillator frequency (DE0-Nano typically 50 MHz).

## References
- [Terasic DE0-Nano Product Page](https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&CategoryNo=139&No=593)
- DE0-Nano User Manual (pin tables & schematics)
- Quartus Prime Handbook & Tutorials (Intel/Altera site)
- Original DE0 documentation for comparison