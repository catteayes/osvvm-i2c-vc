--
--  File Name:         TbI2cArb.vhd
--  Design Unit Name:  TbI2cArb
--
--  Maintainer:        Mehmet Burak Aykenar    email: burak.aykenar@anadologic.com
--  Contributor(s):
--     <intern name>
--
--  Description:
--      Test harness for multi-master arbitration (#16): two
--      I2cController instances and one I2cPeripheral.
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

entity TbI2cArb is
end entity TbI2cArb;

architecture TestHarness of TbI2cArb is

    -- Test Bench Constants
    constant tperiod_Clk : time := 10 ns;
    constant tpd         : time := 2 ns;

    -- Global Signals
    signal Clk     : std_logic;
    signal n_Reset : std_logic;

    -- Testbench Control Records
    signal I2cController1Rec : I2cRecType;
    signal I2cController2Rec : I2cRecType;
    signal I2cPeripheralRec  : I2cRecType;

    -- I2C Bus - shared by both controllers and the peripheral
    signal SCL : std_logic;
    signal SDA : std_logic;

    component TestCtrlArb
        port(
            I2cController1Rec : inout I2cRecType;
            I2cController2Rec : inout I2cRecType;
            I2cPeripheralRec  : inout I2cRecType;
            Clk               : in    std_logic;
            n_Reset           : in    std_logic
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
    -- I2C Verification Components - two controllers, one target,
    -- all three sharing the same SCL/SDA nets (#16).
    ------------------------------------------------------------
    I2cController_1 : I2cController
        port map(
            TransRec => I2cController1Rec,
            SCL      => SCL,
            SDA      => SDA
        );

    I2cController_2 : I2cController
        port map(
            TransRec => I2cController2Rec,
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
    TestCtrl_1 : TestCtrlArb
        port map(
            I2cController1Rec => I2cController1Rec,
            I2cController2Rec => I2cController2Rec,
            I2cPeripheralRec  => I2cPeripheralRec,
            Clk               => Clk,
            n_Reset           => n_Reset
        );

end architecture TestHarness;
