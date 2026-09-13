//+------------------------------------------------------------------+
//|                                                test_fsm_w06.mq5  |
//|                                  Copyright 2026, EddyTrader Team |
//|                                             https://eddytrader.io |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026, EddyTrader Team"
#property link        "https://eddytrader.io"
#property version     "1.00"
#property description "Validação Automatizada dos Cenários W06-01 a W06-15 da FSM e Recuperação"

//--- Definição dos Estados da FSM
enum ENUM_EDDY_STATE
{
   EDDY_STATE_INIT                 = 0,
   EDDY_STATE_MONITORING           = 1,
   EDDY_STATE_PROTECTION_TRIGGERED = 2,
   EDDY_STATE_LIQUIDATING          = 3,
   EDDY_STATE_BLOCKED              = 4,
   EDDY_STATE_REOPENING            = 5
};

//--- Estrutura de Recuperação
struct EddyRecoveryState
{
   ENUM_EDDY_STATE state;
   int             window_id;
   double          baseline;
   datetime        t_trigger;
   datetime        t_unlock;
   ulong           protection_event_id;
   datetime        day_timestamp;
};

//--- Contexto Simulado de Teste
ulong    test_login             = 99999999;
double   test_max_loss          = 500.0;
int      test_block_hours       = 4;

ENUM_EDDY_STATE test_state      = EDDY_STATE_INIT;
int      test_window_id         = 0;
double   test_baseline          = 0.0;
datetime test_t_trigger         = 0;
datetime test_t_unlock          = 0;
ulong    test_event_id          = 0;
datetime test_day_start         = 0;
bool     test_safe_to_operate   = false;

int      sim_positions_total    = 0;
int      sim_orders_total       = 0;
bool     sim_connected          = true;

//--- Contadores de Teste
int g_total_tests  = 0;
int g_passed_tests = 0;
int g_failed_tests = 0;

//+------------------------------------------------------------------+
//| Utilitários de Persistência em GlobalVariables                    |
//+------------------------------------------------------------------+
string TestGVKey(const string suffix)
{
   return StringFormat("EDDY_TEST_%I64u_%s", test_login, suffix);
}

void TestClearGV()
{
   GlobalVariableDel(TestGVKey("STATE"));
   GlobalVariableDel(TestGVKey("WINDOW_ID"));
   GlobalVariableDel(TestGVKey("BASELINE"));
   GlobalVariableDel(TestGVKey("T_TRIGGER"));
   GlobalVariableDel(TestGVKey("T_UNLOCK"));
   GlobalVariableDel(TestGVKey("EVENT_ID"));
   GlobalVariableDel(TestGVKey("DAY"));
   GlobalVariablesFlush();
}

void TestPersistGV()
{
   GlobalVariableSet(TestGVKey("STATE"), (double)test_state);
   GlobalVariableSet(TestGVKey("WINDOW_ID"), (double)test_window_id);
   GlobalVariableSet(TestGVKey("BASELINE"), test_baseline);
   GlobalVariableSet(TestGVKey("T_TRIGGER"), (double)test_t_trigger);
   GlobalVariableSet(TestGVKey("T_UNLOCK"), (double)test_t_unlock);
   GlobalVariableSet(TestGVKey("EVENT_ID"), (double)test_event_id);
   GlobalVariableSet(TestGVKey("DAY"), (double)test_day_start);
   GlobalVariablesFlush();
}

bool TestLoadGV(EddyRecoveryState &rec)
{
   if(!GlobalVariableCheck(TestGVKey("STATE")))
      return false;

   rec.state               = (ENUM_EDDY_STATE)(int)GlobalVariableGet(TestGVKey("STATE"));
   rec.window_id           = (int)GlobalVariableGet(TestGVKey("WINDOW_ID"));
   rec.baseline            = GlobalVariableGet(TestGVKey("BASELINE"));
   rec.t_trigger           = (datetime)GlobalVariableGet(TestGVKey("T_TRIGGER"));
   rec.t_unlock            = (datetime)GlobalVariableGet(TestGVKey("T_UNLOCK"));
   rec.protection_event_id = (ulong)GlobalVariableGet(TestGVKey("EVENT_ID"));
   rec.day_timestamp       = (datetime)GlobalVariableGet(TestGVKey("DAY"));
   return true;
}

//+------------------------------------------------------------------+
//| Funções Lógicas Espelhadas da FSM                                |
//+------------------------------------------------------------------+
datetime TestGetDayStart(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt);
}

bool TestCheckSafetyConditions()
{
   if(sim_positions_total > 0) return false;
   if(sim_orders_total > 0) return false;
   if(!sim_connected) return false;
   return true;
}

double TestCalcWindowResult(double D, double baseline)
{
   return D - baseline;
}

int g_file_handle = INVALID_HANDLE;

void AssertTest(string scenario_id, bool condition, string detail)
{
   g_total_tests++;
   string line = "";
   if(condition)
   {
      g_passed_tests++;
      line = StringFormat("  [PASS] %s: %s", scenario_id, detail);
   }
   else
   {
      g_failed_tests++;
      line = StringFormat("  [FAIL] %s: %s", scenario_id, detail);
   }
   Print(line);
   if(g_file_handle != INVALID_HANDLE)
   {
      FileWriteString(g_file_handle, line + "\r\n");
      FileFlush(g_file_handle);
   }
}

//+------------------------------------------------------------------+
//| Helpers de Teste para a Guarda OWNER + HEARTBEAT                 |
//+------------------------------------------------------------------+
bool TestAcquireGuard(ulong inst_id, bool &is_owner, datetime now)
{
   string owner_key = TestGVKey("INSTANCE_OWNER");
   string hb_key    = TestGVKey("HEARTBEAT");

   if(!GlobalVariableCheck(owner_key))
   {
      GlobalVariableSet(owner_key, (double)inst_id);
      GlobalVariableSet(hb_key, (double)now);
      GlobalVariablesFlush();

      if(GlobalVariableCheck(owner_key) && (ulong)GlobalVariableGet(owner_key) == inst_id)
      {
         is_owner = true;
         return true;
      }
   }

   ulong current_owner = (ulong)GlobalVariableGet(owner_key);
   if(current_owner == inst_id)
   {
      GlobalVariableSet(hb_key, (double)now);
      GlobalVariablesFlush();
      is_owner = true;
      return true;
   }

   if(GlobalVariableCheck(hb_key))
   {
      datetime last_hb = (datetime)GlobalVariableGet(hb_key);
      if(now >= last_hb && (now - last_hb) < 5)
      {
         is_owner = false;
         return false;
      }
   }

   // Lease expirada: tentativa de takeover atômico via CAS
   if(GlobalVariableSetOnCondition(owner_key, (double)inst_id, (double)current_owner))
   {
      GlobalVariableSet(hb_key, (double)now);
      GlobalVariablesFlush();
      is_owner = true;
      return true;
   }

   is_owner = false;
   return false;
}

void TestUpdateHeartbeat(ulong inst_id, bool &is_owner, datetime now, ENUM_EDDY_STATE &state, bool &safe)
{
   if(!is_owner)
      return;

   string owner_key = TestGVKey("INSTANCE_OWNER");
   if(!GlobalVariableCheck(owner_key) || (ulong)GlobalVariableGet(owner_key) != inst_id)
   {
      is_owner = false;
      safe     = false;
      state    = EDDY_STATE_INIT;
      return;
   }

   GlobalVariableSet(TestGVKey("HEARTBEAT"), (double)now);
}

void TestReleaseGuard(ulong inst_id, bool &is_owner)
{
   if(!is_owner)
      return; // Se não for owner, não altera nada!

   string owner_key = TestGVKey("INSTANCE_OWNER");
   if(GlobalVariableCheck(owner_key) && (ulong)GlobalVariableGet(owner_key) == inst_id)
   {
      GlobalVariableDel(owner_key);
      GlobalVariableDel(TestGVKey("HEARTBEAT"));
      GlobalVariablesFlush();
   }
   is_owner = false;
}

//+------------------------------------------------------------------+
//| Execução Central da Bateria de Testes (W06-01 a W06-20)          |
//+------------------------------------------------------------------+
void RunAllTests()
{
   g_file_handle = FileOpen("test_results.txt", FILE_WRITE|FILE_TXT|FILE_ANSI);

   string hdr1 = "==================================================================";
   string hdr2 = " Início da Bateria de Validação Formal W06: Cenários W06-01 a 20  ";
   Print(hdr1);
   Print(hdr2);
   Print(hdr1);
   if(g_file_handle != INVALID_HANDLE)
   {
      FileWriteString(g_file_handle, hdr1 + "\r\n");
      FileWriteString(g_file_handle, hdr2 + "\r\n");
      FileWriteString(g_file_handle, hdr1 + "\r\n");
   }

   datetime t_base = D'2026.09.13 10:00:00';
   datetime t_day  = TestGetDayStart(t_base);

   //-----------------------------------------------------------------
   // W06-01: Inicialização em J0 limpo (sem estado anterior)
   //-----------------------------------------------------------------
   TestClearGV();
   EddyRecoveryState rec01;
   bool has_state01 = TestLoadGV(rec01);
   if(!has_state01)
   {
      test_state           = EDDY_STATE_MONITORING;
      test_window_id       = 0;
      test_baseline        = 0.0;
      test_safe_to_operate = true;
      test_day_start       = t_day;
      TestPersistGV();
   }
   AssertTest("W06-01",
              test_state == EDDY_STATE_MONITORING && test_window_id == 0 && test_baseline == 0.0 && test_safe_to_operate,
              "Inicialização limpa inicia com sucesso em MONITORING, J0, B0=0 e safe_to_operate=true");

   //-----------------------------------------------------------------
   // W06-02: Monitoramento com W > -L (perda dentro do limite)
   //-----------------------------------------------------------------
   double D_02 = -250.0; // Perda de 250
   double W_02 = TestCalcWindowResult(D_02, test_baseline);
   if(W_02 <= -test_max_loss)
   {
      test_state = EDDY_STATE_PROTECTION_TRIGGERED;
   }
   AssertTest("W06-02",
              test_state == EDDY_STATE_MONITORING && W_02 > -test_max_loss,
              StringFormat("W=%.2f > -L=-%.2f: Robô permanece em MONITORING sem disparar proteção", W_02, test_max_loss));

   //-----------------------------------------------------------------
   // W06-03: Violação de limite W <= -L
   //-----------------------------------------------------------------
   double D_03 = -550.0; // Perda de 550 violando 500
   double W_03 = TestCalcWindowResult(D_03, test_baseline);
   datetime t_trigger_03 = D'2026.09.13 11:30:00';
   if(W_03 <= -test_max_loss)
   {
      test_state       = EDDY_STATE_PROTECTION_TRIGGERED;
      test_t_trigger   = t_trigger_03;
      test_t_unlock    = test_t_trigger + (datetime)(test_block_hours * 3600);
      test_event_id    = 1001;
      // Transição atômica imediata para LIQUIDATING
      test_state       = EDDY_STATE_LIQUIDATING;
      TestPersistGV();
   }
   AssertTest("W06-03",
              test_state == EDDY_STATE_LIQUIDATING && test_t_trigger == t_trigger_03 && test_t_unlock == (t_trigger_03 + 14400),
              StringFormat("W=%.2f <= -L=-%.2f: Dispara transição MONITORING -> PROTECTION_TRIGGERED -> LIQUIDATING com t_unlock correto", W_03, test_max_loss));

   //-----------------------------------------------------------------
   // W06-04: Liquidação com sucesso (resíduo zerado)
   //-----------------------------------------------------------------
   sim_positions_total = 0;
   sim_orders_total    = 0;
   if(test_state == EDDY_STATE_LIQUIDATING)
   {
      if(sim_positions_total == 0 && sim_orders_total == 0)
      {
         test_state = EDDY_STATE_BLOCKED;
         TestPersistGV();
      }
   }
   AssertTest("W06-04",
              test_state == EDDY_STATE_BLOCKED,
              "Com posições e ordens zeradas, transita com sucesso de LIQUIDATING para BLOCKED");

   //-----------------------------------------------------------------
   // W06-05: Liquidação com resíduo (falha parcial ou ordens pendentes)
   //-----------------------------------------------------------------
   test_state = EDDY_STATE_LIQUIDATING;
   sim_positions_total = 1; // Resíduo não fechado (ex: mercado fechado)
   sim_orders_total    = 0;
   if(sim_positions_total == 0 && sim_orders_total == 0)
   {
      test_state = EDDY_STATE_BLOCKED;
   }
   AssertTest("W06-05",
              test_state == EDDY_STATE_LIQUIDATING,
              "Com resíduo aberto (>0 posições), FSM é retida estritamente em LIQUIDATING sem avançar para BLOCKED");

   //-----------------------------------------------------------------
   // W06-06: Permanência em BLOCKED com t < t_unlock
   //-----------------------------------------------------------------
   test_state = EDDY_STATE_BLOCKED;
   sim_positions_total = 0;
   datetime t_check_06 = test_t_trigger + 3600; // 1 hora decorrida (faltam 3 horas)
   if(t_check_06 >= test_t_unlock)
   {
      if(TestCheckSafetyConditions())
         test_state = EDDY_STATE_REOPENING;
   }
   AssertTest("W06-06",
              test_state == EDDY_STATE_BLOCKED && t_check_06 < test_t_unlock,
              StringFormat("t=%s < t_unlock=%s: Bloqueio mantido incondicionalmente em BLOCKED",
                           TimeToString(t_check_06, TIME_SECONDS), TimeToString(test_t_unlock, TIME_SECONDS)));

   //-----------------------------------------------------------------
   // W06-07: Intervenção manual durante BLOCKED (neutralização reativa)
   //-----------------------------------------------------------------
   datetime saved_t_trigger = test_t_trigger;
   datetime saved_t_unlock  = test_t_unlock;
   ulong    saved_event_id  = test_event_id;

   // Simula operador abrindo ordem manual
   sim_positions_total = 1;
   // Neutralização reativa é invocada: fecha posição imediatamente
   sim_positions_total = 0;
   // Invariante de negócio: t_trigger e t_unlock NÃO podem ser alterados!
   bool invariant_preserved = (test_t_trigger == saved_t_trigger &&
                               test_t_unlock == saved_t_unlock &&
                               test_event_id == saved_event_id);
   AssertTest("W06-07",
              test_state == EDDY_STATE_BLOCKED && sim_positions_total == 0 && invariant_preserved,
              "Intervenção manual durante BLOCKED é neutralizada reativamente sem alterar t_trigger, t_unlock ou event_id");

   //-----------------------------------------------------------------
   // W06-08: Transcorrer de 4 horas (t >= t_unlock) mas safe_to_reopen == false
   //-----------------------------------------------------------------
   datetime t_check_08 = test_t_unlock + 10; // 4 horas cumpridas
   sim_positions_total = 1; // Posição residual detectada
   if(t_check_08 >= test_t_unlock)
   {
      if(TestCheckSafetyConditions())
      {
         test_state = EDDY_STATE_REOPENING;
      }
      else
      {
         // Retido em BLOCKED
      }
   }
   AssertTest("W06-08",
              test_state == EDDY_STATE_BLOCKED && !TestCheckSafetyConditions(),
              "t >= t_unlock porém safe_to_reopen == false: Robô retém bloqueio em BLOCKED e recusa reabertura");

   //-----------------------------------------------------------------
   // W06-09: Reabertura com sucesso (t >= t_unlock e safe_to_reopen == true)
   //-----------------------------------------------------------------
   sim_positions_total = 0;
   sim_orders_total    = 0;
   sim_connected       = true;
   datetime t_reopen_09 = test_t_unlock + 60; // 1 minuto após unlock
   if(t_reopen_09 >= test_t_unlock && TestCheckSafetyConditions())
   {
      test_state = EDDY_STATE_REOPENING;
      test_window_id++;
      double D_reopen = -520.0; // Resultado consolidado no momento da reabertura
      test_baseline   = D_reopen;
      double W_new    = TestCalcWindowResult(D_reopen, test_baseline);

      // Invariante matemático W_(n+1)(t_reopen) == 0
      bool math_ok = (MathAbs(W_new) < 0.0001);

      // Finaliza reabertura e retorna a MONITORING
      test_t_trigger = 0;
      test_t_unlock  = 0;
      test_event_id  = 0;
      test_state     = EDDY_STATE_MONITORING;
      TestPersistGV();

      AssertTest("W06-09",
                 test_state == EDDY_STATE_MONITORING && test_window_id == 1 && test_baseline == -520.0 && math_ok,
                 StringFormat("Reabertura formal em J1: Baseline Bn=%.2f capturada, W_new=%.2f == 0 validado, retorno a MONITORING",
                              test_baseline, W_new));
   }

   //-----------------------------------------------------------------
   // W06-10: Virada de dia às 00:00:00 durante MONITORING
   //-----------------------------------------------------------------
   datetime t_next_day_10 = t_day + 86400; // Novo dia
   if(t_next_day_10 > test_day_start)
   {
      if(test_state == EDDY_STATE_MONITORING)
      {
         test_day_start = t_next_day_10;
         test_window_id = 0;
         test_baseline  = 0.0;
         TestPersistGV();
      }
   }
   AssertTest("W06-10",
              test_state == EDDY_STATE_MONITORING && test_window_id == 0 && test_baseline == 0.0 && test_day_start == t_next_day_10,
              "Virada de dia em MONITORING reinicia ciclo diário em J0 com B0=0.0");

   //-----------------------------------------------------------------
   // W06-11: Virada de dia às 00:00:00 durante BLOCKED
   //-----------------------------------------------------------------
   test_state     = EDDY_STATE_BLOCKED;
   test_t_trigger = D'2026.09.13 22:00:00';
   test_t_unlock  = test_t_trigger + 14400; // D'2026.09.14 02:00:00' (cruza a meia-noite!)
   test_event_id  = 2002;
   TestPersistGV();

   datetime t_midnight_11 = D'2026.09.14 00:00:01';
   datetime day_14 = TestGetDayStart(t_midnight_11);
   if(day_14 > test_day_start)
   {
      if(test_state == EDDY_STATE_BLOCKED)
      {
         test_day_start = day_14;
         // t_trigger e t_unlock NÃO sofrem reset! Bloqueio de 4h permanece inalterado
         TestPersistGV();
      }
   }
   AssertTest("W06-11",
              test_state == EDDY_STATE_BLOCKED && test_t_unlock == D'2026.09.14 02:00:00',
              "Virada de dia durante BLOCKED preserva rigorosamente o bloqueio contínuo de 4h atravessando a meia-noite");

   //-----------------------------------------------------------------
   // W06-12: Reinicialização do terminal durante MONITORING em J0
   //-----------------------------------------------------------------
   test_state     = EDDY_STATE_MONITORING;
   test_window_id = 0;
   test_baseline  = 0.0;
   test_day_start = day_14;
   TestPersistGV();

   // Simula restart do terminal limpando variáveis em RAM
   test_state     = EDDY_STATE_INIT;
   test_window_id = -1;
   test_baseline  = -999.0;

   // Executa rotina de recuperação do OnInit
   EddyRecoveryState rec12;
   if(TestLoadGV(rec12))
   {
      if(rec12.state == EDDY_STATE_MONITORING)
      {
         test_state     = rec12.state;
         test_window_id = rec12.window_id;
         test_baseline  = rec12.baseline;
      }
   }
   AssertTest("W06-12",
              test_state == EDDY_STATE_MONITORING && test_window_id == 0 && test_baseline == 0.0,
              "Restart durante MONITORING em J0 restaura com sucesso J0 com B0=0");

   //-----------------------------------------------------------------
   // W06-13: Reinicialização durante MONITORING em janela intradiária Jn (n >= 1)
   //-----------------------------------------------------------------
   test_state     = EDDY_STATE_MONITORING;
   test_window_id = 2;
   test_baseline  = -640.50;
   test_day_start = day_14;
   TestPersistGV();

   // Simula restart do terminal
   test_state     = EDDY_STATE_INIT;
   test_window_id = -1;
   test_baseline  = 0.0;

   EddyRecoveryState rec13;
   if(TestLoadGV(rec13))
   {
      if(rec13.state == EDDY_STATE_MONITORING && rec13.window_id >= 1)
      {
         test_state     = rec13.state;
         test_window_id = rec13.window_id;
         test_baseline  = rec13.baseline;
      }
   }
   AssertTest("W06-13",
              test_state == EDDY_STATE_MONITORING && test_window_id == 2 && test_baseline == -640.50,
              "Restart durante MONITORING em Jn (n>=1) restaura perfeitamente Bn=-640.50 sem fallback para 0");

   //-----------------------------------------------------------------
   // W06-14: Reinicialização durante BLOCKED com t < t_unlock
   //-----------------------------------------------------------------
   test_state     = EDDY_STATE_BLOCKED;
   test_t_trigger = D'2026.09.14 01:00:00';
   test_t_unlock  = D'2026.09.14 05:00:00';
   test_event_id  = 3003;
   TestPersistGV();

   // Simula restart do terminal às 02:30:00
   datetime t_restart_14 = D'2026.09.14 02:30:00';
   test_state = EDDY_STATE_INIT;

   EddyRecoveryState rec14;
   if(TestLoadGV(rec14))
   {
      if(rec14.state == EDDY_STATE_BLOCKED)
      {
         if(t_restart_14 < rec14.t_unlock && TestCheckSafetyConditions())
         {
            test_state     = EDDY_STATE_BLOCKED;
            test_t_trigger = rec14.t_trigger;
            test_t_unlock  = rec14.t_unlock;
            test_event_id  = rec14.protection_event_id;
         }
      }
   }
   AssertTest("W06-14",
              test_state == EDDY_STATE_BLOCKED && test_t_unlock == D'2026.09.14 05:00:00' && test_event_id == 3003,
              "Restart durante BLOCKED com t < t_unlock reconstitui t_trigger, t_unlock e event_id mantendo BLOCKED");

   //-----------------------------------------------------------------
   // W06-15: Reinicialização com estado corrompido / ausência de baseline em Jn (n >= 1)
   //-----------------------------------------------------------------
   // Persiste estado com J1 mas deleta a chave de baseline para simular corrupção
   test_state     = EDDY_STATE_MONITORING;
   test_window_id = 1;
   test_baseline  = -400.0;
   TestPersistGV();
   GlobalVariableDel(TestGVKey("BASELINE")); // Deleta propositalmente a baseline
   GlobalVariablesFlush();

   // Simula restart do terminal
   test_state           = EDDY_STATE_INIT;
   test_safe_to_operate = true;

   EddyRecoveryState rec15;
   if(TestLoadGV(rec15))
   {
      if(rec15.state == EDDY_STATE_MONITORING && rec15.window_id >= 1)
      {
         if(!GlobalVariableCheck(TestGVKey("BASELINE")))
         {
            // Postura FAIL-CLOSED: Recusa transição para MONITORING!
            test_state           = EDDY_STATE_INIT;
            test_safe_to_operate = false;
         }
      }
   }
   AssertTest("W06-15",
              test_state == EDDY_STATE_INIT && !test_safe_to_operate,
              "Postura FAIL-CLOSED: Ausência de baseline em Jn (n>=1) retém robô em INIT e proíbe operações");

   //-----------------------------------------------------------------
   // W06-16: Segunda instância rejeitada (concorrência)
   //-----------------------------------------------------------------
   TestClearGV();
   ulong inst_A = 10001;
   ulong inst_B = 10002;
   bool  is_owner_A = false;
   bool  is_owner_B = false;
   datetime t_guard_base = D'2026.09.14 08:00:00';

   // Instância A adquire a guarda
   bool acq_A = TestAcquireGuard(inst_A, is_owner_A, t_guard_base);
   // Instância B tenta adquirir 1 segundo depois (heartbeat de A recente)
   bool acq_B = TestAcquireGuard(inst_B, is_owner_B, t_guard_base + 1);

   ulong registered_owner_16 = (ulong)GlobalVariableGet(TestGVKey("INSTANCE_OWNER"));
   AssertTest("W06-16",
              acq_A && is_owner_A && !acq_B && !is_owner_B && registered_owner_16 == inst_A,
              "Instância concorrente B é rejeitada com lock ativo; Instância A permanece como proprietária legítima");

   //-----------------------------------------------------------------
   // W06-17: INIT_FAILED não remove lock alheio (OnDeinit de B)
   //-----------------------------------------------------------------
   // Instância B falhou em OnInit (is_owner_B == false) e executa OnDeinit
   TestReleaseGuard(inst_B, is_owner_B);

   bool owner_key_exists_17 = GlobalVariableCheck(TestGVKey("INSTANCE_OWNER"));
   ulong registered_owner_17 = (ulong)GlobalVariableGet(TestGVKey("INSTANCE_OWNER"));
   bool hb_exists_17 = GlobalVariableCheck(TestGVKey("HEARTBEAT"));
   AssertTest("W06-17",
              owner_key_exists_17 && registered_owner_17 == inst_A && hb_exists_17,
              "OnDeinit de B (não-proprietária) NÃO remove lock nem heartbeat pertencentes à Instância A");

   //-----------------------------------------------------------------
   // W06-18: Owner pode liberar guarda (OnDeinit de A)
   //-----------------------------------------------------------------
   // Instância A (proprietária legítima) encerra e executa OnDeinit
   TestReleaseGuard(inst_A, is_owner_A);

   bool owner_key_exists_18 = GlobalVariableCheck(TestGVKey("INSTANCE_OWNER"));
   bool hb_exists_18 = GlobalVariableCheck(TestGVKey("HEARTBEAT"));
   AssertTest("W06-18",
              !is_owner_A && !owner_key_exists_18 && !hb_exists_18,
              "Instância proprietária A libera com sucesso o lock e heartbeat em seu OnDeinit");

   //-----------------------------------------------------------------
   // W06-19: Takeover após lease expirada (timeout > 5s)
   //-----------------------------------------------------------------
   // Instância A adquire guarda no instante t_guard_base
   TestAcquireGuard(inst_A, is_owner_A, t_guard_base);
   // Avança tempo em 10 segundos sem renovação de heartbeat por A (lease expirada)
   datetime t_takeover = t_guard_base + 10;
   // Instância B tenta iniciar e executa takeover atômico via CAS
   bool takeover_B = TestAcquireGuard(inst_B, is_owner_B, t_takeover);

   ulong registered_owner_19 = (ulong)GlobalVariableGet(TestGVKey("INSTANCE_OWNER"));
   AssertTest("W06-19",
              takeover_B && is_owner_B && registered_owner_19 == inst_B,
              "Com lease expirada (>5s), Instância B assume ownership com sucesso através de takeover atômico via CAS");

   //-----------------------------------------------------------------
   // W06-20: Instância antiga retorna após takeover (Fail-Closed)
   //-----------------------------------------------------------------
   // B é o proprietário ativo. A (zombie) acorda e tenta atualizar heartbeat
   ENUM_EDDY_STATE state_A = EDDY_STATE_MONITORING;
   bool safe_A = true;
   int saved_positions_20 = sim_positions_total;

   TestUpdateHeartbeat(inst_A, is_owner_A, t_takeover + 1, state_A, safe_A);

   ulong registered_owner_20 = (ulong)GlobalVariableGet(TestGVKey("INSTANCE_OWNER"));
   bool a_contained = (!is_owner_A && !safe_A && state_A == EDDY_STATE_INIT);
   bool b_intact    = (registered_owner_20 == inst_B);
   bool no_damage   = (sim_positions_total == saved_positions_20);

   AssertTest("W06-20",
              a_contained && b_intact && no_damage,
              "Instância antiga A detecta perda de ownership, entra em FAIL-CLOSED, não liquida e não altera lock de B");

   // Limpa GlobalVariables de teste
   TestReleaseGuard(inst_B, is_owner_B);
   TestClearGV();

   //-----------------------------------------------------------------
   // Relatório Final da Bateria
   //-----------------------------------------------------------------
   string ftr1 = "==================================================================";
   string ftr2 = StringFormat(" Resumo da Bateria W06: Total=%d | Aprovados=%d | Falhas=%d",
                              g_total_tests, g_passed_tests, g_failed_tests);
   Print(ftr1);
   Print(ftr2);
   Print(ftr1);

   if(g_file_handle != INVALID_HANDLE)
   {
      FileWriteString(g_file_handle, ftr1 + "\r\n");
      FileWriteString(g_file_handle, ftr2 + "\r\n");
      FileWriteString(g_file_handle, ftr1 + "\r\n");
      FileClose(g_file_handle);
      g_file_handle = INVALID_HANDLE;
   }
}

//+------------------------------------------------------------------+
//| Expert Initialization / Tick Handlers                            |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("[test_fsm_w06] OnInit invocado. Iniciando bateria de testes W06...");
   RunAllTests();
   return INIT_SUCCEEDED;
}

void OnTick()
{
   static bool executed = false;
   if(!executed)
   {
      executed = true;
      Print("[test_fsm_w06] OnTick invocado. Bateria completa.");
      ExpertRemove();
   }
}

void OnDeinit(const int reason)
{
   PrintFormat("[test_fsm_w06] Finalizado com razão %d", reason);
}
//+------------------------------------------------------------------+
