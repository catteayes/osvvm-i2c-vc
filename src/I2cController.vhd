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
--    08/2026   0.11       Fix WaitForClock using wrong delay
--    08/2026   0.11       Multi-master arbitration (#16)
--    08/2026   0.10       10-bit addressing (#15)
--    08/2026   0.9        Failed NACK injection alert
--    07/2026   0.8        SetSclPeriod and SetTimeout (#13)
--    07/2026   0.7        NACK injection (#12)
--    07/2026   0.5        Repeated START (Sr) (#11)
--    07/2026   0.4        Multi-byte write/read (#10)
--    07/2026   0.3        Read path: byte receive, controller-generated
--                         ACK/NACK, NACK-terminated single-byte read,
--                         READ_OP (#8)
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
    use osvvm.ScoreboardPkg_slv.all;

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
    -- Settable with SetSclPeriod.
    signal SclPeriod : time := SCL_PERIOD;
    signal tSclLow  : time := (SCL_PERIOD * 11) / 20;     -- 55%
    signal tSclHigh : time := SCL_PERIOD - (SCL_PERIOD * 11) / 20;  -- 45% = 1 - 0.55

    signal BusTimeout : time := 1 sec;

    -- Small, fixed delay between SCL falling and SDA changing for the next bit.
    -- This tries to mimic a real I2C controller's output-driver propagation delay.
    -- NXP UM10204 Table 11 bounds this two ways: tHD;DAT (min
    -- time old data must hold past SCL falling) is 0 ns for all three
    -- speed grades, so any nonnegative delay is legal; tVD;DAT/tVD;ACK
    -- (max time until new data must be valid) is tightest at Fast-mode-
    -- Plus, 450 ns. This constant is comfortably under that at every
    -- speed grade, and small enough that tSU;DAT (setup before SCL rises,
    -- at most 250 ns at Standard-mode) is easily met by whatever of
    -- tSclLow remains after it.
    constant tSdaChangeDelay : time := 200 ns;

    procedure WaitSclHigh(signal SCL : in std_logic) is
    begin
        wait until SCL = 'H' for BusTimeout;
        AlertIfNot(ModelID, SCL = 'H',
            "I2C bus timeout: SCL never released within " & to_string(BusTimeout, 1 ns),
            FAILURE
        );
    end procedure WaitSclHigh;

    procedure WaitForBusFree(signal SCL, SDA : in std_logic) is
    begin
        wait until rising_edge(SDA) and SCL = 'H';
        wait for tSclLow;
    end procedure WaitForBusFree;

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
        WaitSclHigh(SCL);
        wait for tSclHigh;  -- tSU;STO setup time before SDA rises
        SDA <= 'Z';
        wait for tSclLow;   -- tBUF bus free time before the next START
    end procedure I2cStop;

    -- Repeated START (Sr)
    procedure I2cRepeatedStart(signal SCL, SDA : inout std_logic) is
    begin
        wait for tSdaChangeDelay;
        SDA <= 'Z';
        wait for tSclLow - tSdaChangeDelay;
        SCL <= 'Z';
        WaitSclHigh(SCL);
        wait for tSclHigh;  -- tSU;STA setup time before SDA falls
        SDA <= '0';
        wait for tSclLow;   -- tHD;STA hold before the next byte's first low
        SCL <= '0';
    end procedure I2cRepeatedStart;

    -- Transmit one byte MSB-first, then release SDA on the 9th clock and
    -- sample the receiver's ACK ('0') / NACK ('1'). Also detects
    -- arbitration loss.
    procedure I2cSendByte(
        signal   SCL, SDA : inout std_logic;
        constant Byte     : in  std_logic_vector(7 downto 0);
        variable Acked    : out boolean;
        variable ArbLost  : out boolean
    ) is
    begin
        ArbLost := false;
        for BitIdx in 7 downto 0 loop
            -- Data changes only while SCL is low.
            wait for tSdaChangeDelay;
            SDA <= '0' when Byte(BitIdx) = '0' else 'Z';
            wait for tSclLow - tSdaChangeDelay;
            SCL <= 'Z';
            WaitSclHigh(SCL);

            if Byte(BitIdx) = '1' and to_x01(SDA) = '0' then
                ArbLost := true;
                SDA <= 'Z';
                SCL <= 'Z';
                Acked := false;
                return;
            end if;

            wait for tSclHigh;
            SCL <= '0';
        end loop;

        -- 9th clock: release SDA and sample ACK/NACK
        wait for tSdaChangeDelay;
        SDA <= 'Z';
        wait for tSclLow - tSdaChangeDelay;
        SCL <= 'Z';
        WaitSclHigh(SCL);
        Acked := (SDA = '0');
        wait for tSclHigh;
        SCL <= '0';
    end procedure I2cSendByte;

    -- Receive one byte MSB-first, then drive the 9th clock:
    -- ACK ('0') if more bytes are expected, NACK ('1'/released) if this is
    -- the last byte the controller wants.
    procedure I2cReceiveByte(
        signal   SCL, SDA : inout std_logic;
        variable Byte     : inout std_logic_vector(7 downto 0);
        constant IsLastByte : in    boolean
    ) is
    begin
        wait for tSdaChangeDelay;
        SDA <= 'Z';

        for BitIdx in 7 downto 0 loop
            -- We still generate SCL while receiving - only the data
            -- direction changes, not who owns the clock.
            wait for tSclLow - tSdaChangeDelay;
            SCL <= 'Z';
            WaitSclHigh(SCL);
            Byte(BitIdx) := to_x01(SDA);
            wait for tSclHigh;
            SCL <= '0';
            wait for tSdaChangeDelay;
        end loop;

        SDA <= 'Z' when IsLastByte else '0'; --ACK/NACK
        wait for tSclLow - tSdaChangeDelay;
        SCL <= 'Z';
        WaitSclHigh(SCL);
        wait for tSclHigh;
        SCL <= '0';
    end procedure I2cReceiveByte;

    -- Send the address phase of a transfer: 7-bit (one byte, Addr(6 downto 0)
    -- & R/W) or 10-bit. A 10-bit read always starts as a write-direction setup
    -- (2 bytes: "11110" + Addr(9:8) + W, then Addr(7:0)), then issues its own
    -- repeated START and resends the first byte with R/W=1 to switch direction.
    procedure I2cSendAddress(
        signal   SCL, SDA  : inout std_logic;
        constant Addr      : in  std_logic_vector(9 downto 0);
        constant AddrWidth : in  integer;
        constant IsRead    : in  boolean;
        variable Acked     : out boolean;
        variable ArbLost   : out boolean
    ) is
        variable AddrByte : std_logic_vector(7 downto 0);
    begin
        ArbLost := false;
        if AddrWidth > 7 then
            -- Byte 1: 11110 + Addr(9:8) + W - always write-direction first.
            AddrByte := "11110" & Addr(9 downto 8) & '0';
            I2cSendByte(SCL, SDA, AddrByte, Acked, ArbLost);
            if not ArbLost then
                AlertIfNot(ModelID, Acked,
                    "No ACK received for 10-bit address byte 1 " & to_hxstring(AddrByte),
                    ERROR
                );
                Log(ModelID, "10-bit address byte 1 " & to_hxstring(AddrByte) &
                    "  ACK=" & to_string(Acked), DEBUG);
            end if;

            if Acked and not ArbLost then
                AddrByte := Addr(7 downto 0);
                I2cSendByte(SCL, SDA, AddrByte, Acked, ArbLost);
                if not ArbLost then
                    AlertIfNot(ModelID, Acked,
                        "No ACK received for 10-bit address byte 2 " & to_hxstring(AddrByte),
                        ERROR
                    );
                    Log(ModelID, "10-bit address byte 2 " & to_hxstring(AddrByte) &
                        "  ACK=" & to_string(Acked), DEBUG);
                end if;
            end if;

            if Acked and not ArbLost and IsRead then
                I2cRepeatedStart(SCL, SDA);
                AddrByte := "11110" & Addr(9 downto 8) & '1';
                I2cSendByte(SCL, SDA, AddrByte, Acked, ArbLost);
                if not ArbLost then
                    AlertIfNot(ModelID, Acked,
                        "No ACK received for 10-bit address byte 3 (read direction) " & to_hxstring(AddrByte),
                        ERROR
                    );
                    Log(ModelID, "10-bit address byte 3 (read direction) " & to_hxstring(AddrByte) &
                        "  ACK=" & to_string(Acked), DEBUG);
                end if;
            end if;
        else
            AddrByte := Addr(6 downto 0) & '1' when IsRead else Addr(6 downto 0) & '0';
            I2cSendByte(SCL, SDA, AddrByte, Acked, ArbLost);
            if not ArbLost then
                AlertIfNot(ModelID, Acked,
                    "No ACK received for address " & to_hxstring(AddrByte(7 downto 1)),
                    ERROR
                );
                Log(ModelID, "Address byte " & to_hxstring(AddrByte) &
                    "  ACK=" & to_string(Acked), DEBUG);
            end if;
        end if;
    end procedure I2cSendAddress;

begin

    -- Internal record-dispatch reference clock
    I2cClk <= not I2cClk after SclPeriod / 2;

    -- Change tSclLow/tSclHigh whenever SetSclPeriod changes SclPeriod.
    tSclLow  <= (SclPeriod * 11) / 20;
    tSclHigh <= SclPeriod - tSclLow;

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
        variable Addr10   : std_logic_vector(9 downto 0);  -- 7-bit or 10-bit
        variable WData    : std_logic_vector(7 downto 0);
        variable RData    : std_logic_vector(7 downto 0);
        variable Acked    : boolean;
        variable NumBurstBytes : integer;
        variable RepeatedStartArmed : boolean := false;  -- set with SetRepeatedStart(TRUE)
        variable BusHeldBySr        : boolean := false;  -- true when the previous transfer ended with Sr
        variable NackInjectArmed     : boolean := false;
        variable NackInjectByteIndex : integer := -1;
        variable NackDataArmed       : boolean;  -- if this byte matches NackInjectByteIndex
        variable ArbRetryEnabled : boolean := false;
        variable ArbLost         : boolean;

        -- The whole message restarts from byte 0 for bursts. This is made
        -- as a procedure to allow its own local BurstBytes array to be able
        -- to be sized from the NumBurstBytes parameter. The burst is captured
        -- from WriteBurstFifo at the start, so a retry can always restart clean
        -- even though the FIFO itself only supports one destructive pass.
        procedure I2cWriteBurstWithRetry(
            signal   SCL, SDA      : inout std_logic;
            constant Addr10        : in    std_logic_vector(9 downto 0);
            constant AddrWidth     : in    integer;
            constant NumBurstBytes : in    integer;
            variable Acked         : out   boolean
        ) is
            type ByteArrayType is array (1 to NumBurstBytes) of std_logic_vector(7 downto 0);
            variable BurstBytes : ByteArrayType;
            variable ArbLost    : boolean;
        begin
            for i in 1 to NumBurstBytes loop
                BurstBytes(i) := SafeResize(ModelID, Pop(TransRec.WriteBurstFifo), 8);
            end loop;

            ArbRetryLoop : loop
                if BusHeldBySr then
                    BusHeldBySr := false;
                else
                    I2cStart(SCL, SDA);
                end if;

                I2cSendAddress(SCL, SDA, Addr10, AddrWidth, IsRead => false,
                    Acked => Acked, ArbLost => ArbLost);

                if Acked and not ArbLost then
                    for i in 1 to NumBurstBytes loop
                        I2cSendByte(SCL, SDA, BurstBytes(i), Acked, ArbLost);
                        if ArbLost then
                            exit;
                        end if;
                        AlertIfNot(ModelID, Acked,
                            "No ACK received for burst byte " & to_string(i) &
                            "/" & to_string(NumBurstBytes) & " (" & to_hxstring(BurstBytes(i)) & ")",
                            ERROR
                        );
                        Log(ModelID, "Write Burst byte " & to_string(i) & "/" & to_string(NumBurstBytes) &
                            " " & to_hxstring(BurstBytes(i)) & "  ACK=" & to_string(Acked), DEBUG);

                        exit when not Acked;
                    end loop;
                end if;

                if ArbLost then
                    Alert(ModelID, "Arbitration lost during WriteBurst", WARNING);
                    if ArbRetryEnabled then
                        WaitForBusFree(SCL, SDA);
                        next ArbRetryLoop;
                    end if;
                else
                    if RepeatedStartArmed and Acked then
                        I2cRepeatedStart(SCL, SDA);
                        BusHeldBySr := true;
                    else
                        I2cStop(SCL, SDA);
                    end if;
                    RepeatedStartArmed := false;
                end if;
                exit ArbRetryLoop;
            end loop ArbRetryLoop;
        end procedure I2cWriteBurstWithRetry;

        -- Same as the write side. Bytes are only pushed to the real
        -- ReadBurstFifo once, after the whole attempt is done.
        procedure I2cReadBurstWithRetry(
            signal   SCL, SDA      : inout std_logic;
            constant Addr10        : in    std_logic_vector(9 downto 0);
            constant AddrWidth     : in    integer;
            constant NumBurstBytes : in    integer;
            variable Acked         : out   boolean
        ) is
            type ByteArrayType is array (1 to NumBurstBytes) of std_logic_vector(7 downto 0);
            variable ReadBytes     : ByteArrayType;
            variable ArbLost       : boolean;
            variable RData         : std_logic_vector(7 downto 0);
            variable NackDataArmed : boolean;
        begin
            ArbRetryLoop : loop
                if BusHeldBySr then
                    BusHeldBySr := false;
                else
                    I2cStart(SCL, SDA);
                end if;

                I2cSendAddress(SCL, SDA, Addr10, AddrWidth, IsRead => true,
                    Acked => Acked, ArbLost => ArbLost);

                if Acked and not ArbLost then
                    for i in 1 to NumBurstBytes loop
                        -- NackInjectByteIndex is 0-based; i is 1-based.
                        NackDataArmed := NackInjectArmed and (NackInjectByteIndex = i - 1);

                        I2cReceiveByte(SCL, SDA, RData, IsLastByte => (i = NumBurstBytes) or NackDataArmed);
                        Log(ModelID, "Read Burst byte " & to_string(i) & "/" & to_string(NumBurstBytes) &
                            " " & to_hxstring(RData) &
                            "  ACK=" & to_string(not ((i = NumBurstBytes) or NackDataArmed)), DEBUG);
                        ReadBytes(i) := RData;

                        if NackDataArmed then
                            NackInjectArmed := false;  -- consumed
                            Alert(ModelID, "Read data byte NACK injected (index " &
                                to_string(i - 1) & "), ending read early", ERROR);
                            for FillIdx in i + 1 to NumBurstBytes loop
                                ReadBytes(FillIdx) := (others => '0');
                            end loop;
                            exit;
                        end if;
                    end loop;
                else
                    -- Fill placeholders
                    for i in 1 to NumBurstBytes loop
                        ReadBytes(i) := (others => '0');
                    end loop;
                end if;

                if ArbLost then
                    Alert(ModelID, "Arbitration lost during ReadBurst", WARNING);
                    if ArbRetryEnabled then
                        WaitForBusFree(SCL, SDA);
                        next ArbRetryLoop;
                    end if;
                else
                    if RepeatedStartArmed and Acked then
                        I2cRepeatedStart(SCL, SDA);
                        BusHeldBySr := true;
                    else
                        I2cStop(SCL, SDA);
                    end if;
                    RepeatedStartArmed := false;
                end if;
                exit ArbRetryLoop;
            end loop ArbRetryLoop;

            -- Push once, keeps ReadCheckBurstVector's Pop count satisfied even if there was
            -- an arbitration loss or an early NACK.
            for i in 1 to NumBurstBytes loop
                Push(TransRec.ReadBurstFifo, ReadBytes(i));
            end loop;
        end procedure I2cReadBurstWithRetry;
    begin
        wait on ModelID;  -- wait until initialized
        TransRec.WriteBurstFifo <= NewID("WriteBurstFifo", ModelID, Search => PRIVATE_NAME);
        TransRec.ReadBurstFifo <= NewID("ReadBurstFifo", ModelID, Search => PRIVATE_NAME);

        -- Idle bus state: both lines released (pulled high by the harness)
        SCL <= 'Z';
        SDA <= 'Z';

        TransactionDispatcherLoop : loop
            WaitForTransaction(
                Rdy => TransRec.Rdy,
                Ack => TransRec.Ack
            );

            case Operation is
                when WRITE_OP =>
                    -- 7-bit or 10-bit
                    Addr10 := SafeResize(ModelID, TransRec.Address, 10);
                    WData  := SafeResize(ModelID, TransRec.DataToModel, 8);

                    WriteArbRetryLoop : loop
                        if BusHeldBySr then
                            BusHeldBySr := false;
                        else
                            I2cStart(SCL, SDA);
                        end if;

                        I2cSendAddress(SCL, SDA, Addr10, TransRec.AddrWidth, IsRead => false,
                            Acked => Acked, ArbLost => ArbLost);

                        if Acked and not ArbLost then
                            I2cSendByte(SCL, SDA, WData, Acked, ArbLost);
                            if not ArbLost then
                                AlertIfNot(ModelID, Acked,
                                    "No ACK received for data " & to_hxstring(WData),
                                    ERROR
                                );
                                Log(ModelID, "Data byte " & to_hxstring(WData) &
                                    "  ACK=" & to_string(Acked), DEBUG);
                            end if;
                        end if;

                        if ArbLost then
                            Alert(ModelID, "Arbitration lost during Write", WARNING);
                            if ArbRetryEnabled then
                                WaitForBusFree(SCL, SDA);
                                next WriteArbRetryLoop;
                            end if;
                        else
                            if RepeatedStartArmed and Acked then
                                I2cRepeatedStart(SCL, SDA);
                                BusHeldBySr := true;
                            else
                                I2cStop(SCL, SDA);
                            end if;
                            RepeatedStartArmed := false;
                        end if;
                        exit WriteArbRetryLoop;
                    end loop WriteArbRetryLoop;

                    if NackInjectArmed then
                        NackInjectArmed := false;
                        Alert(ModelID, "Can't NACK inject on write (controller)", ERROR);
                    end if;

                    Log(ModelID,
                        "Write Operation, Address: " & to_hxstring(Addr10) &
                        "  Data: " & to_hxstring(WData) &
                        "  Operation# " & to_string(TransRec.Rdy),
                        INFO,
                        TransRec.StatusMsgOn
                    );

                when WRITE_BURST =>
                    -- 7-bit or 10-bit
                    -- One address phase followed by NumBurstBytes.
                    Addr10        := SafeResize(ModelID, TransRec.Address, 10);
                    NumBurstBytes := TransRec.DataWidth;

                    I2cWriteBurstWithRetry(SCL, SDA, Addr10, TransRec.AddrWidth, NumBurstBytes, Acked);

                    if NackInjectArmed then
                        NackInjectArmed := false;
                        Alert(ModelID, "Can't NACK inject on (burst) write (controller)", ERROR);
                    end if;

                    Log(ModelID,
                        "Write Burst Operation, Address: " & to_hxstring(Addr10) &
                        "  Length: " & to_string(NumBurstBytes) &
                        "  Operation# " & to_string(TransRec.Rdy),
                        INFO,
                        TransRec.StatusMsgOn
                    );

                when READ_OP =>
                    -- 7-bit or 10-bit
                    Addr10 := SafeResize(ModelID, TransRec.Address, 10);

                    ReadArbRetryLoop : loop
                        if BusHeldBySr then
                            BusHeldBySr := false;
                        else
                            I2cStart(SCL, SDA);
                        end if;

                        I2cSendAddress(SCL, SDA, Addr10, TransRec.AddrWidth, IsRead => true,
                            Acked => Acked, ArbLost => ArbLost);

                        if Acked and not ArbLost then
                            -- This byte is the last one: NACK it to stop.
                            I2cReceiveByte(SCL, SDA, RData, IsLastByte => true);
                            Log(ModelID, "Data byte " & to_hxstring(RData) &
                                "  NACK (end of read)", DEBUG);
                        elsif not ArbLost then
                            RData := (others => '0');
                        end if;

                        if ArbLost then
                            Alert(ModelID, "Arbitration lost during Read", WARNING);
                            if ArbRetryEnabled then
                                WaitForBusFree(SCL, SDA);
                                next ReadArbRetryLoop;
                            else
                                RData := (others => '0');
                            end if;
                        else
                            if RepeatedStartArmed and Acked then
                                I2cRepeatedStart(SCL, SDA);
                                BusHeldBySr := true;
                            else
                                I2cStop(SCL, SDA);
                            end if;
                            RepeatedStartArmed := false;
                        end if;
                        exit ReadArbRetryLoop;
                    end loop ReadArbRetryLoop;

                    if NackInjectArmed then
                        NackInjectArmed := false;
                        Alert(ModelID, "Can't NACK inject on (no burst) read (controller)", ERROR);
                    end if;

                    TransRec.DataFromModel <= SafeResize(ModelID, RData, TransRec.DataFromModel'length);

                    Log(ModelID,
                        "Read Operation, Address: " & to_hxstring(Addr10) &
                        "  Data: " & to_hxstring(RData) &
                        "  Operation# " & to_string(TransRec.Rdy),
                        INFO,
                        TransRec.StatusMsgOn
                    );

                when READ_BURST =>
                    -- 7-bit or 10-bit addressing
                    Addr10        := SafeResize(ModelID, TransRec.Address, 10);
                    NumBurstBytes := TransRec.DataWidth;

                    I2cReadBurstWithRetry(SCL, SDA, Addr10, TransRec.AddrWidth, NumBurstBytes, Acked);

                    if NackInjectArmed then
                        NackInjectArmed := false;
                        Alert(ModelID, "NACK injection (index " & to_string(NackInjectByteIndex) &
                            ") was armed but never applied during the last transaction (index out of range)",
                            ERROR);
                    end if;

                    Log(ModelID,
                        "Read Burst Operation, Address: " & to_hxstring(Addr10) &
                        "  Length: " & to_string(NumBurstBytes) &
                        "  Operation# " & to_string(TransRec.Rdy),
                        INFO,
                        TransRec.StatusMsgOn
                    );

                when SET_MODEL_OPTIONS =>
                    case TransRec.Options is
                        when I2cOptionType'pos(SET_REPEATED_START) =>
                            RepeatedStartArmed := TransRec.BoolToModel;
                            Log(ModelID, "Set Repeated Start = " &
                                to_string(TransRec.BoolToModel), INFO);

                        when I2cOptionType'pos(SET_NACK_INJECT) =>
                            NackInjectByteIndex := TransRec.IntToModel;
                            NackInjectArmed     := true;
                            Log(ModelID, "Set NACK Inject, ByteIndex = " &
                                to_string(TransRec.IntToModel), INFO);

                        when I2cOptionType'pos(SET_SCL_PERIOD) =>
                            SclPeriod <= TransRec.TimeToModel;
                            Log(ModelID, "Set SCL Period = " &
                                to_string(TransRec.TimeToModel, 1 ns), INFO);

                        when I2cOptionType'pos(SET_TIMEOUT) =>
                            BusTimeout <= TransRec.TimeToModel;
                            Log(ModelID, "Set Bus Timeout = " &
                                to_string(TransRec.TimeToModel, 1 ns), INFO);

                        when I2cOptionType'pos(SET_ARB_RETRY) =>
                            ArbRetryEnabled := TransRec.BoolToModel;
                            Log(ModelID, "Set Arbitration Auto-Retry = " &
                                to_string(TransRec.BoolToModel), INFO);

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

end architecture model;
