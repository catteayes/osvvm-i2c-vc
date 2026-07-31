--
--  File Name:         I2cTbPkg.vhd
--  Design Unit Name:  I2cTbPkg
--
--  Maintainer:        Mehmet Burak Aykenar    email: burak.aykenar@anadologic.com
--  Contributor(s):
--     <intern name>
--
--  Description:
--      Constants, types, and transaction support for the I2C verification
--      components (I2cController, I2cPeripheral).
--
--  Revision History:
--    Date      Version    Description
--    07/2026   0.4        SetSclPeriod / SetTimeout (#13)
--    07/2026   0.3        SetNackInjectAddress / SetNackInjectDataByte (#12)
--    07/2026   0.2        I2cOptionType / SetRepeatedStart (#11)
--    07/2026   0.1        Initial skeleton
--
--  Licensed under the Apache License, Version 2.0 (the "License");
--  you may not use this file except in compliance with the License.
--  You may obtain a copy of the License at
--
--      https://www.apache.org/licenses/LICENSE-2.0
--
--  Unless required by applicable law or agreed to in writing, software
--  distributed under the License is distributed on an "AS IS" BASIS,
--  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--  See the License for the specific language governing permissions and
--  limitations under the License.
--

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library osvvm;
    context osvvm.OsvvmContext;

library osvvm_common;
    context osvvm_common.OsvvmCommonContext;

package I2cTbPkg is

    ----------------------------------------------------------------------------
    -- I2C Transaction Record Type
    ----------------------------------------------------------------------------
    -- PROPOSAL — to be confirmed by the transaction-interface design note
    -- (see repository issue "Design note: transaction interface").
    -- The controller is address-based (target address + data), so the OSVVM
    -- Model Independent AddressBus transaction interface is proposed:
    --   Write(TransRec, Address, Data) / Read(TransRec, Address, Data)
    -- Compare with StreamRecType as used by osvvm_spi.SpiTbPkg before deciding.
    subtype I2cRecType is AddressBusRecType(
        Address      (9 downto 0),   -- supports 7-bit and 10-bit addressing
        DataToModel  (7 downto 0),
        DataFromModel(7 downto 0)
    );

    ----------------------------------------------------------------------------
    -- I2C Bus Timing (SCL period per bus speed class, NXP UM10204)
    ----------------------------------------------------------------------------
    constant I2C_SCL_PERIOD_100K : time := 10 us;    -- Standard-mode
    constant I2C_SCL_PERIOD_400K : time := 2500 ns;  -- Fast-mode
    constant I2C_SCL_PERIOD_1M   : time := 1 us;     -- Fast-mode Plus

    ----------------------------------------------------------------------------
    -- I2C VC Options (SetModelOptions / GetModelOptions).
    -- See docs/TransactionInterface.md
    --   SET_REPEATED_START  - I2cController only
    --   SET_NACK_INJECT     - I2cController (read-data bytes) and
    --                         I2cPeripheral (address / write-data bytes)
    --   SET_SCL_PERIOD      - I2cController only
    --   SET_TIMEOUT         - I2cController only
    ----------------------------------------------------------------------------
    type I2cOptionType is (
        SET_REPEATED_START,
        SET_NACK_INJECT,
        SET_SCL_PERIOD,
        SET_TIMEOUT
    );

    ----------------------------------------------------------------------------
    -- Setters
    ----------------------------------------------------------------------------
    -- One-time-use: makes the next Write/Read end with a repeated START
    -- (Sr) instead of STOP (P) (for a "write a register pointer, then read
    -- from it without releasing the bus" idiom, for instance). Consumed by
    -- the VC after one transfer and back to STOP.
    procedure SetRepeatedStart(
        signal   TransactionRec : inout I2cRecType;
        constant Value          : boolean
    );

    -- NACK injection: force a NACK on either the address byte or
    -- a data byte (by 0 based index) of the next transfer, one-time-use.
    procedure SetNackInjectAddress(
        signal TransactionRec : inout I2cRecType
    );

    procedure SetNackInjectDataByte(
        signal   TransactionRec : inout I2cRecType;
        constant ByteIndex      : natural
    );

    procedure SetSclPeriod(
        signal   TransactionRec : inout I2cRecType;
        constant Period         : time
    );

    -- Bus timeout (I2cController only): the longest the controller will
    -- wait for SCL to actually respond (release high) during START/STOP/Sr,
    -- byte transmit or ACK/NACK sampling, before Alerting FAILURE instead
    -- of hanging the simulation forever on a stuck bus.
    procedure SetTimeout(
        signal   TransactionRec : inout I2cRecType;
        constant Value          : time
    );

end package I2cTbPkg;

package body I2cTbPkg is

    procedure SetRepeatedStart(
        signal   TransactionRec : inout I2cRecType;
        constant Value          : boolean
    ) is
    begin
        SetModelOptions(TransactionRec,
                        I2cOptionType'pos(SET_REPEATED_START),
                        Value);
    end procedure SetRepeatedStart;

    procedure SetNackInjectAddress(
        signal TransactionRec : inout I2cRecType
    ) is
    begin
        SetModelOptions(TransactionRec,
                        I2cOptionType'pos(SET_NACK_INJECT),
                        -1);
    end procedure SetNackInjectAddress;

    procedure SetNackInjectDataByte(
        signal   TransactionRec : inout I2cRecType;
        constant ByteIndex      : natural
    ) is
    begin
        SetModelOptions(TransactionRec,
                        I2cOptionType'pos(SET_NACK_INJECT),
                        ByteIndex);
    end procedure SetNackInjectDataByte;

    procedure SetSclPeriod(
        signal   TransactionRec : inout I2cRecType;
        constant Period         : time
    ) is
    begin
        SetModelOptions(TransactionRec,
                        I2cOptionType'pos(SET_SCL_PERIOD),
                        Period);
    end procedure SetSclPeriod;

    procedure SetTimeout(
        signal   TransactionRec : inout I2cRecType;
        constant Value          : time
    ) is
    begin
        SetModelOptions(TransactionRec,
                        I2cOptionType'pos(SET_TIMEOUT),
                        Value);
    end procedure SetTimeout;

end package body I2cTbPkg;
