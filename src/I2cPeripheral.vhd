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
--    08/2026   0.8        Fix NACK/clock-stretch armed for a 10-bit read's
--                         data phase not working
--    08/2026   0.7        10-bit addressing (#15) and bug fix for clock stretching
--                         after an ACK bit
--    08/2026   0.6        Clock stretching (#14) and failed NACK injection alert
--    07/2026   0.5        NACK injection (#12)
--    07/2026   0.4        Repeated START (Sr) (#11)
--    07/2026   0.3        Multi-byte write/read (#10)
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
        -- 7-bit mode (default): only TARGET_ADDRESS(6 downto 0) is used,
        -- matching the address literal width a 7-bit test passes to
        -- Write/Read. 10-bit mode (#15): set TEN_BIT_ADDR => true and use
        -- the full 10 bits.
        TARGET_ADDRESS : std_logic_vector(9 downto 0) := "0001010000";  -- 0x50 (7-bit)
        TEN_BIT_ADDR   : boolean := false;
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

    constant tSdaChangeDelay : time := 200 ns;

    -- Bytes the controller has written to this target, handed to the
    -- sequencer by a blocking WRITE_OP (GetWrite).
    signal ReceiveFifo  : osvvm.ScoreboardPkg_slv.ScoreboardIDType;
    signal ReceiveCount : integer := 0;

    -- Bytes the sequencer has queued (by READ_OP/SendRead) for the next
    -- controller read of this target.
    signal TransmitFifo         : osvvm.ScoreboardPkg_slv.ScoreboardIDType;
    signal TransmitRequestCount : integer := 0;
    signal TransmitDoneCount    : integer := 0;

    -- One-time-use: -1 = NACK the address byte, >=0 = NACK that 0-based
    -- (write) data byte index. Driven by TransactionDispatcher, BusEngine
    -- only reads these.
    signal NackInjectByteIndex    : integer := -1;
    signal NackInjectRequestCount : integer := 0;

    -- Clock stretch (#14), one-time-use for the next transaction only.
    -- Index = ByteNum*9 + BitPos (ByteNum 0-based, 0 = address byte;
    -- BitPos 0-7 = data bit MSB-first, 8 = ACK/NACK). Driven by
    -- TransactionDispatcher, BusEngine only reads these. Delay is set
    -- first, then Index (arming happens while setting Index).
    signal ClockStretchDelay        : time    := 0 ns;
    signal ClockStretchIndex        : integer := -1;
    signal ClockStretchRequestCount : integer := 0;

begin

    -- Internal record-dispatch reference clock
    I2cClk <= not I2cClk after SCL_PERIOD / 2;

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

                when SET_MODEL_OPTIONS =>
                    case TransRec.Options is
                        when I2cOptionType'pos(SET_NACK_INJECT) =>
                            NackInjectByteIndex    <= TransRec.IntToModel;
                            NackInjectRequestCount <= NackInjectRequestCount + 1;
                            Log(ModelID, "Set NACK Inject, ByteIndex = " &
                                to_string(TransRec.IntToModel), INFO);

                        when I2cOptionType'pos(SET_CLOCK_STRETCH_DELAY) =>
                            ClockStretchDelay <= TransRec.TimeToModel;
                            Log(ModelID, "Set Clock Stretch Delay = " &
                                to_string(TransRec.TimeToModel, 1 ns), INFO);

                        when I2cOptionType'pos(SET_CLOCK_STRETCH_INDEX) =>
                            ClockStretchIndex        <= TransRec.IntToModel;
                            ClockStretchRequestCount <= ClockStretchRequestCount + 1;
                            Log(ModelID, "Set Clock Stretch Index = " &
                                to_string(TransRec.IntToModel), INFO);

                        when others =>
                            Alert(ModelID, "Unimplemented Option: " &
                                to_string(I2cOptionType'val(TransRec.Options)),
                                FAILURE);
                    end case;

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
        variable Addr2     : std_logic_vector(7 downto 0);  -- 10-bit addressing's second byte
        variable DataByte  : std_logic_vector(7 downto 0);
        variable Addressed : boolean;
        variable IsRead    : boolean;

        variable SrDetected : boolean := false;

        variable ControllerAcked : boolean;
        variable AddressNacked : boolean;
        variable DataNacked    : boolean;
        variable WriteByteIdx  : integer;  -- 0-based
        variable NackArmed         : boolean := false;
        variable NackByteIndexCopy : integer := -1;
        variable SeenNackRequests  : integer := 0;

        variable StretchArmed        : boolean := false;
        variable StretchIndexCopy    : integer := -1;
        variable StretchDelayCopy    : time    := 0 ns;
        variable StretchByteNum      : integer := -1;  -- Index / 9
        variable StretchBitPos       : integer := -1;  -- Index mod 9
        variable SeenStretchRequests : integer := 0;
        -- Byte position for this transaction: 0 = address byte,
        -- 1/2/3... = the 1st/2nd/3rd data byte.
        variable TransferByteNum : integer := 0;

        variable TenBitReadAddressPhase : boolean := false;

        -- Holds SCL low an extra StretchDelayCopy right after BitPos of the
        -- current byte (TransferByteNum), if that's what was armed for this
        -- transaction. A no-op (no wait) otherwise, so it's safe to
        -- call after every bit.
        procedure MaybeStretch(constant BitPos : integer; constant AlreadyElapsed : time := 0 ns) is
        begin
            if StretchArmed and StretchByteNum = TransferByteNum and StretchBitPos = BitPos then
                StretchArmed := false;  -- consumed
                SCL <= '0';
                if StretchDelayCopy > AlreadyElapsed then
                    wait for StretchDelayCopy - AlreadyElapsed;
                end if;
                SCL <= 'Z';
                Log(ModelID, "Clock stretch: held SCL low for " &
                    to_string(StretchDelayCopy, 1 ns) & " after byte " &
                    to_string(TransferByteNum) & " bit " & to_string(BitPos),
                    INFO);
            end if;
        end procedure MaybeStretch;
    begin
        SDA <= 'Z';
        SCL <= 'Z';

        BusEngineLoop : loop
            -- START (or repeated START): SDA falls while SCL is high.
            -- This also doubles as "go idle on STOP" without any
            -- separate STOP handling.
            if SrDetected then
                SrDetected := false;
            else
                wait until falling_edge(SDA) and SCL = 'H';
            end if;

            TenBitReadAddressPhase := false;

            TransferByteNum := 0;
            if ClockStretchRequestCount /= SeenStretchRequests then
                SeenStretchRequests := ClockStretchRequestCount;
                StretchIndexCopy    := ClockStretchIndex;
                StretchDelayCopy    := ClockStretchDelay;
                StretchByteNum      := StretchIndexCopy / 9;
                StretchBitPos       := StretchIndexCopy mod 9;
                StretchArmed        := true;
            end if;

            -- Address + R/W byte, MSB first, based on the controller's
            -- SCL rising edges.
            for BitIdx in 7 downto 0 loop
                wait until rising_edge(SCL);
                AddrByte(BitIdx) := to_x01(SDA);
                wait until falling_edge(SCL);
                MaybeStretch(7 - BitIdx);
            end loop;

            -- 10-bit addressing: this first byte is always the "11110" + Addr(9:8)
            -- + R/W prefix. For a write, R/W=0 and a second (8-bit) address byte
            -- follows. For a read, this is the third byte.
            if TEN_BIT_ADDR then
                Addressed := (AddrByte(7 downto 3) = "11110")
                         and (AddrByte(2 downto 1) = TARGET_ADDRESS(9 downto 8));
            else
                Addressed := (AddrByte(7 downto 1) = TARGET_ADDRESS(6 downto 0));
            end if;
            IsRead := (AddrByte(0) = '1');

            if NackInjectRequestCount /= SeenNackRequests then
                SeenNackRequests  := NackInjectRequestCount;
                NackByteIndexCopy := NackInjectByteIndex;
                NackArmed         := true;
            end if;
            AddressNacked := Addressed and NackArmed and (NackByteIndexCopy = -1);

            if Addressed and not AddressNacked then
                wait for tSdaChangeDelay;
                SDA <= '0';
            end if;
            wait until rising_edge(SCL);
            wait until falling_edge(SCL);
            wait for tSdaChangeDelay;
            SDA <= 'Z';
            MaybeStretch(8, AlreadyElapsed => tSdaChangeDelay);  -- after the address byte's ACK/NACK bit

            if AddressNacked then
                NackArmed := false;  -- consumed
                Log(ModelID, "Address NACK injected: " &
                    to_hxstring(AddrByte(7 downto 1)), INFO);
            end if;

            -- 10-bit addressing: a write direction setup (R/W=0 on
            -- that first byte) still needs its second 8-bit address
            -- byte. A read-direction byte (after Sr) has no second byte,
            -- so data starts immediately, same as 7-bit mode.
            if Addressed and not AddressNacked and TEN_BIT_ADDR and not IsRead then
                for BitIdx in 7 downto 0 loop
                    wait until rising_edge(SCL);
                    Addr2(BitIdx) := to_x01(SDA);
                    wait until falling_edge(SCL);
                end loop;

                Addressed := (Addr2 = TARGET_ADDRESS(7 downto 0));

                if Addressed then
                    wait for tSdaChangeDelay;
                    SDA <= '0';
                end if;
                wait until rising_edge(SCL);
                wait until falling_edge(SCL);
                wait for tSdaChangeDelay;
                SDA <= 'Z';
            end if;

            if Addressed and not AddressNacked then
                WriteByteIdx     := 0;
                TransferByteNum  := 1;  -- first data byte
                if IsRead then
                    -- Sends bytes until controller NACKs
                    ReadLoop : loop
                        if IsEmpty(TransmitFifo) then
                            WaitForToggle(TransmitRequestCount);
                        end if;
                        DataByte := Pop(TransmitFifo);

                        for BitIdx in 7 downto 0 loop
                            SDA <= '0' when DataByte(BitIdx) = '0' else 'Z';
                            wait until rising_edge(SCL);
                            wait until falling_edge(SCL);
                            wait for tSdaChangeDelay;
                            MaybeStretch(7 - BitIdx, AlreadyElapsed => tSdaChangeDelay);
                        end loop;
                        SDA <= 'Z';  -- release for the controller's ACK/NACK

                        wait until rising_edge(SCL);
                        ControllerAcked := (to_x01(SDA) = '0');
                        Log(ModelID,
                            "Data byte " & to_hxstring(DataByte) &
                            "  Controller ACK=" & to_string(ControllerAcked),
                            DEBUG
                        );
                        wait until falling_edge(SCL);
                        MaybeStretch(8);

                        Increment(TransmitDoneCount);
                        TransferByteNum := TransferByteNum + 1;

                        exit ReadLoop when not ControllerAcked;
                    end loop ReadLoop;
                else
                    -- Receives bytes until controller stops instead of sending a new one.
                    WriteLoop : loop
                        wait until rising_edge(SCL);
                        DataByte(7) := to_x01(SDA);
                        wait until falling_edge(SCL) or (SDA'event and SCL = 'H');
                        if SCL = 'H' then
                            -- SDA fell => Sr, another transfer follows immediately
                            -- with no idle gap in between (see SrDetected above).
                            -- SDA rose => STOP, go idle as before.
                            SrDetected := (to_x01(SDA) = '0');
                            if TEN_BIT_ADDR and SrDetected then
                                TenBitReadAddressPhase := true;
                            end if;
                            exit WriteLoop;
                        end if;
                        MaybeStretch(0);  -- after bit 7/MSB (confirmed not Sr/Stop)

                        for BitIdx in 6 downto 0 loop
                            wait until rising_edge(SCL);
                            DataByte(BitIdx) := to_x01(SDA);
                            wait until falling_edge(SCL);
                            MaybeStretch(7 - BitIdx);
                        end loop;

                        if NackInjectRequestCount /= SeenNackRequests then
                            SeenNackRequests  := NackInjectRequestCount;
                            NackByteIndexCopy := NackInjectByteIndex;
                            NackArmed         := true;
                        end if;
                        DataNacked := NackArmed and (NackByteIndexCopy = WriteByteIdx);

                        wait for tSdaChangeDelay;
                        if not DataNacked then
                            SDA <= '0';  -- ACK the data byte
                        end if;
                        wait until rising_edge(SCL);
                        wait until falling_edge(SCL);
                        wait for tSdaChangeDelay;
                        SDA <= 'Z';
                        MaybeStretch(8, AlreadyElapsed => tSdaChangeDelay);
                        TransferByteNum := TransferByteNum + 1;

                        if DataNacked then
                            NackArmed := false;  -- consumed
                            Log(ModelID, "Data byte " & to_hxstring(DataByte) &
                                " NACK injected (index " & to_string(WriteByteIdx) & ")",
                                INFO);
                            exit WriteLoop;  -- Stop receiving after NACKing data
                        end if;

                        Push(ReceiveFifo, DataByte);
                        Increment(ReceiveCount);
                        WriteByteIdx := WriteByteIdx + 1;
                    end loop WriteLoop;
                end if;
            end if;

            if not TenBitReadAddressPhase then
                if NackArmed then
                    NackArmed := false;
                    Alert(ModelID, "NACK injection (index " & to_string(NackByteIndexCopy) &
                        ") was armed but never applied during the last transaction", ERROR);
                end if;

                if StretchArmed then
                    StretchArmed := false;
                    Alert(ModelID, "Clock stretch (index " & to_string(StretchIndexCopy) &
                        ") was armed but never applied during the last transaction", ERROR);
                end if;
            end if;
        end loop BusEngineLoop;
    end process BusEngine;

end architecture model;
