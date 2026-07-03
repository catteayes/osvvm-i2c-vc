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
--      address. Skeleton only — stimulus to be implemented.
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
    begin
        wait until n_Reset = '1';
        WaitForClock(I2cControllerRec, 2);

        -- TODO(intern): Write(I2cControllerRec, Addr, Data) then
        -- Read/ReadCheck the same location back.

        WaitForBarrier(TestDone);
        wait;
    end process ControllerProc;

    ------------------------------------------------------------
    -- Peripheral-side stimulus / checking
    ------------------------------------------------------------
    PeripheralProc : process
    begin
        wait until n_Reset = '1';

        -- TODO(intern): receive the written byte and check it; provide
        -- the byte to be returned on the read.

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
