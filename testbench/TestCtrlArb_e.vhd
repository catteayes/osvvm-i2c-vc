--
--  File Name:         TestCtrlArb_e.vhd
--  Design Unit Name:  TestCtrlArb
--
--  Maintainer:        Mehmet Burak Aykenar    email: burak.aykenar@anadologic.com
--  Contributor(s):
--     <intern name>
--
--  Description:
--      Test sequencer entity for multi-master arbitration testbench
--      (#16): two independent I2cController instances trying for the
--      same bus, with one I2cPeripheral.
--
--  Revision History:
--    Date      Version    Description
--    08/2026   0.1        Initial skeleton (#16)
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
    use std.textio.all;

library osvvm;
    context osvvm.OsvvmContext;

library osvvm_i2c;
    context osvvm_i2c.I2cContext;

entity TestCtrlArb is
    port(
        -- Record Interfaces
        I2cController1Rec : inout I2cRecType;
        I2cController2Rec : inout I2cRecType;
        I2cPeripheralRec  : inout I2cRecType;
        -- Global Signal Interface
        Clk               : in    std_logic;
        n_Reset           : in    std_logic
    );
end entity TestCtrlArb;
