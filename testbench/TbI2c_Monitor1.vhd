--
--  File Name:         TbI2c_Monitor1.vhd
--  Design Unit Name:  architecture Monitor1 of TestCtrl
--
--  Maintainer:        Mehmet Burak Aykenar    email: burak.aykenar@anadologic.com
--  Contributor(s):
--     <intern name>
--
--  Description:
--      Bus monitor test.
--
--  Revision History:
--    Date      Version    Description
--    08/2026   0.1        Initial bus monitor test (#17)
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

architecture Monitor1 of TestCtrl is

    signal TestDone : integer_barrier := 1;

    constant DEV_ADDR : std_logic_vector(6 downto 0) := "1010000";
    constant WDATA    : std_logic_vector(7 downto 0) := X"65";

begin

    ------------------------------------------------------------
    -- Test global control
    ------------------------------------------------------------
    ControlProc : process
    begin
        SetTestName("TbI2c_Monitor1");
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
    -- Controller-side stimulus - also drives the monitor's expectations.
    ------------------------------------------------------------
    ControllerProc : process
        variable CountBefore : integer;
    begin
        wait until n_Reset = '1';
        WaitForClock(I2cControllerRec, 2);

        CountBefore := MonitorTransactionCount;

        Push(MonitorScoreboardID, DEV_ADDR & '0');
        Push(MonitorScoreboardID, WDATA);

        Write(I2cControllerRec, DEV_ADDR, WDATA);

        wait for 1 ns;

        AffirmIfEqual(MonitorTransactionCount, CountBefore + 1,
            "Monitor should have observed exactly one transaction");
        AffirmIfEqual(GetAlertCount(MonitorModelID), 0,
            "Monitor's scoreboard's mismatch count");

        WaitForBarrier(TestDone);
        wait;
    end process ControllerProc;

    ------------------------------------------------------------
    -- Peripheral-side stimulus / checking
    ------------------------------------------------------------
    PeripheralProc : process
        variable RxAddr : std_logic_vector(6 downto 0);
        variable RxData : std_logic_vector(7 downto 0);
    begin
        wait until n_Reset = '1';

        GetWrite(I2cPeripheralRec, RxAddr, RxData);
        AffirmIfEqual(RxAddr, DEV_ADDR, "Peripheral received write address");
        AffirmIfEqual(RxData, WDATA, "Peripheral received data");

        WaitForBarrier(TestDone);
        wait;
    end process PeripheralProc;

end architecture Monitor1;

configuration TbI2c_Monitor1 of TbI2c is
    for TestHarness
        for TestCtrl_1 : TestCtrl
            use entity work.TestCtrl(Monitor1);
        end for;
    end for;
end configuration TbI2c_Monitor1;
