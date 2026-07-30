# AXI4-Lite Peripheral Subsystem — GPIO / Timer / FIFO with IRQ Aggregation

A multi-peripheral SoC-style subsystem built around a shared AXI4-Lite bus, integrating a GPIO controller, a programmable timer, and a FIFO, unified behind a single address-decoded interconnect with aggregated interrupt output. Verified with a UVM testbench and synthesized on Intel/Altera Cyclone 10 GX.

Follows on from a standalone [AXI4-Lite block-level UVM verification project](#) (single subordinate device, exhaustive coverage-driven verification). This project's goal was different: build a realistic multi-peripheral subsystem, integrate it cleanly, and carry it through synthesis and timing closure — not repeat the same exhaustive coverage push at larger scale. The verification strategy below reflects that.

---

## 1. Architecture

```
                        ┌─────────────────────────────┐
                        │        top (subsystem)       │
  AXI4-Lite  ───────►   │   axi4lite_wrapper            │
  (AW/W/B, AR/R)         │   (AW/W/B, AR/R FSMs)         │
                        │        │                      │
                        │        ▼                      │
                        │   address_decoder             │
                        │    ├─► gpio    (0x000–0x0FF)  │
                        │    ├─► timer   (0x100–0x1FF)  │
                        │    └─► fifo    (0x200–0x2FF)  │
                        │                               │
                        │   irq_gpio ─┐                 │
                        │   irq_timer ├─► irq_aggregator │──► combined IRQ
                        │   irq_fifo ─┘                 │
                        └─────────────────────────────┘
```

- **GPIO** — data out/in, direction, full interrupt subsystem (enable, w1c status, edge/level trigger, polarity select)
- **Timer** — 32-bit LOAD/COUNT/CONTROL/STATUS/PRESCALAR, one-shot + auto-reload modes, w1c status clear
- **FIFO** — 16-entry × 32-bit, word-addressed, configurable interrupt threshold, empty/full/threshold status flags
- **address_decoder** — flat 256-word (1KB) window per peripheral
- **irq_aggregator** — combinational OR of the three IRQ lines into one subsystem IRQ, per-source status bits exposed for checking
- **axi4lite_wrapper** — AXI4-Lite AW/W/B and AR/R handshakes → internal `psel`/`pwrite`/`paddr`/`pwdata`/`prdata` bus, via two FSMs: `write_state` (w_req→w_dat→w_res), `read_state` (r_req→r_dat→r_res)

---

## 2. Verification approach: directed, not coverage-driven random

- The block-level project used constrained-random-style stimulus (manual `$urandom_range` weighting, no full Questa license) on a **single** subordinate device, with coverage built to prove exhaustive exercising of address space, strobes, and response codes.
- That doesn't transfer cleanly to a 3-peripheral subsystem with interacting interrupts, a shared bus, and stateful timer/FIFO behavior — fully randomizing writes across three independent peripherals with no sequencing mostly produces noise (illegal configs, timer periods too short to observe, FIFO ops faster than the model can track).
- So verification here is **directed-with-local-randomization**:
  - Each test targets a specific peripheral or cross-peripheral scenario
  - *Within* each scenario, specific fields are randomized via `$urandom_range` inside explicit `randomise()` functions (GPIO polarity/edge select, FIFO write data, timer LOAD/PRESCALAR) — same manual-randomization technique carried over from the block-level project

| Test | Focus |
|---|---|
| `test_gpio_basic` | GPIO configuration + interrupt trigger path |
| `test_timer_basic` | Timer LOAD/PRESCALAR/CONTROL config, status read/w1c |
| `test_fifo_basic` | FIFO write/read round-trip, randomized data |
| `test_all_peripherals` | All three together, cross-peripheral IRQ aggregation |

- `run_regression` runs all four tests across N random seeds, so directed-structure tests still get seed-to-seed variation in randomized fields and timing.
- **Scoreboard** — shadow-state model (`axi4lite_scoreboard`) checks every register read against tracked write history. Timer count-down is modeled cycle-accurately via a background `fork...join_none` process mirroring `timer.sv`'s FSM exactly, including prescaler ticking and auto-reload wraparound.
- **Coverage** — a lightweight functional coverage class (`axi4lite_coverage`) tracks per-peripheral write/read hits, WSTRB usage, and response codes, alongside Questa's structural coverage (branch/condition/statement/toggle/FSM). Reported as evidence of what was exercised, not as an optimization target.

---

## 3. Bugs found and fixed

**RTL:**
- **Timer period race** — one-cycle race between counter decrement and IRQ observation at short LOAD values; fixed by measuring IRQ-to-IRQ intervals with large LOAD values instead of config-write-to-first-IRQ.
- **LOAD=0 corner case** — FSM latch-timing gap on the first tick; fixed in the IDLE→COUNT transition.
- **FIFO back-to-back read pointer bug** — repeated reads without an address change were advancing the pointer multiple times; fixed with an `rd_req`/`rd_req_prev` edge-detect pair so the pointer only advances on the rising edge of a read request.
- **Read FSM regression** — `r_dat`/`r_res` were briefly, incorrectly gated on `write_state` instead of `read_state`; caught and corrected.
- **Modport direction violation** — `gpio_oe` declared `input` in the `subordinate` modport but driven via continuous `assign` — a real IEEE 1800-2017 §25.5 violation. Questa's leniency on continuous-assign direction checking let it through silently; caught by manual review, not by the tool.

**UVM testbench / scoreboard:**
- **`TIMER_COUNT` off-by-one** — shadow model was one cycle ahead of RTL; aligned decrement timing to match the `always_ff` exactly.
- **w1c race condition** — same-cycle status-clear write vs. timer overflow: RTL's NBA semantics mean set wins over clear. Fixed with a `timer_overflow_this_cycle` flag the w1c handler checks before applying a clear.
- **Auto-reload timing reference not resetting** — period-timing check needs to re-anchor after every overflow, not just the first; without the fix, `actual_period` grows as 2×, 3×, 4×... on each subsequent cycle.
- **Monitor timestamp offset** — timestamp was stamped at the W phase instead of after `BVALID`/`RVALID`, introducing a consistent ~30ns (3-cycle) offset into every timing check. Fixed by moving the timestamp assignment to right after the BVALID/RVALID wait.
- **GPIO interrupt polarity coverage gap** — `gpio_config_seq` only randomized `edge_triggered`, not `rising`, so level-triggered/polarity variations were silently untested. Caught by inspection, fixed by randomizing both together.

---

## 4. Simulation results

**`test_all_peripherals`, single seed:** 0 UVM_ERROR, 0 UVM_FATAL, scoreboard **7/7 checks passed.**

- GPIO configuration (data-out, direction, IRQ enable/type/polarity)
- Timer set for auto-reload (LOAD=0x3E, PRESCALAR=0x2, CONTROL=0x7)
- One FIFO write/read-back cycle: `0x7981A327` written, `0x7981A327` read back — correct

**⚠ Timer IRQ timing — narrow margin, not comfortable.** The scoreboard allows a ±3-cycle (30ns) tolerance window around the expected timer period, to absorb a structural pipeline offset between monitor-observed `BVALID` and the timer actually receiving `psel`/`pwrite`. In this run, the observed diff was **exactly 30ns — right at the edge of the window**, not comfortably inside it. It passed (`diff > window` was false), but this is worth stating honestly: the window is sized correctly for the real offset, but isn't a wide safety margin, and a different LOAD/PRESCALAR combination could plausibly land right at the boundary of failing.

**⚠ GPIO interrupt path not meaningfully exercised in this run.** `gpio_in` was never driven, so the level-trigger logic received an undriven (X) input that latched into `int_status_reg`. Since `if(X)` evaluates false in SystemVerilog, the scoreboard's GPIO-IRQ check simply never fired — an absence of a check, not a false pass. `test_gpio_basic` is structured to close this gap; confirming it requires the full regression, not this test alone.

**Structural coverage (Questa, single seed, `+cover=bcefsx`):**

| Instance | Branch | Condition | Statement | Toggle | Notes |
|---|---|---|---|---|---|
| gpio | 54.2% | 14.3% | 71.1% | 0.6% | reads not exercised |
| timer | 73.3% | 55.6% | 73.0% | 2.4% | reads not exercised |
| fifo | 68.4% | 57.1% | 86.7% | 29.2% | |
| irq_aggregator | — | — | 100% | — | trivial 3-input OR |
| axi4lite_wrapper | 85.7% | 50.0% | 92.2% | 33.2% | FSM states 100%, transitions 66.7%/75% |
| address_decoder | 100% | 33.3% | 100% | 56.2% | |

**Total blended: 61.8%** — expected for a single directed run, not a regression. Reported as evidence of what one scenario exercised, not a completeness claim.

- Wrapper's `write_state` and `read_state` FSMs: 100% state coverage, but miss bypass transitions (`w_req→w_res`, `w_dat→w_req`, `r_dat→r_req`) — likely abort/early-exit paths a clean directed run without fault injection never triggers.

---

## 5. Synthesis results (Quartus Prime 26.1.0, Cyclone 10 GX)

| Metric | Result |
|---|---|
| Device | 10CX220YF780I5G |
| Logic utilization | 499 / 80,330 ALMs (< 1%) |
| Registers | 699 |
| Block memory | 8,192 / 12,021,760 bits (< 1%), 1 / 587 RAM blocks |
| DSP blocks | 0 / 192 |
| Pins | 248 / 340 (73%) |
| Target clock | 100 MHz (10 ns) |
| Fmax (Slow 900mV, 100°C) | **164.55 MHz** |
| Setup slack @ 100 MHz | **+3.923 ns**, 0 failing endpoints |
| Hold slack (Fast 900mV, −40°C) | **+0.019 ns**, 0 failing endpoints |
| Critical path | `wrapper.paddr[23]` → `wrapper.axiif.RDATA[0]` (registered read-address → read-data) |

- Comfortable setup margin (~4ns) and Fmax well above the 100MHz target; hold passes with a small but positive margin, typical of FPGA flows where hold is closed mostly by the fitter's automatic buffer insertion.
- **FIFO memory** correctly infers as an `altsyncram` block-RAM primitive (confirmed via Technology Map Viewer) — result of fix moving from a multi-write `always_ff` block to a combinational write-address mux, which Quartus couldn't otherwise map to embedded RAM.
- Quartus auto-inserts read-during-write "pass-through" bypass registers alongside the RAM — standard automatic fitter behavior for synchronous memories, not something added manually in RTL.

---

## 6. Known limitations

- **No AXI error-response generation.** Synthesis confirms `BRESP`/`RRESP` are permanently stuck at GND (OKAY) — no RTL path ever drives SLVERR or DECERR, for any condition. Matches simulation (response-code coverage never showed anything but OKAY). A deliberate scope boundary, not a missed gap.
- **No concurrent read/write per peripheral.** Each peripheral services one operation at a time.
- **Timer IRQ timing tolerance is narrow in practice** — the ±3-cycle window is correctly sized but observed diffs have landed at its edge rather than comfortably inside it.
- **Coverage above reflects a single directed run**, not a multi-seed regression.

---

## 7. Repository structure

```
rtl/
  gpio.sv, timer.sv, fifo.sv, top.sv,
  axi4lite_wrapper.sv, address_decoder.sv, irq_aggregator.sv
tb/
  interface/     axi4lite_if.sv, gpio_if.sv, timer_if.sv, fifo_if.sv, irq_if.sv
  seq_item/      axi4lite_seq_item.sv, gpio_transaction.sv, irq_transaction.sv
  driver/        axi4lite_driver.sv
  monitor/       axi4lite_monitor.sv, gpio_monitor.sv, irq_monitor.sv
  scoreboard/    axi4lite_scoreboard.sv
  coverage/      axi4lite_coverage.sv
  sequencer/     axi4lite_sequencer.sv
  agent/         axi4lite_agent.sv
  sequence/      axi4lite_sequence.sv
  env/           axi4lite_env.sv
  tests/         axi4lite_base_test.sv
  axi4lite_pkg.sv, tb_top.sv
sim/
  run_uvm.do, regression.do
quartus/
  axi4lite_subsystem.qpf / .qsf
  reports/  (compilation summary, timing summary)
```



