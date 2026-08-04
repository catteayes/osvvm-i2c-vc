# I2C Verification Component User Guide

## Overview

This library provides three OSVVM verification components (VCs) for I2C:

| VC | Role | Transaction interface |
|---|---|---|
| `I2cController` | Bus master, drives SCL/SDA, initiates transactions | AddressBus Manager (`Write`/`Read`/burst) |
| `I2cPeripheral` | Bus target, responds when addressed | AddressBus Subordinate (`GetWrite`/`SendRead`) |
| `I2cMonitor` | Passive observer, never drives the bus | None (plain output ports only) |

All three share the same `SCL`/`SDA` open-drain bus.

## Library and Context

```vhdl
library osvvm;
    context osvvm.OsvvmContext;

library osvvm_i2c;
    context osvvm_i2c.I2cContext;
```

`I2cContext` pulls in `I2cTbPkg` (the `I2cRecType` transaction record, option
setters, speed-class constants), `I2cComponentPkg` (component declarations
for all three VCs), and `I2cCoveragePkg` (shared functional-coverage support,
see [Functional Coverage](#functional-coverage) below).

## Instantiating the Verification Components

```vhdl
architecture TestHarness of TbI2c is
    signal I2cControllerRec : I2cRecType;
    signal I2cPeripheralRec : I2cRecType;
    signal SCL, SDA         : std_logic;

    -- Bus monitor output state
    signal MonitorModelID          : AlertLogIDType;
    signal MonitorScoreboardID     : osvvm.ScoreboardPkg_slv.ScoreboardIDType;
    signal MonitorTransactionCount : integer;
begin

    SCL <= 'H';  -- pull-ups: VCs only drive '0' or 'Z' (open-drain)
    SDA <= 'H';

    I2cController_1 : I2cController
        port map(
            TransRec => I2cControllerRec,
            SCL      => SCL,
            SDA      => SDA
        );

    I2cPeripheral_1 : I2cPeripheral
        port map(
            TransRec => I2cPeripheralRec,
            SCL      => SCL,
            SDA      => SDA
        );

    I2cMonitor_1 : I2cMonitor
        port map(
            SCL                 => SCL,
            SDA                 => SDA,
            ModelID             => MonitorModelID,
            MonitorScoreboardID => MonitorScoreboardID,
            TransactionCount    => MonitorTransactionCount
        );

end architecture TestHarness;
```

## Generics

### I2cController

| Generic | Type | Default | Meaning |
|---|---|---|---|
| `MODEL_ID_NAME` | `string` | `""` | AlertLog ID name; falls back to the instance label (e.g. `i2ccontroller_1`) if left empty |
| `SCL_PERIOD` | `time` | `I2C_SCL_PERIOD_400K` (2.5 us, Fast-mode) | Initial SCL period. Can be changed at runtime with `SetSclPeriod` |

### I2cPeripheral

| Generic | Type | Default | Meaning |
|---|---|---|---|
| `MODEL_ID_NAME` | `string` | `""` | Same as above |
| `TARGET_ADDRESS` | `std_logic_vector(9 downto 0)` | `"0001010000"` (0x50, 7-bit) | This peripheral's own device address |
| `TEN_BIT_ADDR` | `boolean` | `false` | `true` selects 10-bit addressing; `TARGET_ADDRESS`'s full 10 bits are then significant (otherwise only the low 7 bits are) |
| `SCL_PERIOD` | `time` | `I2C_SCL_PERIOD_400K` | Only used for the peripheral's own internal reference clock (see below). has no effect on the real bus timing, which the peripheral just reacts to |

### I2cMonitor

| Generic | Type | Default | Meaning |
|---|---|---|---|
| `MODEL_ID_NAME` | `string` | `""` | Same as above |

## Transaction API

### Controller (Manager) side

All of these are OSVVM AddressBus Model Independent Transactions,
`iAddr`/`oData` are `std_logic_vector`s sized to whatever address width (7 or
10 bits) and 8-bit data the test uses; `I2cRecType` itself is sized for
10-bit addresses (`Address(9 downto 0)`), so passing a 7-bit literal like
`"1010000"` still works.

**`Write`**, blocking single-byte write:
```vhdl
Write(I2cControllerRec, "1010000", X"65");
```

**`Read`**, blocking single-byte read:
```vhdl
variable RData : std_logic_vector(7 downto 0);
...
Read(I2cControllerRec, "1010000", RData);
```

**`WriteBurstVector`**, blocking multi-byte write, bytes supplied as an
`slv_vector`:
```vhdl
constant WriteBytes : slv_vector(0 to 2)(7 downto 0) := (X"11", X"22", X"33");
...
WriteBurstVector(I2cControllerRec, BURST_ADDR, WriteBytes);
```

**`ReadBurst`** / **`ReadCheckBurstVector`**, blocking multi-byte read;
`ReadBurst` queues the received bytes into `TransRec.ReadBurstFifo` for the
caller to `Pop`, `ReadCheckBurstVector` checks them directly against an
expected `slv_vector`:
```vhdl
ReadBurst(I2cControllerRec, DEV_ADDR, 3);
AffirmIfEqual(Pop(I2cControllerRec.ReadBurstFifo), RDATA0, "byte 0");
...
-- or, to check against a known vector directly:
ReadCheckBurstVector(I2cControllerRec, BURST_ADDR, ReadBytes);
```

**`WaitForClock`**, advance the VC's internal reference clock:
```vhdl
WaitForClock(I2cControllerRec, 2);
```

**`GetAlertLogID`** / **`GetTransactionCount`**:
```vhdl
variable CtrlAlertLogID : AlertLogIDType;
GetAlertLogID(I2cControllerRec, CtrlAlertLogID);
```

### Peripheral (Subordinate) side

**`GetWrite`**, block until a write cycle addressed to this peripheral
happens, then return the address and data:
```vhdl
variable RxAddr : std_logic_vector(6 downto 0);
variable RxData : std_logic_vector(7 downto 0);
...
GetWrite(I2cPeripheralRec, RxAddr, RxData);
```

**`SendRead`**, block until addressed for a read, then send the supplied
data:
```vhdl
SendRead(I2cPeripheralRec, RxAddr, X"34");
```

For burst reads/writes on the peripheral side, call `GetWrite`/`SendRead`
once per byte in a loop (see `TbI2c_Burst1.vhd`'s `PeripheralProc` for the
pattern), the peripheral doesn't need its own burst-specific transaction,
since it just responds to each address-matched byte as it arrives.

### Monitor (passive)

`I2cMonitor` has no transaction interface, it never receives commands, it
only observes. Its three output ports are read directly by the test:

- `ModelID` for `GetAlertCount(MonitorModelID)`, to confirm the monitor
  found no protocol violations or scoreboard mismatches.
- `MonitorScoreboardID`, `Push` expected wire bytes (address+R/W byte, then
  each data byte, in wire order) before the transaction happens; the monitor
  reconstructs the real bytes independently off SCL/SDA and `Check`s them
  automatically.
- `TransactionCount` increments once per complete transaction the monitor
  observed.

```vhdl
Push(MonitorScoreboardID, DEV_ADDR & '0');  -- expected address+R/W byte
Push(MonitorScoreboardID, WDATA);           -- expected data byte

Write(I2cControllerRec, DEV_ADDR, WDATA);

wait for 1 ns;  -- let the monitor's own process catch up to the same STOP
AffirmIfEqual(MonitorTransactionCount, CountBefore + 1, "...");
AffirmIfEqual(GetAlertCount(MonitorModelID), 0, "...");
```

If a test never `Push`es anything into `MonitorScoreboardID`, the monitor
doesn't check that transaction's bytes (no false failures), it still
tracks `TransactionCount` and still enforces protocol-legality checks
(SDA-stable-while-SCL-high, ACK-position, START/STOP framing) regardless.

## Model Options (`SetModelOptions`)

Every option below is exposed through a named wrapper procedure in
`I2cTbPkg`, test code should always use the wrapper, never raw
`SetModelOptions`/`I2cOptionType'pos(...)` calls directly.

| Option | Wrapper | Applies to | Meaning |
|---|---|---|---|
| `SET_SCL_PERIOD` | `SetSclPeriod(TransRec, Period)` | `I2cController` | Change the SCL clock period at runtime (e.g. `I2C_SCL_PERIOD_100K`/`_400K`/`_1M`, or any other `time` value) |
| `SET_TIMEOUT` | `SetTimeout(TransRec, Value)` | `I2cController` | Longest time the controller will wait for SCL to release before Alerting `FAILURE` instead of hanging on a stuck bus |
| `SET_REPEATED_START` | `SetRepeatedStart(TransRec, Value)` | `I2cController` | One-time-use: the next `Write`/`Read` ends with a repeated START (Sr) instead of STOP, so the following transaction stays on the same bus session |
| `SET_NACK_INJECT` | `SetNackInjectAddress(TransRec)` / `SetNackInjectDataByte(TransRec, ByteIndex)` | `I2cPeripheral` (address / write-data bytes) and `I2cController` (read-data bytes) | One-time-use: force a NACK on the next transaction's address byte, or a specific data byte by 0-based index |
| `SET_CLOCK_STRETCH_DELAY` / `SET_CLOCK_STRETCH_INDEX` | `SetClockStretch(TransRec, Delay, Index)` | `I2cPeripheral` | One-time-use: hold SCL low for `Delay` after bit `Index mod 9` of byte `Index / 9` of the next transaction (`0`=address byte; bit `0`-`7`=data MSB-first, `8`=ACK/NACK) |
| `SET_ARB_RETRY` | `SetArbitrationAutoRetry(TransRec, Value)` | `I2cController` | When a `Write`/`Read`/`WriteBurst`/`ReadBurst` loses multi-master arbitration: with retry disabled (default) the controller releases the bus and gives up (Alert `WARNING`); with retry enabled, it waits for the bus to go idle and retries the whole transaction from the start |

Example, forcing a peripheral to NACK the next write's address byte:
```vhdl
SetNackInjectAddress(I2cPeripheralRec);
Write(I2cControllerRec, DEV_ADDR, WDATA);  -- fails with an ERROR alert
```

Example, a register-pointer-then-read using repeated START:
```vhdl
SetRepeatedStart(I2cControllerRec, TRUE);
Write(I2cControllerRec, DEV_ADDR, REG_POINTER);  -- ends with Sr, not STOP
Read(I2cControllerRec, DEV_ADDR, RData);         -- not rearmed -> normal STOP
```

## 10-bit Addressing

Pass a 10-bit address (any `std_logic_vector(9 downto 0)`) to the same
`Write`/`Read`/burst calls used for 7-bit addressing - the controller
automatically drives the correct two-byte wire encoding (`"11110" & Addr(9
downto 8) & R/W`, then `Addr(7 downto 0)`, with its own internal repeated
START before the read-direction byte on a `Read`). On the peripheral side,
set `TEN_BIT_ADDR => true` and give the full 10-bit `TARGET_ADDRESS` in the
instance's generic map (see `TbI2c_Addr10_1.vhd`'s `configuration` block for
the exact pattern).

## Functional Coverage

`I2cCoveragePkg` (in `I2cContext`) provides shared support for per-test
functional coverage models: `I2cErrorKindType`, the coverage-database file
names, and `MergeCovDbIfExists`/`I2cAddrRangeBucket` helpers. Each test
declares its own local `CoverageIDType` signals, builds its own bins, and
samples them directly with `ICover` after each transaction, see
`TbI2c_WriteRead1.vhd` for the reference pattern. Coverage accumulates
across a whole `RunAllTests.pro` regression via `WriteCovDb`/`ReadCovDb`
round-tripping through the shared `.txt` database files, since each test in
`testbench.pro` runs as a separate GHDL process.