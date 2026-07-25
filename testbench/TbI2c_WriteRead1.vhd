--
--  File Name:         TbI2c_WriteRead1.vhd
--  Design Unit Name:  architecture WriteRead1 of TestCtrl
--
--  Maintainer:        Mehmet Burak Aykenar    email: burak.aykenar@anadologic.com
--  Contributor(s):
--     <intern name>
--
--  Description:
--      First test case: single-byte write then read to a 7-bit target
--      address. Self-checking via AffirmIfEqual on both the controller and
--      peripheral side.
--
--  Revision History:
--    Date      Version    Description
--    07/2026   0.2        Write and read, self-checking (#9)
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

architecture WriteRead1 of TestCtrl is

    signal TestDone : integer_barrier := 1;

begin

    ------------------------------------------------------------
    -- Test global control
    ------------------------------------------------------------
    ControlProc : process
    begin
        SetTestName("TbI2c_WriteRead1");
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

        Write(I2cControllerRec, "1010000", X"65");

        -- Read data differs from the byte just written, so this can't
        -- pass by accident (e.g. a FIFO handing back stale write data).
        Read(I2cControllerRec, "1010000", RData);
        AffirmIfEqual(RData, X"34", "Controller received read data");

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
        AffirmIfEqual(RxAddr, "1010000", "Peripheral received address for write");
        AffirmIfEqual(RxData, X"65", "Peripheral received data");

        SendRead(I2cPeripheralRec, RxAddr, X"34");
        AffirmIfEqual(RxAddr, "1010000", "Peripheral received address for read");

        WaitForBarrier(TestDone);
        wait;
    end process PeripheralProc;

end architecture WriteRead1;

configuration TbI2c_WriteRead1 of TbI2c is
    for TestHarness
        for TestCtrl_1 : TestCtrl
            use entity work.TestCtrl(WriteRead1);
        end for;
    end for;
end configuration TbI2c_WriteRead1;
