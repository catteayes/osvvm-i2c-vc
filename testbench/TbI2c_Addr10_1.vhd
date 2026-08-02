--
--  File Name:         TbI2c_Addr10_1.vhd
--  Design Unit Name:  architecture Addr10_1 of TestCtrl
--
--  Maintainer:        Mehmet Burak Aykenar    email: burak.aykenar@anadologic.com
--  Contributor(s):
--     <intern name>
--
--  Description:
--      10-bit addressing test.
--
--  Revision History:
--    Date      Version    Description
--    08/2026   0.1        Initial 10-bit addressing test (#15)
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

architecture Addr10_1 of TestCtrl is

    signal TestDone : integer_barrier := 1;

    constant DEV_ADDR : std_logic_vector(9 downto 0) := "1111000001";
    constant WDATA    : std_logic_vector(7 downto 0) := X"65";
    constant RDATA    : std_logic_vector(7 downto 0) := X"34";

begin

    ------------------------------------------------------------
    -- Test global control
    ------------------------------------------------------------
    ControlProc : process
    begin
        SetTestName("TbI2c_Addr10_1");
        SetLogEnable(PASSED, TRUE);
        SetLogEnable(DEBUG, TRUE);

        wait for 0 ns;  wait for 0 ns;
        TranscriptOpen;
        SetTranscriptMirror(TRUE);

        wait until n_Reset = '1';
        ClearAlerts;

        WaitForBarrier(TestDone, 10 ms);
        AlertIf(now >= 10 ms, "Test finished due to timeout");

        TranscriptClose;
        EndOfTestReports;
        std.env.stop;
        wait;
    end process ControlProc;

    ------------------------------------------------------------
    -- Controller-side stimulus
    ------------------------------------------------------------
    ControllerProc : process
        variable RData : std_logic_vector(7 downto 0);
    begin
        wait until n_Reset = '1';
        WaitForClock(I2cControllerRec, 2);

        Write(I2cControllerRec, DEV_ADDR, WDATA);

        Read(I2cControllerRec, DEV_ADDR, RData);
        AffirmIfEqual(RData, RDATA, "Controller received read data");

        WaitForBarrier(TestDone);
        wait;
    end process ControllerProc;

    ------------------------------------------------------------
    -- Peripheral-side stimulus / checking
    ------------------------------------------------------------
    PeripheralProc : process
        variable RxAddr : std_logic_vector(9 downto 0);
        variable RxData : std_logic_vector(7 downto 0);
    begin
        wait until n_Reset = '1';

        GetWrite(I2cPeripheralRec, RxAddr, RxData);
        AffirmIfEqual(RxAddr, DEV_ADDR, "Peripheral received write address");
        AffirmIfEqual(RxData, WDATA, "Peripheral received data");

        SendRead(I2cPeripheralRec, RxAddr, RDATA);
        AffirmIfEqual(RxAddr, DEV_ADDR, "Peripheral received read address");

        WaitForBarrier(TestDone);
        wait;
    end process PeripheralProc;

end architecture Addr10_1;

configuration TbI2c_Addr10_1 of TbI2c is
    for TestHarness
        for TestCtrl_1 : TestCtrl
            use entity work.TestCtrl(Addr10_1);
        end for;
        for I2cPeripheral_1 : I2cPeripheral
            use entity osvvm_i2c.I2cPeripheral
                generic map (
                    TARGET_ADDRESS => "1111000001",
                    TEN_BIT_ADDR   => true
                );
        end for;
    end for;
end configuration TbI2c_Addr10_1;
