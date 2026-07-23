# Transaction Interface for the I2C VCs

Both `I2cController` and `I2cPeripheral` use OSVVM's AddressBus Model Independent
Transactions (`AddressBusRecType`), not Stream.

- `I2cController` uses the Manager transaction set (`Write` / `Read` / burst).
- `I2cPeripheral` uses the Subordinate transaction set (`GetWrite` / `SendRead`).

UART and SPI use Stream (`Send` / `Get`, Transmitter/Receiver) because they do not
have addressing, every transfer is just data over a point-to-point wire.
I2C needs addresses to determine where the data will travel:

- **Manager side:** `Write(TransRec, iAddr, iData)` / `Read(TransRec, iAddr, oData)` map to I2C's START → target → data → STOP
- **Subordinate side:** `GetWrite(TransRec, oAddr, oData)` ("block until a write cycle
  addressed to me happens, then hand me the data") and `SendRead(TransRec, oAddr, iData)`
  ("block until addressed for read, then send this data") already describe exactly what an
  I2C target does when its address matches the one sent from the controller.

Stream would not work here for the peripheral because `Send`/`Get` has no concept of "was I the
one addressed" which means that every target on the bus would have to decide themselves whether to
respond, which AddressBus's address-matching model already handles.

## Controller interface

| MIT call | I2C bus behavior |
|---|---|
| `Write(TransRec, Addr, Data)` | START, Address + Write bit, ACK, Data, ACK, STOP |
| `Read(TransRec, Addr, Data)` | START, Address + Read bit, ACK, Data (from target), NACK (controller-receiver, end of transfer), STOP |
| `WriteBurst` / `ReadBurst` | START, Address + Write or Read bit, ACK, multiple data bytes (using `WriteBurstFifo`/`ReadBurstFifo`), STOP |

## Peripheral interface

The peripheral is a memory-style responder (`GetWrite`/`SendRead`), not `Send`/`Get` (Stream). Stream would technically work 
because the target already knows its own address, however memory-style (`GetWrite`/`SendRead`) 
is used because:

- It has the same vocabulary as the controller side (`Write`/`Read`, `GetWrite`/`SendRead`) and avoids 
switching from AddressBus to Stream in the same system.

- In I2C, addressing happens once per
  transaction (the target address), and the peripheral VC already knows its own address, so `oAddr` from `GetWrite` would just return the
  matched target address back. This does not cost much and allows for potential new features.

## Repeated START

I2C's repeated START (Sr) means
"don't release the bus, just re-address" which is needed for patterns like "write a register
pointer, then read from it without releasing the bus." for example.

A `SET_REPEATED_START` option, part of an `I2cOptionType` enum (like
`SpiOptionType`/`UartOptionType`), used through a wrapper (`SetRepeatedStart`).
This is set immediately before each
transaction that should end with Sr instead of a STOP (P):

```vhdl
SetRepeatedStart(TransRec, TRUE) ;
Write(TransRec, DevAddr, RegPointer) ;     -- ends with Sr, not P
Read(TransRec, DevAddr, Data) ;            -- not rearmed -> normal P
```

`SetRepeatedStart` is a wrapper in `I2cTbPkg`:

```vhdl
procedure SetRepeatedStart (
  signal   TransactionRec : inout I2cRecType ;
  constant Value          : boolean
) is
begin
  SetModelOptions(TransactionRec, I2cOptionType'pos(SET_REPEATED_START), Value) ;
end procedure SetRepeatedStart ;
```

And the VC decodes this option:

```vhdl
when SET_MODEL_OPTIONS =>
  case TransRec.Options is
    when I2cOptionType'pos(SET_REPEATED_START) =>
      RepeatedStartArmed <= TransRec.BoolToModel ;
    ...
```

One time use requires an explicit reset side. `SET_MODEL_OPTIONS` above
only sets `RepeatedStartArmed`, nothing clears it back to `FALSE` on its own. The reset
happens inside `WRITE_OP`/`READ_OP`, at the point that transfer
decides how to end the bus cycle - it reads the flag to choose P or Sr for that transfer,
then unconditionally clears it right there, regardless of which way it went:

```vhdl
when WRITE_OP | READ_OP =>
  -- ... drive S/Sr, address, and data as usual ...
  if RepeatedStartArmed then
    -- hold the bus: emit Sr for the next transaction instead of STOP
  else
    -- emit a normal STOP
  end if ;
  RepeatedStartArmed <= FALSE ;   -- consumed either way - back to "close normally" by default
```

## NACK injection

Let the test writer choose to force a NACK on **either the address byte or
any specific data byte** (by index) of the next transaction.

One integer value is carried:

- `NackByteIndex < 0` (`-1` for example) -> NACK the address byte.
- `NackByteIndex >= 0` -> NACK the data byte at that 0-based index within the next transfer
  (a burst's `NumFifoWords` bytes, or index `0` for a single byte `Write`/`Read`).

Two named wrapper procedures, both writing the same underlying integer option:

```vhdl
procedure SetNackInjectAddress (
  signal TransactionRec : inout I2cRecType
) ;   -- next address byte gets NACKed

procedure SetNackInjectDataByte (
  signal   TransactionRec : inout I2cRecType ;
  constant ByteIndex      : natural
) ;   -- next transfer's ByteIndex'th data byte gets NACKed
```

ACK/NACK on the bus is always
generated by whichever side is receiving that byte:

- `I2cPeripheral` generates ACK/NACK for the address byte (every write and read starts
  with the target ACKing its own address) and for write-data bytes (target receives, target
  ACKs/NACKs). So `SetNackInjectAddress` and `SetNackInjectDataByte` on a write both belong
  on the peripheral VC.
- `I2cController` generates ACK/NACK for read-data bytes (controller receives, controller
  ACKs/NACKs, NACKing only the last byte to end the read). `SetNackInjectDataByte`
  on a read is therefore a controller-side option, used to force an early/unexpected NACK
  in the middle rather than at the last byte.

## Model options (`SetModelOptions` / `GetModelOptions`)

Following the pattern used by `SpiOptionType`/`UartOptionType`: `I2cOptionType` is used,
dispatched by position in the VC's `SET_MODEL_OPTIONS` branch, with each option exposed to
test writers through its own named wrapper procedure (`SetSclPeriod` or `SetRepeatedStart` for instance) rather than raw `SetModelOptions`/`I2cOptionType'pos(...)` calls in test
code:

| Option | Type | Wrapper procedure | Meaning |
|---|---|---|---|
| `SET_SCL_PERIOD` | `time` | `SetSclPeriod(TransRec, Period)` | Override the SCL clock period (Standard-mode/Fast-mode/Fast-mode Plus) |
| `SET_CLOCK_STRETCH_ENABLE` | `boolean` | `SetClockStretchEnable(TransRec, Value)` | Enable/disable this VC clock stretching |
| `SET_NACK_INJECT` | `integer` (`<0` = address, `>=0` = data byte index) | `SetNackInjectAddress(TransRec)` / `SetNackInjectDataByte(TransRec, Index)` | Force a NACK on the address byte or a specific data byte on the next transaction. This is implemented on whichever VC generates ACK/NACK for that byte |
| `SET_REPEATED_START` | `boolean` | `SetRepeatedStart(TransRec, Value)` | One-time-use: next `Write`/`Read` ends with Sr instead of STOP |