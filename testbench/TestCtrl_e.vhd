--
--  File Name:         TestCtrl_e.vhd
--  Design Unit Name:  TestCtrl
--
--  Maintainer:        Mehmet Burak Aykenar    email: burak.aykenar@anadologic.com
--  Contributor(s):
--     <intern name>
--
--  Description:
--      Test sequencer entity for the I2C testbench.
--      Each test case is an architecture of this entity in its own file
--      (TbI2c_<TestName>.vhd), following the OSVVM test-per-architecture
--      pattern — see OsvvmLibraries/SPI_GuyEschemann/testbench.
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
    use std.textio.all;

library osvvm;
    context osvvm.OsvvmContext;

library osvvm_i2c;
    context osvvm_i2c.I2cContext;

entity TestCtrl is
    port(
        -- Record Interfaces
        I2cControllerRec : inout I2cRecType;
        I2cPeripheralRec : inout I2cRecType;
        -- Global Signal Interface
        Clk              : in    std_logic;
        n_Reset          : in    std_logic
    );
end entity TestCtrl;
