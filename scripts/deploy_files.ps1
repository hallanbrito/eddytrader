$termData = "C:\Users\dmnde\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"

Copy-Item "C:\Projetos\eddytrader\src\EddyTrader.mq5" -Destination "$termData\MQL5\Experts\EddyTrader.mq5" -Force
Copy-Item "C:\Projetos\eddytrader\src\EddyTrader.ex5" -Destination "$termData\MQL5\Experts\EddyTrader.ex5" -Force

Copy-Item "C:\Projetos\eddytrader\tests\test_fsm_w06.mq5" -Destination "$termData\MQL5\Experts\test_fsm_w06.mq5" -Force
Copy-Item "C:\Projetos\eddytrader\tests\test_fsm_w06.ex5" -Destination "$termData\MQL5\Experts\test_fsm_w06.ex5" -Force

Copy-Item "C:\Projetos\eddytrader\tests\test_fsm_w06.mq5" -Destination "$termData\MQL5\Scripts\test_fsm_w06.mq5" -Force
Copy-Item "C:\Projetos\eddytrader\tests\test_fsm_w06.ex5" -Destination "$termData\MQL5\Scripts\test_fsm_w06.ex5" -Force

Write-Host "Files deployed to Experts and Scripts successfully!"
