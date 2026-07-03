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

entity I2cPeripheral is
    generic(
        MODEL_ID_NAME  : string := "";
        TARGET_ADDRESS : std_logic_vector(6 downto 0) := "1010000"  -- 0x50
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

    constant MODEL_INSTANCE_NAME : string := IfElse(MODEL_ID_NAME'length > 0,
                                                    MODEL_ID_NAME,
                                                    to_lower(PathTail(I2cPeripheral'PATH_NAME)));

    signal ModelID : AlertLogIDType;

begin

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
    --  TODO(intern): WaitForTransaction loop — provide data for reads,
    --  receive/check data for writes, options (clock stretching, NACK
    --  injection), 10-bit addressing.
    ----------------------------------------------------------------------------
    TransactionDispatcher : process
    begin
        wait on ModelID;  -- wait until initialized
        Log(ModelID, "I2cPeripheral skeleton — no transaction handling implemented yet", ALWAYS);
        -- TODO(intern): loop { WaitForTransaction; case TransRec.Operation ... }
        wait;
    end process TransactionDispatcher;

    ----------------------------------------------------------------------------
    --  I2C bus engine
    --  TODO(intern): START/STOP detection, address matching (7- and 10-bit),
    --  ACK generation, byte receive/transmit, optional clock stretching.
    ----------------------------------------------------------------------------
    SCL <= 'Z';
    SDA <= 'Z';

end architecture model;
