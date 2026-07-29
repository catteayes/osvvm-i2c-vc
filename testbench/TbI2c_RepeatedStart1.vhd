--
--  File Name:         TbI2c_RepeatedStart1.vhd
--  Design Unit Name:  architecture RepeatedStart1 of TestCtrl
--
--  Maintainer:        Mehmet Burak Aykenar    email: burak.aykenar@anadologic.com
--  Contributor(s):
--     <intern name>
--
--  Description:
--      Repeated START test: the standard "write a register pointer, then
--      read from it without releasing the bus" idiom. The Write is armed
--      with SetRepeatedStart so it ends with Sr instead of STOP; the Read
--      that follows is not rearmed, so it ends with a normal STOP.
--
--  Revision History:
--    Date      Version    Description
--    07/2026   0.1        Initial repeated START write-then-read test (#11)
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

architecture RepeatedStart1 of TestCtrl is

    signal TestDone : integer_barrier := 1;

    constant DEV_ADDR    : std_logic_vector(6 downto 0) := "1010000";
    constant REG_POINTER : std_logic_vector(7 downto 0) := X"12";
    constant REG_DATA    : std_logic_vector(7 downto 0) := X"7A";

begin

    ------------------------------------------------------------
    -- Test global control
    ------------------------------------------------------------
    ControlProc : process
    begin
        SetTestName("TbI2c_RepeatedStart1");
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

        SetRepeatedStart(I2cControllerRec, TRUE);
        Write(I2cControllerRec, DEV_ADDR, REG_POINTER);

        Read(I2cControllerRec, DEV_ADDR, RData);
        AffirmIfEqual(RData, REG_DATA, "Controller received read data");

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
        AffirmIfEqual(RxData, REG_POINTER, "Peripheral received register pointer");

        SendRead(I2cPeripheralRec, RxAddr, REG_DATA);
        AffirmIfEqual(RxAddr, DEV_ADDR, "Peripheral received read address");

        WaitForBarrier(TestDone);
        wait;
    end process PeripheralProc;

end architecture RepeatedStart1;

configuration TbI2c_RepeatedStart1 of TbI2c is
    for TestHarness
        for TestCtrl_1 : TestCtrl
            use entity work.TestCtrl(RepeatedStart1);
        end for;
    end for;
end configuration TbI2c_RepeatedStart1;
