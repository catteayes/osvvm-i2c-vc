--
--  File Name:         I2cComponentPkg.vhd
--  Design Unit Name:  I2cComponentPkg
--
--  Maintainer:        Mehmet Burak Aykenar    email: burak.aykenar@anadologic.com
--  Contributor(s):
--     <intern name>
--
--  Description:
--      Component declarations for the I2C verification components.
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

use work.I2cTbPkg.all;

package I2cComponentPkg is

    component I2cController is
        generic(
            MODEL_ID_NAME : string := "";
            SCL_PERIOD    : time   := I2C_SCL_PERIOD_400K
        );
        port(
            TransRec : inout I2cRecType;
            SCL      : inout std_logic;
            SDA      : inout std_logic
        );
    end component I2cController;

    component I2cPeripheral is
        generic(
            MODEL_ID_NAME  : string := "";
            TARGET_ADDRESS : std_logic_vector(6 downto 0) := "1010000"
        );
        port(
            TransRec : inout I2cRecType;
            SCL      : inout std_logic;
            SDA      : inout std_logic
        );
    end component I2cPeripheral;

end package I2cComponentPkg;
