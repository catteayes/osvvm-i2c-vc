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
    --  TODO(intern): WaitForTransaction loop decoding TransRec.Operation
    --  (WRITE_OP, READ_OP, burst variants, SetModelOptions, WaitForClock, ...)
    ----------------------------------------------------------------------------
    TransactionDispatcher : process
    begin
        wait on ModelID;  -- wait until initialized
        Log(ModelID, "I2cController skeleton — no transaction handling implemented yet", ALWAYS);
        -- TODO(intern): loop { WaitForTransaction; case TransRec.Operation ... }
        wait;
    end process TransactionDispatcher;

    ----------------------------------------------------------------------------
    --  I2C bus engine
    --  TODO(intern): START / STOP / repeated START generation, byte
    --  transmit/receive with ACK/NACK sampling, clock stretching support,
    --  arbitration monitoring.
    ----------------------------------------------------------------------------
    SCL <= 'Z';
    SDA <= 'Z';

end architecture model;
