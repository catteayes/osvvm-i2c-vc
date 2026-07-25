--
--  File Name:         I2cPeripheral.vhd
--  Design Unit Name:  I2cPeripheral
--
--  Maintainer:        Mehmet Burak Aykenar    email: burak.aykenar@anadologic.com
--  Contributor(s):
--     <intern name>
--
--  Description:
--      I2C Peripheral (bus target/slave) Verification Component.
--      Responds on SCL/SDA as an addressed I2C target; the test sequencer
--      provides/checks data via OSVVM Model Independent Transactions.
--
--      Modeled on OsvvmLibraries/SPI_GuyEschemann/src/SpiPeripheral.vhd —
--      read that file first.
--
--  Revision History:
--    Date      Version    Description
--    07/2026   0.2        Bus engine: START/STOP detection, 7-bit address
--                         match, ACK generation, byte receive/transmit;
--                         WRITE_OP/READ_OP (#7)
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
    use osvvm.ScoreboardPkg_slv.all;

library osvvm_common;
    context osvvm_common.OsvvmCommonContext;

use work.I2cTbPkg.all;

entity I2cPeripheral is
    generic(
        MODEL_ID_NAME  : string := "";
        TARGET_ADDRESS : std_logic_vector(6 downto 0) := "1010000";  -- 0x50
        SCL_PERIOD     : time   := I2C_SCL_PERIOD_400K
    );
    port(
        -- Transaction interface to the test sequencer
        TransRec : inout I2cRecType;
        -- I2C bus: open-drain — drive '0' or 'Z', never '1'.
        -- The testbench harness supplies the pull-ups ('H').
        SCL      : inout std_logic;
        SDA      : inout std_logic
    );
end entity I2cPeripheral;

architecture model of I2cPeripheral is

    -- Use MODEL_ID_NAME generic if set, otherwise use the instance label
    constant MODEL_INSTANCE_NAME : string := IfElse(MODEL_ID_NAME'length > 0,
                                                    MODEL_ID_NAME,
                                                    to_lower(PathTail(I2cPeripheral'PATH_NAME)));

    signal ModelID : AlertLogIDType;

    -- Free-running internal reference clock, used only to align the
    -- WaitForTransaction/WaitForClock record handshake, like
    -- I2cController's I2cClk. The peripheral's real bus behavior below
    -- (BusEngine) never uses it: as a target, it reacts directly to the
    -- controller's actual SCL edges, not to any clock of its own.
    signal I2cClk : std_logic := '0';

    constant tSdaChangeDelay : time := 50 ns;

    -- Bytes the controller has written to this target, handed to the
    -- sequencer by a blocking WRITE_OP (GetWrite).
    signal ReceiveFifo  : osvvm.ScoreboardPkg_slv.ScoreboardIDType;
    signal ReceiveCount : integer := 0;

    -- Bytes the sequencer has queued (by READ_OP/SendRead) for the next
    -- controller read of this target.
    signal TransmitFifo         : osvvm.ScoreboardPkg_slv.ScoreboardIDType;
    signal TransmitRequestCount : integer := 0;
    signal TransmitDoneCount    : integer := 0;

begin

    -- Internal record-dispatch reference clock
    I2cClk <= not I2cClk after SCL_PERIOD / 2;

    -- This model never drives SCL (no clock stretching yet).
    SCL <= 'Z';

    ----------------------------------------------------------------------------
    --  Initialize alerts and data structures
    ----------------------------------------------------------------------------
    Initialize : process
        variable ID : AlertLogIDType;
    begin
        ID           := NewID(MODEL_INSTANCE_NAME);
        ModelID      <= ID;
        ReceiveFifo  <= NewID("ReceiveFifo", ID, ReportMode => DISABLED, Search => PRIVATE_NAME);
        TransmitFifo <= NewID("TransmitFifo", ID, ReportMode => DISABLED, Search => PRIVATE_NAME);
        wait;
    end process Initialize;

    ----------------------------------------------------------------------------
    --  Transaction dispatcher
    --  TODO(intern): WaitForTransaction loop — provide data for reads,
    --  receive/check data for writes, options (clock stretching, NACK
    --  injection), 10-bit addressing.
    ----------------------------------------------------------------------------
    TransactionDispatcher : process
        alias Operation  : AddressBusOperationType is TransRec.Operation;
        variable RxData  : std_logic_vector(7 downto 0);
        variable TxData  : std_logic_vector(7 downto 0);
    begin
        wait on ModelID;  -- wait until initialized

        TransactionDispatcherLoop : loop
            WaitForTransaction(
                Clk => I2cClk,
                Rdy => TransRec.Rdy,
                Ack => TransRec.Ack
            );

            case Operation is
                when WRITE_OP =>
                    -- Block until the controller has actually written a
                    -- matching address byte onto the bus.
                    if IsEmpty(ReceiveFifo) then
                        WaitForToggle(ReceiveCount);
                    end if;
                    RxData := Pop(ReceiveFifo);

                    TransRec.Address       <= SafeResize(ModelID, TARGET_ADDRESS, TransRec.Address'length);
                    TransRec.DataFromModel <= SafeResize(ModelID, RxData, TransRec.DataFromModel'length);

                    Log(ModelID,
                        "Write Operation, Address: " & to_hxstring(TARGET_ADDRESS) &
                        "  Data: " & to_hxstring(RxData),
                        INFO,
                        TransRec.StatusMsgOn
                    );

                when READ_OP =>
                    -- Hand the sequencer's byte to BusEngine and block until
                    -- it has actually been sent out to the controller.
                    TxData := SafeResize(ModelID, TransRec.DataToModel, 8);
                    Push(TransmitFifo, TxData);
                    Increment(TransmitRequestCount);
                    wait for 0 ns;  -- Ensure increment
                    wait until TransmitRequestCount = TransmitDoneCount;

                    TransRec.Address <= SafeResize(ModelID, TARGET_ADDRESS, TransRec.Address'length);

                    Log(ModelID,
                        "Read Operation, Address: " & to_hxstring(TARGET_ADDRESS) &
                        "  Data: " & to_hxstring(TxData),
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

    ----------------------------------------------------------------------------
    --  I2C bus engine
    ----------------------------------------------------------------------------
    BusEngine : process
        variable AddrByte  : std_logic_vector(7 downto 0);
        variable DataByte  : std_logic_vector(7 downto 0);
        variable Addressed : boolean;
        variable IsRead    : boolean;
    begin
        SDA <= 'Z';

        BusEngineLoop : loop
            -- START (or repeated START): SDA falls while SCL is high.
            -- This also doubles as "go idle on STOP" without any
            -- separate STOP handling.
            wait until falling_edge(SDA) and SCL = 'H';

            -- Address + R/W byte, MSB first, based on the controller's
            -- SCL rising edges.
            for BitIdx in 7 downto 0 loop
                wait until rising_edge(SCL);
                AddrByte(BitIdx) := to_x01(SDA);
            end loop;

            Addressed := (AddrByte(7 downto 1) = TARGET_ADDRESS);
            IsRead    := (AddrByte(0) = '1');

            -- ACK slot: drive '0' only if addressed, then release.
            wait until falling_edge(SCL);
            if Addressed then
                wait for tSdaChangeDelay;
                SDA <= '0';
            end if;
            wait until rising_edge(SCL);
            wait until falling_edge(SCL);
            wait for tSdaChangeDelay;
            SDA <= 'Z';

            if Addressed then
                if IsRead then
                    -- Byte transmit (read path): block until the sequencer
                    -- has queued data with READ_OP/SendRead.
                    if IsEmpty(TransmitFifo) then
                        WaitForToggle(TransmitRequestCount);
                    end if;
                    DataByte := Pop(TransmitFifo);

                    for BitIdx in 7 downto 0 loop
                        wait for tSdaChangeDelay;
                        SDA <= '0' when DataByte(BitIdx) = '0' else 'Z';
                        wait until rising_edge(SCL);
                        wait until falling_edge(SCL);
                    end loop;
                    wait for tSdaChangeDelay;
                    SDA <= 'Z';  -- release for the controller's ACK/NACK

                    wait until rising_edge(SCL);
                    Log(ModelID,
                        "Data byte " & to_hxstring(DataByte) &
                        "  Controller ACK=" & to_string(to_x01(SDA) = '0'),
                        DEBUG
                    );
                    wait until falling_edge(SCL);

                    Increment(TransmitDoneCount);
                else
                    -- Byte receive (write path): sample, ACK, release.
                    for BitIdx in 7 downto 0 loop
                        wait until rising_edge(SCL);
                        DataByte(BitIdx) := to_x01(SDA);
                    end loop;

                    wait until falling_edge(SCL);
                    wait for tSdaChangeDelay;
                    SDA <= '0';  -- ACK the data byte
                    wait until rising_edge(SCL);
                    wait until falling_edge(SCL);
                    wait for tSdaChangeDelay;
                    SDA <= 'Z';

                    Push(ReceiveFifo, DataByte);
                    Increment(ReceiveCount);
                end if;
            end if;
        end loop BusEngineLoop;
    end process BusEngine;

end architecture model;
