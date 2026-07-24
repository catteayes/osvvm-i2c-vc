--
--  File Name:         I2cController.vhd
--  Design Unit Name:  I2cController
--
--  Maintainer:        Mehmet Burak Aykenar    email: burak.aykenar@anadologic.com
--  Contributor(s):
--     <intern name>
--
--  Description:
--      I2C Controller (bus master) Verification Component.
--      Drives SCL/SDA as an I2C controller and executes OSVVM
--      Model Independent Transactions from the test sequencer.
--
--      Modeled on OsvvmLibraries/SPI_GuyEschemann/src/SpiController.vhd —
--      read that file first.
--
--  Revision History:
--    Date      Version    Description
--    07/2026   0.2        Bus engine: START/STOP, byte transmit, ACK sampling;
--                         WRITE_OP dispatch, 7-bit addressing (#6)
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

use work.I2cTbPkg.all;

entity I2cController is
    generic(
        MODEL_ID_NAME : string := "";
        SCL_PERIOD    : time   := I2C_SCL_PERIOD_400K
    );
    port(
        -- Transaction interface to the test sequencer
        TransRec : inout I2cRecType;
        -- I2C bus: open-drain — drive '0' or 'Z', never '1'.
        -- The testbench harness supplies the pull-ups ('H').
        SCL      : inout std_logic;
        SDA      : inout std_logic
    );
end entity I2cController;

architecture model of I2cController is

    -- Use MODEL_ID_NAME generic if set, otherwise use the instance label
    constant MODEL_INSTANCE_NAME : string := IfElse(MODEL_ID_NAME'length > 0,
                                                    MODEL_ID_NAME,
                                                    to_lower(PathTail(I2cController'PATH_NAME)));

    signal ModelID : AlertLogIDType;

    -- Free-running internal reference clock, used only to align the
    -- WaitForTransaction/WaitForClock record handshake. I2C's actual SCL is
    -- not continuous (it only toggles during a transaction and is released
    -- - i.e. pulled high - when idle), so the real bus clock is generated
    -- directly in the bus engine procedures below using tSclHigh/tSclLow.
    signal I2cClk : std_logic := '0';

    -- Instead of a per-mode lookup, one fixed r is chosen
    -- that works for all three predefined speed grades at once.
    -- For tLow = r * SCL_PERIOD and tHigh = (1-r) * SCL_PERIOD, NXP UM10204
    -- Table 10/11's tLOW/tHIGH minimums require, per mode:
    --   Standard (100K, 10 us):  r >= 4.7/10  = 0.47 ; r <= 1-4.0/10  = 0.60
    --   Fast     (400K, 2.5 us): r >= 1.3/2.5 = 0.52 ; r <= 1-0.6/2.5 = 0.76
    --   Fast+    (1M,   1 us):   r >= 0.5/1   = 0.50 ; r <= 1-0.26/1  = 0.74
    -- Intersecting all three gives a valid range of r in [0.52, 0.60],
    -- bound below by Fast-mode's tLOW minimum and above by Standard-mode's
    -- tHIGH minimum. 0.55 is close to the center of that, and thus was chosen.
    constant tSclLow  : time := (SCL_PERIOD * 11) / 20;     -- 55%
    constant tSclHigh : time := SCL_PERIOD - tSclLow;       -- 45% = 1 - 0.55

    -- Small, fixed delay between SCL falling and SDA changing for the next bit.
    -- This tries to mimic a real I2C controller's output-driver propagation delay.
    -- NXP UM10204 Table 11 bounds this two ways: tHD;DAT (min
    -- time old data must hold past SCL falling) is 0 ns for all three
    -- speed grades, so any nonnegative delay is legal; tVD;DAT/tVD;ACK
    -- (max time until new data must be valid) is tightest at Fast-mode-
    -- Plus, 450 ns - this constant is comfortably under that at every
    -- speed grade, and small enough that tSU;DAT (setup before SCL rises,
    -- at most 250 ns at Standard-mode) is easily met by whatever of
    -- tSclLow remains after it.
    constant tSdaChangeDelay : time := 50 ns;

    -- Open-drain only: every drive here is either '0' or 'Z'.
    -- Data (SDA) only changes while
    -- SCL is low and must be stable while SCL is high.

    -- START (or repeated START) condition: SDA transitions H->L while SCL
    -- is high. Before START: bus idle, SCL and SDA both released/high.
    procedure I2cStart(signal SCL, SDA : inout std_logic) is
    begin
        SDA <= '0';
        wait for tSclLow;  -- tHD;STA hold time before the first SCL low phase
        SCL <= '0';
    end procedure I2cStart;

    -- STOP condition: SDA transitions L->H while SCL is high.
    procedure I2cStop(signal SCL, SDA : inout std_logic) is
    begin
        wait for tSdaChangeDelay;
        SDA <= '0';
        wait for tSclLow - tSdaChangeDelay;
        SCL <= 'Z';
        wait until SCL = 'H';
        wait for tSclHigh;  -- tSU;STO setup time before SDA rises
        SDA <= 'Z';
        wait for tSclLow;   -- tBUF bus free time before the next START
    end procedure I2cStop;

    -- Transmit one byte MSB-first, then release SDA on the 9th clock and
    -- sample the receiver's ACK ('0') / NACK ('1').
    procedure I2cSendByte(
        signal   SCL, SDA : inout std_logic;
        constant Byte     : in  std_logic_vector(7 downto 0);
        variable Acked    : out boolean
    ) is
    begin
        for BitIdx in 7 downto 0 loop
            -- Data changes only while SCL is low.
            wait for tSdaChangeDelay;
            SDA <= '0' when Byte(BitIdx) = '0' else 'Z';
            wait for tSclLow - tSdaChangeDelay;
            SCL <= 'Z';
            wait until SCL = 'H';
            wait for tSclHigh;
            SCL <= '0';
        end loop;

        -- 9th clock: release SDA and sample ACK/NACK
        wait for tSdaChangeDelay;
        SDA <= 'Z';
        wait for tSclLow - tSdaChangeDelay;
        SCL <= 'Z';
        wait until SCL = 'H';
        Acked := (SDA = '0');
        wait for tSclHigh;
        SCL <= '0';
    end procedure I2cSendByte;

begin

    -- Internal record-dispatch reference clock
    I2cClk <= not I2cClk after SCL_PERIOD / 2;

    ----------------------------------------------------------------------------
    --  Initialize alerts and data structures
    ----------------------------------------------------------------------------
    Initialize : process
    begin
        ModelID <= NewID(MODEL_INSTANCE_NAME);
        wait;
    end process Initialize;

    ----------------------------------------------------------------------------
    --  Transaction dispatcher
    --  TODO(intern): WaitForTransaction loop decoding TransRec.Operation
    --  (WRITE_OP, READ_OP, burst variants, SetModelOptions, WaitForClock, ...)
    ----------------------------------------------------------------------------
    TransactionDispatcher : process
        alias Operation   : AddressBusOperationType is TransRec.Operation;
        variable AddrByte : std_logic_vector(7 downto 0);
        variable WData    : std_logic_vector(7 downto 0);
        variable Acked    : boolean;
    begin
        wait on ModelID;  -- wait until initialized

        -- Idle bus state: both lines released (pulled high by the harness)
        SCL <= 'Z';
        SDA <= 'Z';

        TransactionDispatcherLoop : loop
            WaitForTransaction(
                Clk => I2cClk,
                Rdy => TransRec.Rdy,
                Ack => TransRec.Ack
            );

            case Operation is
                when WRITE_OP =>
                    -- 7-bit addressing only; R/W bit '0' = write
                    AddrByte := SafeResize(ModelID, TransRec.Address, 7) & '0';
                    WData    := SafeResize(ModelID, TransRec.DataToModel, 8);

                    I2cStart(SCL, SDA);

                    -- Send address byte
                    I2cSendByte(SCL, SDA, AddrByte, Acked);
                    AlertIfNot(ModelID, Acked,
                        "No ACK received for address " & to_hxstring(AddrByte(7 downto 1)),
                        ERROR
                    );
                    Log(ModelID, "Address byte " & to_hxstring(AddrByte) &
                        "  ACK=" & to_string(Acked), DEBUG);

                    -- Send data byte
                    I2cSendByte(SCL, SDA, WData, Acked);
                    AlertIfNot(ModelID, Acked,
                        "No ACK received for data " & to_hxstring(WData),
                        ERROR
                    );
                    Log(ModelID, "Data byte " & to_hxstring(WData) &
                        "  ACK=" & to_string(Acked), DEBUG);

                    I2cStop(SCL, SDA);

                    Log(ModelID,
                        "Write Operation, Address: " & to_hxstring(AddrByte(7 downto 1)) &
                        "  Data: " & to_hxstring(WData) &
                        "  Operation# " & to_string(TransRec.Rdy),
                        INFO,
                        TransRec.StatusMsgOn
                    );

                when GET_ALERTLOG_ID =>
                    TransRec.IntFromModel <= integer(ModelID);

                when WAIT_FOR_CLOCK =>
                    WaitForClock(I2cClk, TransRec.IntToModel);

                when WAIT_FOR_TRANSACTION =>
                    wait for 0 ns;

                when MULTIPLE_DRIVER_DETECT =>
                    Alert(ModelID, "Multiple Drivers on Transaction Record." & "  Transaction # " & to_string(TransRec.Rdy), FAILURE);

                when others =>
                    Alert(ModelID, "Unimplemented Transaction: " & to_string(Operation), FAILURE);
            end case;
        end loop TransactionDispatcherLoop;
    end process TransactionDispatcher;

end architecture model;
