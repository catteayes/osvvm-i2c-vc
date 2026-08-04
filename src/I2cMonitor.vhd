--
--  File Name:         I2cMonitor.vhd
--  Design Unit Name:  I2cMonitor
--
--  Maintainer:        Mehmet Burak Aykenar    email: burak.aykenar@anadologic.com
--  Contributor(s):
--     <intern name>
--
--  Description:
--      I2C Bus Monitor Verification Component. Passive: it doesn't drive
--      SCL/SDA, only observes them. It reconstructs transactions' address
--      bytes and data bytes from the wire and puts them into its scoreboard
--      (MonitorScoreboardID). A test can Push expected bytes and let Check
--      compare them automatically. Alerts on protocol legality violations:
--      - SDA changing while SCL is high, when it isn't a START/STOP/Sr
--      - Data continuing on the bus after a NACK, which should have ended
--        the transaction (Sr/STOP)
--      - SCL clock count since the last START/Sr must be a multiple of 9
--        (8 bits + ACK)
--
--      This enables checking any DUT independent of the active VCs.
--
--  Revision History:
--    Date      Version    Description
--    08/2026   0.2        Fix NACK'ing at the first address byte for 10-bit
--                         addressing
--    08/2026   0.1        Initial bus monitor VC (#17)
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

entity I2cMonitor is
    generic(
        MODEL_ID_NAME : string := ""
    );
    port(
        -- Aren't driven.
        SCL : in std_logic;
        SDA : in std_logic;

        ModelID             : out AlertLogIDType;
        MonitorScoreboardID : out osvvm.ScoreboardPkg_slv.ScoreboardIDType;
        TransactionCount    : out integer
    );
end entity I2cMonitor;

architecture model of I2cMonitor is

    -- Use MODEL_ID_NAME generic if set, otherwise use the instance label
    constant MODEL_INSTANCE_NAME : string := IfElse(MODEL_ID_NAME'length > 0,
                                                    MODEL_ID_NAME,
                                                    to_lower(PathTail(I2cMonitor'PATH_NAME)));

    signal LocalModelID          : AlertLogIDType;
    signal LocalScoreboardID     : osvvm.ScoreboardPkg_slv.ScoreboardIDType;
    signal LocalTransactionCount : integer := 0;

begin

    ModelID             <= LocalModelID;
    MonitorScoreboardID <= LocalScoreboardID;
    TransactionCount    <= LocalTransactionCount;

    ----------------------------------------------------------------------------
    --  Initialize alerts and the scoreboard
    ----------------------------------------------------------------------------
    Initialize : process
        variable ID : AlertLogIDType;
    begin
        ID := NewID(MODEL_INSTANCE_NAME);
        LocalModelID      <= ID;
        LocalScoreboardID <= NewID("I2cMonitorScoreboard", ID, Search => PRIVATE_NAME);
        wait;
    end process Initialize;

    ----------------------------------------------------------------------------
    --  SCL clock count since the last START/Sr must be a multiple of 9 (8 bits + ACK)
    ----------------------------------------------------------------------------
    FramingMonitor : process
        variable TransactionEdgeCount  : integer := 0;
        -- To skip the first transaction (0 mod 9 = 0)
        variable HaveSeenTransaction   : boolean := false;
    begin
        loop
            wait until rising_edge(SCL) or SDA'event;

            if rising_edge(SCL) then
                TransactionEdgeCount := TransactionEdgeCount + 1;

            elsif falling_edge(SDA) and SCL = 'H' then
                -- START or repeated START
                if HaveSeenTransaction then
                    AlertIfNot(LocalModelID, TransactionEdgeCount mod 9 = 1,
                        "Framing violation: " & to_string(TransactionEdgeCount) &
                        " SCL clocks since the last START/Sr - expected 9*N + 1 (8 bits + ACK and STOP/Sr's release)",
                        ERROR
                    );
                end if;
                TransactionEdgeCount := 0;
                HaveSeenTransaction  := true;

            elsif rising_edge(SDA) and SCL = 'H' then
                -- STOP
                AlertIfNot(LocalModelID, TransactionEdgeCount mod 9 = 1,
                    "Framing violation: " & to_string(TransactionEdgeCount) &
                    " SCL clocks since the last START/Sr - expected 9*N + 1 (8 bits + ACK and STOP/Sr's release)",
                    ERROR
                );
            end if;
        end loop;
    end process FramingMonitor;

    ----------------------------------------------------------------------------
    --  Passive bus monitor
    ----------------------------------------------------------------------------
    BusMonitor : process
        variable AddrByte : std_logic_vector(7 downto 0);
        variable DataByte : std_logic_vector(7 downto 0);
        variable AckValue : std_logic;

        procedure SampleBit(
            variable Byte   : inout std_logic_vector(7 downto 0);
            constant BitIdx : in    integer
        ) is
        begin
            wait until rising_edge(SCL);
            Byte(BitIdx) := to_x01(SDA);
            wait until falling_edge(SCL) or SDA'event;
            AlertIfNot(LocalModelID, not (SCL = 'H' and SDA'event),
                "Protocol violation: SDA changed while SCL was high (data must be stable while SCL is high)",
                ERROR
            );
            if SCL = 'H' then
                wait until falling_edge(SCL);
            end if;
        end procedure SampleBit;

        procedure CheckAckBit(variable Ack : out std_logic) is
        begin
            wait until rising_edge(SCL);
            Ack := to_x01(SDA);
            wait until falling_edge(SCL) or SDA'event;
            AlertIfNot(LocalModelID, not (SCL = 'H' and SDA'event),
                "Protocol violation: SDA changed while SCL was high (data must be stable while SCL is high)",
                ERROR
            );
            if SCL = 'H' then
                wait until falling_edge(SCL);
            end if;
        end procedure CheckAckBit;

    begin
        MonitorLoop : loop
            -- START (or repeated START): SDA falls while SCL is high.
            wait until falling_edge(SDA) and SCL = 'H';

            -- Address + R/W byte, MSB first.
            for BitIdx in 7 downto 0 loop
                SampleBit(AddrByte, BitIdx);
            end loop;

            if not IsEmpty(LocalScoreboardID) then
                Check(LocalScoreboardID, AddrByte);
            end if;

            CheckAckBit(AckValue);

            -- 10-bit addressing
            if AddrByte(7 downto 3) = "11110" and AddrByte(0) = '0' and AckValue = '0' then
                for BitIdx in 7 downto 0 loop
                    SampleBit(AddrByte, BitIdx);
                end loop;

                if not IsEmpty(LocalScoreboardID) then
                    Check(LocalScoreboardID, AddrByte);
                end if;

                CheckAckBit(AckValue);
            end if;

            -- Data bytes until STOP or a repeated START.
            ByteLoop : loop
                wait until rising_edge(SCL);
                DataByte(7) := to_x01(SDA);
                wait until falling_edge(SCL) or (SDA'event and SCL = 'H');
                exit ByteLoop when SCL = 'H';
                
                AlertIfNot(LocalModelID, AckValue = '0',
                    "ACK position violation: bus continued past a NACK - " &
                    "the transaction should have ended with a repeated START or STOP",
                    ERROR
                );

                for BitIdx in 6 downto 0 loop
                    SampleBit(DataByte, BitIdx);
                end loop;
                if not IsEmpty(LocalScoreboardID) then
                    Check(LocalScoreboardID, DataByte);
                end if;

                CheckAckBit(AckValue);
            end loop ByteLoop;

            Increment(LocalTransactionCount);
        end loop MonitorLoop;
    end process BusMonitor;

end architecture model;
