# Fault Detection and Recovery Controller (FDRC)

A hardware fault management IP core written in SystemVerilog. Monitors up to four sub-modules via heartbeat lines, logs fault events with clock-cycle timestamps, and escalates through a software-supervised recovery sequence to hardware-enforced safe mode — all without processor polling overhead during normal operation.

Verified on Intel Cyclone IV EP4CE6E22C8N FPGA. Simulated with Icarus Verilog and ModelSim.

---

## Architecture overview

The design follows a hybrid hardware-software approach: hardware handles detection and escalation at clock speed, software handles diagnosis and controlled recovery via an AXI4-Lite register interface.

```
                    ┌─────────────────────────────────────────┐
heartbeat[3:0] ───► │           fault_monitor.v               │
 error_flag[3:0] ──►│  Cycle-accurate heartbeat watchdog      │─── fault_detected
                    │  Programmable timeout threshold         │─── fault_code[1:0]
                    └────────────────┬────────────────────────┘
                                     │ fault_detected
                    ┌────────────────▼────────────────────────┐
                    │           recovery_fsm.v                │
                    │  IDLE → MONITOR → RECOVERY_START        │─── recovery_req
recover_ack ───────►│         → WAIT_ACK → SAFE_MODE          │─── safe_mode
                    │  Retry-limited, ack-timeout escalation  │─── fault_clear
                    └────────────────┬────────────────────────┘
                                     │ fault_detected, fault_code
                    ┌────────────────▼────────────────────────┐
                    │           fault_logger.v                │
                    │  16-entry hardware flight recorder      │─── log_valid
                    │  Timestamp, module_id, fault_code       │─── log_count[7:0]
                    └─────────────────────────────────────────┘

                    ┌─────────────────────────────────────────┐
                    │          axi_lite_slave.v               │
 CPU / software ───►│  Register map: status, fault code,      │─── timeout_cfg[7:0]
  AXI4-Lite bus     │  log count, control, timeout, retry     │─── retry_cfg[7:0]
                    └─────────────────────────────────────────┘
```
---

## Module descriptions

### `fault_monitor.v`

Watches four independent `heartbeat` lines and four `error_flag` lines simultaneously. Each heartbeat has its own counter; if a counter reaches `timeout_cfg` without being cleared by a heartbeat pulse, `fault_detected` is asserted and `fault_code` is set to `2'b01`. An asserted `error_flag` on any channel forces `fault_detected` high with `fault_code = 2'b10`.

Parameters:

| Parameter | Default | Description |
|---|---|---|
| `NUM_MODULES` | 4 | Number of monitored sub-modules |
| `COUNTER_WIDTH` | 8 | Width of per-module heartbeat counter |

### `recovery_fsm.v`

Five-state FSM that reacts to `fault_detected` and manages the recovery handshake with external software:

```
IDLE → MONITOR → RECOVERY_START → WAIT_ACK → SAFE_MODE
                      ▲               │  (recover_ack)
                      └───────────────┘  (retry if ack timeout, up to retry_cfg times)
```

Once `retry_counter >= retry_cfg` without a valid `recover_ack`, the FSM enters `SAFE_MODE` permanently (requires `rst_n` to exit). This is intentional — safe mode is designed as a hard stop requiring human intervention before re-arming.

Parameters:

| Parameter | Default | Description |
|---|---|---|
| `ACK_TIMEOUT` | 8 | Clock cycles before retrying a recovery request |
| `COUNTER_WIDTH` | 8 | Width of retry and ack-timeout counters |

### `fault_logger.v`

16-entry circular hardware flight recorder. Each entry captures a `timestamp_counter` value, `module_id`, and `fault_code` at the moment of fault detection. The timestamp counter runs continuously and is never paused, ensuring the recorded time reflects the actual fault onset rather than a polled sample.

Parameters:

| Parameter | Default | Description |
|---|---|---|
| `LOG_DEPTH` | 16 | Number of fault log entries |
| `TIMESTAMP_WIDTH` | 16 | Width of the free-running timestamp counter |
| `MODULE_ID_WIDTH` | 2 | Width of module identifier field |

### `axi_lite_slave.v`

AXI4-Lite compliant slave implementing a 6-register map. Simultaneous `awvalid` + `wvalid` write protocol. Read path is single-cycle registered.

**Register map:**

| Address | Name | R/W | Description |
|---|---|---|---|
| `0x00` | STATUS | R | `[0]` fault_detected, `[1]` safe_mode |
| `0x04` | FAULT_CODE | R | `[1:0]` last fault code (01=heartbeat, 10=error_flag) |
| `0x08` | LOG_COUNT | R | Number of fault events logged |
| `0x0C` | CONTROL | W | `[0]` clear_fault, `[1]` clear_logs |
| `0x10` | TIMEOUT_CFG | R/W | Heartbeat timeout threshold (default: 8 cycles) |
| `0x14` | RETRY_CFG | R/W | Max recovery retries before SAFE_MODE (default: 3) |

Default values restore on `rst_n` deassertion.

---

## Simulation

Tested with Icarus Verilog and ModelSim. The testbench exercises the following sequence:

1. Reset release
2. AXI write: `TIMEOUT_CFG = 5`, `RETRY_CFG = 2`
3. Drop `heartbeat[0]` — triggers fault detection after 5 cycles
4. Assert `recover_ack` — FSM returns to MONITOR
5. Observe `safe_mode` not asserted (successful recovery)

To simulate with Icarus Verilog:

```bash
iverilog -g2012 -o fdrc_sim \
  fault_monitor.v recovery_fsm.v fault_logger.v axi_lite_slave.v fdrc_top.v tb_fdrc_top.v

vvp fdrc_sim
gtkwave fdrc_top.vcd
```

---

## Timing constraints

Defined in `fdrc.sdc`:

```
create_clock -name clk -period 20.000 [get_ports clk]
```

Target: 50 MHz on Cyclone IV EP4CE6E22C8N (–8 speed grade). All paths are synchronous to a single clock domain; no CDC crossings in the current design.

---

## Known limitations

- `module_id` is hardcoded to `2'b00` in `fdrc_top.v`. The logger records fault type and timestamp correctly but cannot distinguish which of the four heartbeat channels triggered the fault. Planned fix: encode the triggering channel index from `fault_monitor` and route it as `module_id`.
- `fault_code` uses last-write-wins priority within the monitoring loop. If two channels fault simultaneously in the same clock cycle, only the highest-indexed channel's code is recorded.
- No interrupt output pin. Software must poll `STATUS_REG (0x00)` to detect `recovery_req` assertion. An IRQ output is planned for a future revision.

---

## Design rationale

Pure software fault monitoring (timer-based polling or periodic interrupts) burns CPU cycles proportional to the number of monitored modules and the required detection latency. This design offloads monitoring entirely to hardware counters, so the processor is idle during normal operation and is only invoked when a fault actually occurs.

Pure hardware implementations fix safety thresholds at synthesis time. The AXI register interface allows runtime adjustment — tighter timeouts during high-criticality operation, relaxed thresholds during boot or heavy background transfers.

The two-stage escalation (software-supervised recovery first, automatic hardware SAFE_MODE fallback) allows a supervisor CPU to save state and park actuators before acknowledging a fault, while guaranteeing that an unresponsive CPU cannot leave a faulted subsystem running indefinitely.

---

## Author

**Badrinath Ayyamperumal**  
GitHub: [github.com/Badrinath007](https://github.com/Badrinath007)  
LinkedIn: [linkedin.com/in/badrinatha](https://linkedin.com/in/badrinatha)
