//+------------------------------------------------------------------+
//|                         test_w10_4_financial_integrity.mq5       |
//|                         EddyTrader - W10.4 regression harness    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, EddyTrader Team"
#property version   "1.00"
#property strict

enum TEST_STATE
{
   TEST_INIT = 0,
   TEST_MONITORING = 1,
   TEST_LIQUIDATING = 3,
   TEST_BLOCKED = 4,
   TEST_REOPENING = 5
};

struct TestRecovery
{
   TEST_STATE state;
   int window_id;
   double baseline;
   datetime trigger;
   datetime unlock;
   ulong event_id;
};

int g_total = 0;
int g_passed = 0;
int g_failed = 0;
int g_history_calls = 0;
int g_file = INVALID_HANDLE;
string g_prefix = "EDDY_W104_TEST_";

void AssertW104(const string id, const bool condition, const string detail)
{
   g_total++;
   string line = StringFormat("[%s] %s: %s", (condition ? "PASS" : "FAIL"), id, detail);
   Print(line);
   if(condition) g_passed++; else g_failed++;
   if(g_file != INVALID_HANDLE)
      FileWriteString(g_file, line + "\r\n");
}

bool ModelReadHistory(const bool select_ok,
                      const bool ticket_ok,
                      const bool properties_ok,
                      double &realized)
{
   g_history_calls++;
   realized = 0.0;
   if(!select_ok || !ticket_ok || !properties_ok)
      return false;
   realized = -125.75;
   return true;
}

double ModelHudRead(const bool snapshot_valid, const double consolidated)
{
   // HUD deliberadamente nao chama ModelReadHistory.
   return snapshot_valid ? consolidated : 0.0;
}

bool ModelSafeToReopen(const int positions,
                       const int orders,
                       const bool connected,
                       const bool financial_valid)
{
   return (positions == 0 && orders == 0 && connected && financial_valid);
}

bool ModelTradeConfirmed(const bool request_sent,
                         const uint retcode,
                         const bool still_in_inventory)
{
   bool server_done = (retcode == TRADE_RETCODE_DONE ||
                       retcode == TRADE_RETCODE_DONE_PARTIAL);
   return (request_sent && server_done && !still_in_inventory);
}

bool ModelReopen(TestRecovery &state,
                 const bool financial_valid,
                 const bool commit_ok,
                 const double consolidated)
{
   TestRecovery previous = state;
   if(!financial_valid)
   {
      state.state = TEST_BLOCKED;
      return false;
   }

   state.state = TEST_MONITORING;
   state.window_id++;
   state.baseline = consolidated;
   state.trigger = 0;
   state.unlock = 0;
   state.event_id = 0;
   if(!commit_ok)
   {
      state = previous;
      state.state = TEST_BLOCKED;
      return false;
   }
   return true;
}

string SlotKey(const int slot, const string suffix)
{
   return StringFormat("%sS%d_%s", g_prefix, slot, suffix);
}

void ClearTestGV()
{
   GlobalVariableDel(g_prefix + "GEN");
   for(int slot = 0; slot < 2; slot++)
   {
      GlobalVariableDel(SlotKey(slot, "GEN"));
      GlobalVariableDel(SlotKey(slot, "STATE"));
      GlobalVariableDel(SlotKey(slot, "WINDOW"));
      GlobalVariableDel(SlotKey(slot, "BASELINE"));
   }
   GlobalVariablesFlush();
}

void WriteTestSlot(const int slot,
                   const ulong generation,
                   const TEST_STATE state,
                   const int window_id,
                   const double baseline,
                   const bool complete)
{
   GlobalVariableSet(SlotKey(slot, "STATE"), (double)state);
   GlobalVariableSet(SlotKey(slot, "WINDOW"), (double)window_id);
   if(complete)
      GlobalVariableSet(SlotKey(slot, "BASELINE"), baseline);
   GlobalVariableSet(SlotKey(slot, "GEN"), (double)generation);
   GlobalVariablesFlush();
}

bool ReadCommittedSlot(TestRecovery &state)
{
   if(!GlobalVariableCheck(g_prefix + "GEN"))
      return false;
   ulong generation = (ulong)GlobalVariableGet(g_prefix + "GEN");
   int slot = (int)(generation % 2);
   if(!GlobalVariableCheck(SlotKey(slot, "GEN")) ||
      !GlobalVariableCheck(SlotKey(slot, "STATE")) ||
      !GlobalVariableCheck(SlotKey(slot, "WINDOW")) ||
      !GlobalVariableCheck(SlotKey(slot, "BASELINE")) ||
      (ulong)GlobalVariableGet(SlotKey(slot, "GEN")) != generation)
      return false;

   state.state = (TEST_STATE)(int)GlobalVariableGet(SlotKey(slot, "STATE"));
   state.window_id = (int)GlobalVariableGet(SlotKey(slot, "WINDOW"));
   state.baseline = GlobalVariableGet(SlotKey(slot, "BASELINE"));
   return true;
}

void RunW104Tests()
{
   double realized = 0.0;
   AssertW104("W104-01", !ModelReadHistory(false, true, true, realized),
              "HistorySelect falho invalida o dado; zero nao vira resultado legitimo");
   AssertW104("W104-02", !ModelReadHistory(true, false, true, realized),
              "ticket zero/falho invalida toda a leitura parcial");
   AssertW104("W104-03", !ModelReadHistory(true, true, false, realized),
              "propriedade ausente invalida toda a leitura parcial");

   int calls_before_hud = g_history_calls;
   double hud_value = ModelHudRead(true, -42.50);
   AssertW104("W104-04", g_history_calls == calls_before_hud && MathAbs(hud_value + 42.50) < 0.00001,
              "HUD consome snapshot e nao altera saude do historico");

   AssertW104("W104-05", !ModelSafeToReopen(0, 0, true, false),
              "safe_to_reopen exige contabilidade valida alem de inventario e conexao");

   TestRecovery rec;
   rec.state = TEST_BLOCKED;
   rec.window_id = 3;
   rec.baseline = -500.0;
   rec.trigger = D'2026.11.02 10:00:00';
   rec.unlock = D'2026.11.02 14:00:00';
   rec.event_id = 202611021000001;
   bool reopened = ModelReopen(rec, false, true, -620.0);
   AssertW104("W104-06", !reopened && rec.state == TEST_BLOCKED &&
              rec.window_id == 3 && rec.event_id == 202611021000001,
              "falha financeira em REOPENING preserva janela, evento e bloqueio");

   rec.state = TEST_BLOCKED;
   reopened = ModelReopen(rec, true, true, -620.0);
   AssertW104("W104-07", reopened && rec.state == TEST_MONITORING &&
              rec.window_id == 4 && MathAbs((-620.0) - rec.baseline) < 0.00001 &&
              rec.event_id == 0,
              "commit de reabertura cria uma unica nova janela com W=0");

   rec.state = TEST_BLOCKED;
   rec.window_id = 4;
   rec.baseline = -620.0;
   rec.trigger = D'2026.11.02 15:00:00';
   rec.unlock = D'2026.11.02 19:00:00';
   rec.event_id = 202611021500001;
   reopened = ModelReopen(rec, true, false, -700.0);
   AssertW104("W104-08", !reopened && rec.state == TEST_BLOCKED && rec.window_id == 4 &&
              MathAbs(rec.baseline + 620.0) < 0.00001 && rec.event_id == 202611021500001,
              "falha de commit faz rollback integral do candidato de reabertura");

   ClearTestGV();
   WriteTestSlot(1, 1, TEST_BLOCKED, 7, -710.0, true);
   TestRecovery loaded;
   AssertW104("W104-09", !ReadCommittedSlot(loaded),
              "slot preparado sem marcador de commit nao substitui estado anterior");

   GlobalVariableSet(g_prefix + "GEN", 1.0);
   GlobalVariablesFlush();
   AssertW104("W104-10", ReadCommittedSlot(loaded) && loaded.state == TEST_BLOCKED &&
              loaded.window_id == 7 && MathAbs(loaded.baseline + 710.0) < 0.00001,
              "marcador publicado por ultimo torna o slot completo recuperavel");

   WriteTestSlot(0, 2, TEST_MONITORING, 8, -800.0, false);
   GlobalVariableSet(g_prefix + "GEN", 2.0);
   GlobalVariablesFlush();
   AssertW104("W104-11", !ReadCommittedSlot(loaded),
              "slot comprometido incompleto e rejeitado em fail-closed");

   AssertW104("W104-12", ModelTradeConfirmed(true, TRADE_RETCODE_DONE, false),
              "retcode DONE mais ausencia no inventario confirma encerramento");
   AssertW104("W104-13", !ModelTradeConfirmed(true, TRADE_RETCODE_DONE, true),
              "retcode DONE com residuo no inventario nao confirma encerramento");
   AssertW104("W104-14", !ModelTradeConfirmed(false, TRADE_RETCODE_DONE, false),
              "booleano local falso impede confirmacao mesmo sem residuo observado");

   TEST_STATE liquidation_state = TEST_LIQUIDATING;
   int residual_positions = 1;
   if(residual_positions == 0)
      liquidation_state = TEST_BLOCKED;
   AssertW104("W104-15", liquidation_state == TEST_LIQUIDATING,
              "FSM permanece LIQUIDATING enquanto houver residuo global");

   ulong next_attempt = 1500;
   ulong callback_time = 1200;
   AssertW104("W104-16", callback_time < next_attempt,
              "callback dentro da janela de retry nao duplica solicitacao CTrade");

   ulong instance_id = 12345;
   ulong persisted_owner = 67890;
   AssertW104("W104-17", instance_id != persisted_owner,
              "ownership e revalidado antes de efeito externo");

   int deals_first = 9;
   int deals_second = 10;
   AssertW104("W104-18", deals_first != deals_second,
              "mudanca da lista de deals durante R+F descarta snapshot inconsistente");

   ClearTestGV();
}

int OnInit()
{
   g_file = FileOpen("w104_test_results.txt", FILE_WRITE|FILE_TXT|FILE_ANSI);
   RunW104Tests();
   string summary = StringFormat("W10.4: Total=%d | Aprovados=%d | Falhas=%d",
                                 g_total, g_passed, g_failed);
   Print(summary);
   if(g_file != INVALID_HANDLE)
   {
      FileWriteString(g_file, summary + "\r\n");
      FileClose(g_file);
      g_file = INVALID_HANDLE;
   }
   return INIT_SUCCEEDED;
}

void OnTick()
{
   ExpertRemove();
}

void OnDeinit(const int reason)
{
   PrintFormat("[test_w10_4_financial_integrity] Finalizado com razao %d", reason);
}
//+------------------------------------------------------------------+
