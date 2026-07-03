--
--  File Name:         TbI2c.vhd
--  Design Unit Name:  TbI2c
--
--  Maintainer:        Mehmet Burak Aykenar    email: burak.aykenar@anadologic.com
--  Contributor(s):
--     <intern name>
--
--  Description:
--      Test harness: I2cController and I2cPeripheral connected over an
--      open-drain SCL/SDA bus with pull-ups, plus the TestCtrl sequencer.
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

entity TbI2c is
end entity TbI2c;

architecture TestHarness of TbI2c is

    -- Test Bench Constants
    constant tperiod_Clk : time := 10 ns;
    constant tpd         : time := 2 ns;

    -- Global Signals
    signal Clk     : std_logic;
    signal n_Reset : std_logic;

    -- Testbench Control Records
    signal I2cControllerRec : I2cRecType;
    signal I2cPeripheralRec : I2cRecType;

    -- I2C Bus
    signal SCL : std_logic;
    signal SDA : std_logic;

    component TestCtrl
        port(
            I2cControllerRec : inout I2cRecType;
            I2cPeripheralRec : inout I2cRecType;
            Clk              : in    std_logic;
            n_Reset          : in    std_logic
        );
    end component;

begin

    ------------------------------------------------------------
    -- Bus pull-ups: VCs drive only '0' or 'Z' (open-drain);
    -- the weak 'H' here resolves to high when nobody drives.
    ------------------------------------------------------------
    SCL <= 'H';
    SDA <= 'H';

    ------------------------------------------------------------
    -- Clock and Reset
    ------------------------------------------------------------
    CreateClock(
        Clk    => Clk,
        Period => tperiod_Clk
    );

    CreateReset(
        Reset       => n_Reset,
        ResetActive => '0',
        Clk         => Clk,
        Period      => 7 * tperiod_Clk,
        tpd         => tpd
    );

    ------------------------------------------------------------
    -- I2C Verification Components
    ------------------------------------------------------------
    I2cController_1 : I2cController
        port map(
            TransRec => I2cControllerRec,
            SCL      => SCL,
            SDA      => SDA
        );

    I2cPeripheral_1 : I2cPeripheral
        port map(
            TransRec => I2cPeripheralRec,
            SCL      => SCL,
            SDA      => SDA
        );

    ------------------------------------------------------------
    -- Test Sequencer
    ------------------------------------------------------------
    TestCtrl_1 : TestCtrl
        port map(
            I2cControllerRec => I2cControllerRec,
            I2cPeripheralRec => I2cPeripheralRec,
            Clk              => Clk,
            n_Reset          => n_Reset
        );

end architecture TestHarness;
