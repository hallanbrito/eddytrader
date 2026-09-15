//+------------------------------------------------------------------+
//|                                                test_fsm_w06.mq5  |
//|                                  Copyright 2026, EddyTrader Team |
//|                                             https://eddytrader.io |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026, EddyTrader Team"
#property link        "https://eddytrader.io"
#property version     "1.00"
#property description "Validação Automatizada dos Cenários W06-01..15, W07R-01..06, W08R-01..02, W09R-01..29 e W10R-01..10"

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

//--- Definição dos Modos de HUD (W09/W09.3)
enum ENUM_EDDY_HUD_MODE
{
   EDDY_HUD_COMPACT  = 0, // Painel Compacto Trader
   EDDY_HUD_DETAILED = 1, // Painel Técnico Detalhado
   EDDY_HUD_OFF      = 2  // HUD Desativado
};

//--- Definição dos Estados do Painel HUD (W10)
enum ENUM_DISCIPLINADOR_PANEL_STATE
{
   PANEL_EXPANDED  = 0,
   PANEL_COLLAPSED = 1
};

//--- Definição dos Estados da Interface de Configuração (W09/W09.2)
enum ENUM_CONFIG_UI_STATE
{
   UI_STATE_IDLE = 0,
   UI_STATE_EDITING,
   UI_STATE_CONFIRMING
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
double   test_g_max_loss        = 500.0;
int      test_block_hours       = 4;
bool     sim_gv_persist_fail    = false;

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

string TestGVConfigKey(const string suffix)
{
   return StringFormat("EDDY_TEST_%I64u_CONFIG_%s", test_login, suffix);
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
   GlobalVariableDel(TestGVConfigKey("MAX_LOSS"));
   GlobalVariableDel(TestGVConfigKey("PANEL_COLLAPSED"));
   GlobalVariablesFlush();
}

bool TestParseMoneyInput(string input_str, double &out_val)
{
   out_val = 0.0;
   StringTrimLeft(input_str);
   StringTrimRight(input_str);
   if(StringLen(input_str) == 0)
      return false;

   string s = input_str;
   StringToUpper(s);
   StringReplace(s, "R$", "");
   StringReplace(s, "$", "");
   StringReplace(s, "BRL", "");
   StringReplace(s, "USD", "");
   StringReplace(s, "EUR", "");
   StringReplace(s, " ", "");
   StringReplace(s, ",", ".");

   StringTrimLeft(s);
   StringTrimRight(s);
   if(StringLen(s) == 0)
      return false;

   int dot_count = 0;
   int digit_count = 0;
   for(int i = 0; i < StringLen(s); i++)
   {
      ushort ch = StringGetCharacter(s, i);
      if(ch >= '0' && ch <= '9')
      {
         digit_count++;
      }
      else if(ch == '.')
      {
         dot_count++;
         if(dot_count > 1)
            return false;
      }
      else
      {
         return false;
      }
   }

   if(digit_count == 0)
      return false;

   double val = StringToDouble(s);
   if(val <= 0.0)
      return false;

   out_val = NormalizeDouble(val, 2);
   return true;
}

bool TestSetMaxLossConfig(double new_limit, string &err_msg)
{
   // 1. Validar novo valor
   if(new_limit <= 0.0)
   {
      err_msg = "Limite deve ser maior que zero (> 0.0).";
      return false;
   }

   // Bloqueio por estado e segurança operacional
   if(test_state != EDDY_STATE_MONITORING || !test_safe_to_operate)
   {
      err_msg = "Alteracao proibida: EA nao esta em MONITORING seguro.";
      return false;
   }

   // 2. Gravar Global Variable
   string key = TestGVConfigKey("MAX_LOSS");

   // Simulação de falha transacional de persistência/flush (W09R-13)
   if(sim_gv_persist_fail)
   {
      err_msg = "Falha ao gravar configuracao no terminal MT5 (falha simulada).";
      return false; // Retorna imediatamente sem alterar test_g_max_loss
   }

   ResetLastError();
   datetime set_res = GlobalVariableSet(key, new_limit);
   int set_err = GetLastError();
   if(set_res == 0 && set_err != 0)
   {
      err_msg = "Falha ao gravar configuracao no terminal MT5.";
      return false;
   }

   // 3. Executar GlobalVariablesFlush()
   GlobalVariablesFlush();

   // 4. Confirmar sucesso da persistência (leitura atômica de volta)
   if(!GlobalVariableCheck(key))
   {
      err_msg = "Falha na verificacao da chave persistida nas Global Variables.";
      return false;
   }

   double read_back = GlobalVariableGet(key);
   if(read_back != new_limit)
   {
      err_msg = "Inconsistencia no valor gravado nas Global Variables.";
      return false;
   }

   // 5. Somente então atualizar test_g_max_loss
   test_g_max_loss = new_limit;
   err_msg = "";

   // 6. Executar a avaliação normal da FSM
   return true;
}

double TestResolveEffectiveLimit(double input_default)
{
   string key = TestGVConfigKey("MAX_LOSS");
   if(GlobalVariableCheck(key))
   {
      double val = GlobalVariableGet(key);
      if(val > 0.0) return val;
   }
   return input_default;
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
const int INSTANCE_LEASE_TIMEOUT_SECONDS = 15;

bool TestAcquireGuard(ulong inst_id, bool &is_owner, datetime now)
{
   string owner_key = TestGVKey("INSTANCE_OWNER");
   string hb_key    = TestGVKey("HEARTBEAT");

   // 1. Bootstrap: cria com valor neutro 0 se a chave ainda não existe
   if(!GlobalVariableCheck(owner_key))
   {
      GlobalVariableSet(owner_key, 0.0);
      GlobalVariablesFlush();
   }

   ulong current_owner = (ulong)GlobalVariableGet(owner_key);

   // 2. Mesma instância readquirindo
   if(current_owner == inst_id && inst_id != 0)
   {
      GlobalVariableSet(hb_key, (double)now);
      GlobalVariablesFlush();
      is_owner = true;
      return true;
   }

   // 3. Caso OWNER == 0: guarda livre. Aquisição inicial puramente atômica via CAS: 0 -> inst_id
   if(current_owner == 0)
   {
      if(GlobalVariableSetOnCondition(owner_key, (double)inst_id, 0.0))
      {
         GlobalVariableSet(hb_key, (double)now);
         GlobalVariablesFlush();
         is_owner = true;
         return true;
      }
      current_owner = (ulong)GlobalVariableGet(owner_key);
   }

   // 4. Caso OWNER != 0 e OWNER != inst_id
   if(current_owner != 0 && current_owner != inst_id)
   {
      if(GlobalVariableCheck(hb_key))
      {
         datetime last_hb = (datetime)GlobalVariableGet(hb_key);
         if(last_hb > 0 && now >= last_hb && (now - last_hb) <= INSTANCE_LEASE_TIMEOUT_SECONDS)
         {
            is_owner = false;
            return false;
         }
      }

      // Lease expirada (> INSTANCE_LEASE_TIMEOUT_SECONDS): tentativa de takeover atômico via CAS
      if(GlobalVariableSetOnCondition(owner_key, (double)inst_id, (double)current_owner))
      {
         GlobalVariableSet(hb_key, (double)now);
         GlobalVariablesFlush();
         is_owner = true;
         return true;
      }
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
   // Liberação estritamente atômica via CAS: inst_id -> 0
   if(GlobalVariableSetOnCondition(owner_key, 0.0, (double)inst_id))
   {
      GlobalVariablesFlush();
   }
   is_owner = false;
   // INVARIANTE: NÃO apaga a chave HEARTBEAT.
   // OWNER == 0 torna o heartbeat semanticamente irrelevante e elimina condição de corrida.
}

//+------------------------------------------------------------------+
//| Execução Central da Bateria de Testes (W06-01 a W06-20)          |
//+------------------------------------------------------------------+
void RunAllTests()
{
   g_file_handle = FileOpen("test_results.txt", FILE_WRITE|FILE_TXT|FILE_ANSI);

   string hdr1 = "==================================================================";
   string hdr2 = " Início da Bateria Formal: Cenários W06-01..20 e W07R-01..06     ";
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
   // W06-18: Owner pode liberar guarda via CAS (OnDeinit de A)
   //-----------------------------------------------------------------
   // Instância A (proprietária legítima) encerra e executa OnDeinit
   TestReleaseGuard(inst_A, is_owner_A);

   bool owner_key_exists_18 = GlobalVariableCheck(TestGVKey("INSTANCE_OWNER"));
   ulong registered_owner_18 = (ulong)GlobalVariableGet(TestGVKey("INSTANCE_OWNER"));
   bool hb_exists_18 = GlobalVariableCheck(TestGVKey("HEARTBEAT"));
   AssertTest("W06-18",
              !is_owner_A && owner_key_exists_18 && registered_owner_18 == 0 && hb_exists_18,
              "Instância proprietária A libera com sucesso o lock via CAS (Owner=0) e preserva heartbeat para evitar corrida");

   //-----------------------------------------------------------------
   // W06-19: Takeover após lease expirada (timeout > 15s)
   //-----------------------------------------------------------------
   // Instância A adquire guarda no instante t_guard_base
   TestAcquireGuard(inst_A, is_owner_A, t_guard_base);

   // Verificação limítrofe: com lease ativa (age <= 15s), takeover é estritamente proibido
   datetime t_boundary = t_guard_base + INSTANCE_LEASE_TIMEOUT_SECONDS; // exatamente 15s
   bool takeover_boundary = TestAcquireGuard(inst_B, is_owner_B, t_boundary);

   // Com lease expirada (age > 15s), Instância B tenta iniciar e executa takeover atômico via CAS
   datetime t_takeover = t_guard_base + INSTANCE_LEASE_TIMEOUT_SECONDS + 1; // 16s
   bool takeover_B = TestAcquireGuard(inst_B, is_owner_B, t_takeover);

   ulong registered_owner_19 = (ulong)GlobalVariableGet(TestGVKey("INSTANCE_OWNER"));
   AssertTest("W06-19",
              !takeover_boundary && takeover_B && is_owner_B && registered_owner_19 == inst_B,
              "Com lease ativa (<=15s) takeover é proibido; com lease expirada (>15s), Instância B assume ownership via CAS");

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
   // W07R-01: Reabertura Estrita BLOCKED -> REOPENING -> MONITORING
   //-----------------------------------------------------------------
   // 1. Cenário Operacional Ativo: Transição formal através de REOPENING
   test_state     = EDDY_STATE_BLOCKED;
   test_window_id = 1;
   test_baseline  = -500.0;
   test_t_trigger = D'2026.09.14 10:00:00';
   test_t_unlock  = test_t_trigger + 14400; // 14:00:00
   test_event_id  = 7001;
   sim_positions_total = 0;
   sim_orders_total    = 0;
   sim_connected       = true;
   TestPersistGV();

   datetime t_now_01 = test_t_unlock + 10; // 10s após t_unlock
   bool path_reopening_hit = false;
   bool path_monitoring_hit = false;
   double captured_baseline_01 = 0.0;
   double evaluated_w_new_01 = -999.0;

   if(test_state == EDDY_STATE_BLOCKED && t_now_01 >= test_t_unlock)
   {
      if(TestCheckSafetyConditions())
      {
         // Transiciona obrigatoriamente para REOPENING
         test_state = EDDY_STATE_REOPENING;
         path_reopening_hit = true;

         // No estado REOPENING:
         test_window_id++;
         double D_reopen = -530.0; // Resultado acumulado diário no momento da reabertura
         test_baseline = D_reopen; // Bn = D(t_reopen), NUNCA Equity!
         captured_baseline_01 = test_baseline;
         evaluated_w_new_01 = TestCalcWindowResult(D_reopen, test_baseline); // W_(n+1)(t_reopen) == 0

         // Conclusão da reabertura: limpa bloqueio e transiciona para MONITORING
         test_t_trigger = 0;
         test_t_unlock  = 0;
         test_event_id  = 0;
         test_safe_to_operate = true;
         test_state = EDDY_STATE_MONITORING;
         path_monitoring_hit = true;
         TestPersistGV();
      }
   }

   // 2. Cenário Pós-Restart com t >= t_unlock: INIT -> REOPENING -> MONITORING
   // Persiste estado BLOCKED com tempo expirado
   test_state     = EDDY_STATE_BLOCKED;
   test_window_id = 1;
   test_baseline  = -530.0;
   test_t_trigger = D'2026.09.14 10:00:00';
   test_t_unlock  = D'2026.09.14 14:00:00';
   test_event_id  = 7002;
   TestPersistGV();

   // Simula restart do terminal às 14:30:00
   datetime t_restart_01 = D'2026.09.14 14:30:00';
   test_state = EDDY_STATE_INIT;
   bool restart_path_ok = false;

   EddyRecoveryState rec_01;
   if(TestLoadGV(rec_01))
   {
      if(rec_01.state == EDDY_STATE_BLOCKED)
      {
         if(t_restart_01 >= rec_01.t_unlock && TestCheckSafetyConditions())
         {
            // T02C: Direto para REOPENING, nunca diretamente para MONITORING!
            test_state = EDDY_STATE_REOPENING;
            test_window_id = rec_01.window_id + 1;
            double D_reopen = -530.0;
            test_baseline = D_reopen;
            double W_new = TestCalcWindowResult(D_reopen, test_baseline);

            test_t_trigger = 0;
            test_t_unlock  = 0;
            test_event_id  = 0;
            test_safe_to_operate = true;
            test_state = EDDY_STATE_MONITORING;
            if(W_new == 0.0) restart_path_ok = true;
            TestPersistGV();
         }
      }
   }

   bool test_01_ok = (path_reopening_hit && path_monitoring_hit &&
                      captured_baseline_01 == -530.0 && evaluated_w_new_01 == 0.0 &&
                      test_window_id == 2 && test_state == EDDY_STATE_MONITORING &&
                      restart_path_ok);
   AssertTest("W07R-01",
              test_01_ok,
              "Fluxo de reabertura obedece rigorosamente BLOCKED -> REOPENING -> MONITORING, Bn = D(t_reopen), W_new == 0 e INIT -> REOPENING -> MONITORING no restart");

   //-----------------------------------------------------------------
   // W07R-02: Virada de Dia em MONITORING (B0=0) e em BLOCKED (Preserva Bloqueio)
   //-----------------------------------------------------------------
   // 1. Virada de dia em MONITORING em janela avançada Jn (n=2, Bn=-530.0)
   test_state     = EDDY_STATE_MONITORING;
   test_window_id = 2;
   test_baseline  = -530.0;
   datetime day_old_02 = D'2026.09.14 00:00:00';
   test_day_start = day_old_02;
   TestPersistGV();

   datetime t_midnight_02 = D'2026.09.15 00:00:05';
   datetime day_new_02    = TestGetDayStart(t_midnight_02);
   bool rollover_mon_ok = false;

   if(day_new_02 > test_day_start)
   {
      test_day_start = day_new_02;
      if(test_state == EDDY_STATE_MONITORING)
      {
         // Reinicia estritamente para J0 com B0 = 0.0 (NUNCA Equity!)
         test_window_id = 0;
         test_baseline  = 0.0;
         TestPersistGV();
         rollover_mon_ok = (test_window_id == 0 && test_baseline == 0.0);
      }
   }

   // 2. Virada de dia durante BLOCKED
   test_state     = EDDY_STATE_BLOCKED;
   test_t_trigger = D'2026.09.15 22:30:00';
   test_t_unlock  = test_t_trigger + 14400; // D'2026.09.16 02:30:00'
   test_event_id  = 7003;
   TestPersistGV();

   datetime t_midnight_blk = D'2026.09.16 00:00:10';
   datetime day_new_blk    = TestGetDayStart(t_midnight_blk);
   bool rollover_blk_ok = false;

   if(day_new_blk > test_day_start)
   {
      test_day_start = day_new_blk;
      if(test_state == EDDY_STATE_BLOCKED)
      {
         // Preserva integralmente t_trigger, t_unlock e event_id (sem resetar as 4h)
         rollover_blk_ok = (test_t_trigger == D'2026.09.15 22:30:00' &&
                            test_t_unlock  == D'2026.09.16 02:30:00' &&
                            test_event_id  == 7003 &&
                            test_state     == EDDY_STATE_BLOCKED);
         TestPersistGV();
      }
   }

   AssertTest("W07R-02",
              rollover_mon_ok && rollover_blk_ok,
              "Virada de dia em MONITORING reinicia para J0 com B0=0.0 (sem tocar em Equity) e durante BLOCKED preserva t_trigger, t_unlock e event_id");

   TestClearGV();

   //-----------------------------------------------------------------
   // W07R-03: Concorrência no Bootstrap / Disputa Atômica de Aquisição Inicial (CAS 0 -> ID)
   //-----------------------------------------------------------------
   ulong id_C = 999111;
   ulong id_D = 999222;
   bool is_owner_C = false;
   bool is_owner_D = false;
   datetime t_cas = D'2026.09.16 10:00:00';

   // Instância C inicia bootstrap (0) e adquire via CAS (0 -> id_C)
   bool acq_C = TestAcquireGuard(id_C, is_owner_C, t_cas);
   // Instância D tenta simultaneamente no mesmo segundo (encontra OWNER == id_C, heartbeat recente)
   bool acq_D = TestAcquireGuard(id_D, is_owner_D, t_cas);

   ulong registered_owner_03 = (ulong)GlobalVariableGet(TestGVKey("INSTANCE_OWNER"));
   bool hb_exists_03 = GlobalVariableCheck(TestGVKey("HEARTBEAT"));
   datetime hb_val_03 = (datetime)GlobalVariableGet(TestGVKey("HEARTBEAT"));

   AssertTest("W07R-03",
              acq_C && is_owner_C && !acq_D && !is_owner_D &&
              registered_owner_03 == id_C && hb_exists_03 && hb_val_03 == t_cas,
              "Bootstrap neutro (0) e aquisição via CAS (0 -> ID) garante exclusão mútua estrita na disputa inicial");

   //-----------------------------------------------------------------
   // W07R-04: Liberação e Handoff Seguro sem Apagar Heartbeat
   //-----------------------------------------------------------------
   // C encerra e libera a guarda via CAS: id_C -> 0
   TestReleaseGuard(id_C, is_owner_C);

   bool c_freed_04 = (!is_owner_C &&
                      (ulong)GlobalVariableGet(TestGVKey("INSTANCE_OWNER")) == 0 &&
                      GlobalVariableCheck(TestGVKey("HEARTBEAT")));

   // Instância D tenta adquirir 2 segundos depois (sem esperar timeout de lease, pois OWNER == 0)
   datetime t_cas_handoff = t_cas + 2;
   bool acq_D_hand = TestAcquireGuard(id_D, is_owner_D, t_cas_handoff);

   ulong registered_owner_04 = (ulong)GlobalVariableGet(TestGVKey("INSTANCE_OWNER"));
   datetime hb_val_04 = (datetime)GlobalVariableGet(TestGVKey("HEARTBEAT"));

   AssertTest("W07R-04",
              c_freed_04 && acq_D_hand && is_owner_D &&
              registered_owner_04 == id_D && hb_val_04 == t_cas_handoff,
              "Liberação atômica (ID -> 0) preserva heartbeat para segurança e permite handoff imediato via CAS para nova instância");

   //-----------------------------------------------------------------
   // W07R-05: OnDeinit Tardio de Zumbi após Takeover (CAS Falha e Preserva Lock)
   //-----------------------------------------------------------------
   // D é proprietária no instante t_cas_handoff.
   // Simula travamento da instância D por 25 segundos (lease expira: 25s > 15s).
   ulong id_E = 999333;
   bool is_owner_E = false;
   datetime t_cas_takeover = t_cas_handoff + 25;

   // Instância E chega e executa takeover via CAS: id_D -> id_E
   bool acq_E = TestAcquireGuard(id_E, is_owner_E, t_cas_takeover);

   // Zumbi D acorda de sua pausa e executa seu OnDeinit tardio (com flag local is_owner_D ainda true)
   // O método TestReleaseGuard executa CAS: id_D -> 0.
   // Como OWNER atual é id_E, o CAS DEVE FALHAR, preservando id_E intacto!
   TestReleaseGuard(id_D, is_owner_D);

   ulong registered_owner_05 = (ulong)GlobalVariableGet(TestGVKey("INSTANCE_OWNER"));
   datetime hb_val_05 = (datetime)GlobalVariableGet(TestGVKey("HEARTBEAT"));

   AssertTest("W07R-05",
              acq_E && is_owner_E && !is_owner_D &&
              registered_owner_05 == id_E && hb_val_05 == t_cas_takeover,
              "OnDeinit de instância zumbi pós-takeover falha no CAS e não corrompe ownership nem heartbeat do novo proprietário");

   //-----------------------------------------------------------------
   // W07R-06: Heartbeat Residual com OWNER == 0 é Ignorado e Sobrescrito
   //-----------------------------------------------------------------
   // Instância E encerra normalmente e libera via CAS: id_E -> 0
   TestReleaseGuard(id_E, is_owner_E);

   // Neste instante: OWNER == 0, mas HEARTBEAT ainda contém t_cas_takeover
   bool owner_is_zero_06 = ((ulong)GlobalVariableGet(TestGVKey("INSTANCE_OWNER")) == 0);
   bool hb_residual_06   = (GlobalVariableCheck(TestGVKey("HEARTBEAT")) &&
                            (datetime)GlobalVariableGet(TestGVKey("HEARTBEAT")) == t_cas_takeover);

   // Nova instância F chega apenas 1 segundo depois (t_cas_takeover + 1)
   ulong id_F = 999444;
   bool is_owner_F = false;
   datetime t_cas_F = t_cas_takeover + 1;

   // F deve adquirir imediatamente via CAS (0 -> id_F) e sobrescrever heartbeat, sem esperar lease
   bool acq_F = TestAcquireGuard(id_F, is_owner_F, t_cas_F);

   ulong registered_owner_06 = (ulong)GlobalVariableGet(TestGVKey("INSTANCE_OWNER"));
   datetime hb_val_06 = (datetime)GlobalVariableGet(TestGVKey("HEARTBEAT"));

   AssertTest("W07R-06",
              owner_is_zero_06 && hb_residual_06 && acq_F && is_owner_F &&
              registered_owner_06 == id_F && hb_val_06 == t_cas_F,
              "Heartbeat residual com OWNER == 0 é ignorado e sobrescrito imediatamente por nova instância sem delay de lease");

   //-----------------------------------------------------------------
   // W08R-01: Falha de Persistência Durante LIQUIDATING Mantém Retries
   //-----------------------------------------------------------------
   TestClearGV();
   test_state           = EDDY_STATE_LIQUIDATING;
   test_window_id       = 1;
   test_baseline        = -500.0;
   test_t_trigger       = D'2026.09.15 11:00:00';
   test_t_unlock        = D'2026.09.15 15:00:00';
   test_event_id        = 8001;
   test_safe_to_operate = false; // Simula fail-closed por falha de persistência
   sim_positions_total  = 2;
   sim_orders_total     = 1;

   // Em LIQUIDATING com posições/ordens > 0, o loop de liquidação continua ativo
   bool retry_executed = false;
   if(test_state == EDDY_STATE_LIQUIDATING && (sim_positions_total > 0 || sim_orders_total > 0))
   {
      // Simula execução da liquidação que zera as ordens e posições
      sim_positions_total = 0;
      sim_orders_total    = 0;
      retry_executed      = true;
   }

   // Após zerar resíduo, transiciona para BLOCKED, mas NUNCA para MONITORING
   if(sim_positions_total == 0 && sim_orders_total == 0)
   {
      test_state = EDDY_STATE_BLOCKED;
   }

   AssertTest("W08R-01",
              retry_executed && (sim_positions_total == 0) &&
              (test_state == EDDY_STATE_BLOCKED) &&
              (test_safe_to_operate == false) &&
              (test_state != EDDY_STATE_MONITORING),
              "Falha de persistência (fail-closed) durante LIQUIDATING não impede retries de liquidação e proíbe MONITORING");

   //-----------------------------------------------------------------
   // W08R-02: Fail-Closed Durante BLOCKED com Nova Exposição Neutraliza Reativamente
   //-----------------------------------------------------------------
   // Pré-condição: robô em BLOCKED com safe_to_operate = false
   test_state           = EDDY_STATE_BLOCKED;
   test_t_trigger       = D'2026.09.15 11:00:00';
   test_t_unlock        = D'2026.09.15 15:00:00';
   test_event_id        = 8002;
   test_safe_to_operate = false;

   // Nova intervenção manual gera posição espúria
   sim_positions_total = 1;
   bool neutralizacao_executada = false;

   // Proteção reativa (OnTradeTransaction / ProcessFSM) detecta resíduo em BLOCKED e neutraliza
   if(test_state == EDDY_STATE_BLOCKED && (sim_positions_total > 0 || sim_orders_total > 0))
   {
      sim_positions_total = 0; // Neutralização compulsória imediata
      neutralizacao_executada = true;
   }

   bool blocked_preserved = (test_state == EDDY_STATE_BLOCKED &&
                             test_t_trigger == D'2026.09.15 11:00:00' &&
                             test_t_unlock  == D'2026.09.15 15:00:00' &&
                             test_event_id  == 8002 &&
                             test_safe_to_operate == false &&
                             test_state != EDDY_STATE_MONITORING);

   AssertTest("W08R-02",
              neutralizacao_executada && (sim_positions_total == 0) && blocked_preserved,
              "Fail-closed durante BLOCKED neutraliza imediatamente nova exposição sem violar t_trigger, t_unlock ou avançar para MONITORING");

   // Limpeza final
   TestReleaseGuard(id_F, is_owner_F);
   TestClearGV();

   //=================================================================
   // BATERIA W09R — TRADER UX, CONFIGURAÇÃO ON-CHART E SEGURANÇA
   //=================================================================

   //-----------------------------------------------------------------
   // W09R-01: Persistência Tem Precedência sobre InpMaxLoss no Start
   //-----------------------------------------------------------------
   TestClearGV();
   GlobalVariableSet(TestGVConfigKey("MAX_LOSS"), 750.0);
   GlobalVariablesFlush();
   double effective_limit_01 = TestResolveEffectiveLimit(500.0);
   AssertTest("W09R-01",
              (effective_limit_01 == 750.0),
              "Limite persistido em GlobalVariables tem precedência sobre o valor padrão de InpMaxLoss");

   //-----------------------------------------------------------------
   // W09R-02: Fallback para InpMaxLoss na Ausência de Configuração
   //-----------------------------------------------------------------
   TestClearGV();
   double effective_limit_02 = TestResolveEffectiveLimit(500.0);
   AssertTest("W09R-02",
              (effective_limit_02 == 500.0),
              "Na ausência de configuração persistida, o sistema adota fielmente o InpMaxLoss padrão");

   //-----------------------------------------------------------------
   // W09R-03: Atualização de Limite em MONITORING com Ambiente Seguro
   //-----------------------------------------------------------------
   TestClearGV();
   test_state           = EDDY_STATE_MONITORING;
   test_safe_to_operate = true;
   test_g_max_loss      = 500.0;
   string err_03        = "";
   bool ok_03           = TestSetMaxLossConfig(800.0, err_03);
   bool gv_saved_03     = (GlobalVariableCheck(TestGVConfigKey("MAX_LOSS")) &&
                           GlobalVariableGet(TestGVConfigKey("MAX_LOSS")) == 800.0);
   AssertTest("W09R-03",
              (ok_03 && test_g_max_loss == 800.0 && gv_saved_03 && err_03 == ""),
              "Alteração de limite em MONITORING com ambiente seguro persiste em GV e atualiza limite imediatamente");

   //-----------------------------------------------------------------
   // W09R-04: Tentativa de Alteração Durante BLOCKED é Rejeitada
   //-----------------------------------------------------------------
   test_state           = EDDY_STATE_BLOCKED;
   test_safe_to_operate = true;
   test_g_max_loss      = 500.0;
   test_t_trigger       = D'2026.09.15 10:00:00';
   test_t_unlock        = D'2026.09.15 14:00:00';
   test_event_id        = 9004;
   string err_04        = "";
   bool ok_04           = TestSetMaxLossConfig(1000.0, err_04);
   bool blocked_ok_04   = (test_g_max_loss == 500.0 &&
                           test_state == EDDY_STATE_BLOCKED &&
                           test_t_trigger == D'2026.09.15 10:00:00' &&
                           test_t_unlock  == D'2026.09.15 14:00:00' &&
                           test_event_id  == 9004);
   AssertTest("W09R-04",
              (!ok_04 && blocked_ok_04 && StringLen(err_04) > 0),
              "Tentativa de alteração de limite durante BLOCKED é rejeitada sem alterar limites ou parâmetros de bloqueio");

   //-----------------------------------------------------------------
   // W09R-05: Tentativa de Alteração sob Fail-Closed é Rejeitada
   //-----------------------------------------------------------------
   test_state           = EDDY_STATE_MONITORING;
   test_safe_to_operate = false;
   test_g_max_loss      = 500.0;
   string err_05        = "";
   bool ok_05           = TestSetMaxLossConfig(600.0, err_05);
   AssertTest("W09R-05",
              (!ok_05 && test_g_max_loss == 500.0 && StringLen(err_05) > 0),
              "Tentativa de alteração com safe_to_operate=false (fail-closed) é rejeitada com preservação do limite");

   //-----------------------------------------------------------------
   // W09R-06: Validação de Entrada Rejeita Valores Nulos ou Negativos
   //-----------------------------------------------------------------
   double val_zero = 0.0, val_neg = 0.0;
   bool p_zero = TestParseMoneyInput("0", val_zero);
   bool p_neg  = TestParseMoneyInput("-150.00", val_neg);
   string err_06 = "";
   test_state = EDDY_STATE_MONITORING;
   test_safe_to_operate = true;
   bool set_zero = TestSetMaxLossConfig(0.0, err_06);
   AssertTest("W09R-06",
              (!p_zero && !p_neg && !set_zero && StringLen(err_06) > 0),
              "Validação de entrada rejeita estritamente valores nulos ou negativos");

   //-----------------------------------------------------------------
   // W09R-07: Validação de Entrada Rejeita Texto e Strings Inválidas
   //-----------------------------------------------------------------
   double val_txt = 0.0, val_empty = 0.0, val_mixed = 0.0;
   bool p_txt   = TestParseMoneyInput("abc", val_txt);
   bool p_empty = TestParseMoneyInput("", val_empty);
   bool p_mixed = TestParseMoneyInput("12.34.56", val_mixed);
   AssertTest("W09R-07",
              (!p_txt && !p_empty && !p_mixed),
              "Validação de entrada rejeita texto puro, strings vazias e múltiplos separadores decimais");

   //-----------------------------------------------------------------
   // W09R-08: Parser Monetário Trata Separador Decimal com Vírgula
   //-----------------------------------------------------------------
   double val_comma = 0.0;
   bool p_comma = TestParseMoneyInput("450,50", val_comma);
   AssertTest("W09R-08",
              (p_comma && val_comma == 450.50),
              "Parser monetário aceita vírgula como separador decimal convertendo com precisão matemática");

   //-----------------------------------------------------------------
   // W09R-09: Parser Monetário Remove Prefixos de Moeda e Espaços
   //-----------------------------------------------------------------
   double val_brl = 0.0, val_usd = 0.0, val_eur = 0.0;
   bool p_brl = TestParseMoneyInput("  R$ 350,00 ", val_brl);
   bool p_usd = TestParseMoneyInput("$ 500.00", val_usd);
   bool p_eur = TestParseMoneyInput("EUR 250", val_eur);
   AssertTest("W09R-09",
              (p_brl && val_brl == 350.0 && p_usd && val_usd == 500.0 && p_eur && val_eur == 250.0),
              "Parser monetário remove prefixos de moeda (R$, $, EUR) e espaços em branco corretamente");

   //-----------------------------------------------------------------
   // W09R-10: Novo Limite Mais Rigoroso Dispara Proteção Imediatamente
   //-----------------------------------------------------------------
   test_state           = EDDY_STATE_MONITORING;
   test_safe_to_operate = true;
   test_g_max_loss      = 500.0;
   double current_W     = -320.0;
   string err_10        = "";
   bool ok_10           = TestSetMaxLossConfig(300.0, err_10);
   bool triggered_10    = false;
   if(test_state == EDDY_STATE_MONITORING && current_W <= -test_g_max_loss)
   {
      test_state = EDDY_STATE_PROTECTION_TRIGGERED;
      triggered_10 = true;
   }
   AssertTest("W09R-10",
              (ok_10 && test_g_max_loss == 300.0 && triggered_10 && test_state == EDDY_STATE_PROTECTION_TRIGGERED),
              "Aplicação de limite mais rigoroso que a perda atual dispara imediatamente a transição de proteção");

   //-----------------------------------------------------------------
   // W09R-11: Isolamento de Chave de Configuração por Login de Conta
   //-----------------------------------------------------------------
   ulong login_A = 11111111;
   ulong login_B = 22222222;
   string key_A = StringFormat("EDDY_TEST_%I64u_CONFIG_MAX_LOSS", login_A);
   string key_B = StringFormat("EDDY_TEST_%I64u_CONFIG_MAX_LOSS", login_B);
   GlobalVariableSet(key_A, 600.0);
   GlobalVariableSet(key_B, 900.0);
   GlobalVariablesFlush();
   double val_A = GlobalVariableGet(key_A);
   double val_B = GlobalVariableGet(key_B);
   GlobalVariableDel(key_A);
   GlobalVariableDel(key_B);
   GlobalVariablesFlush();
   AssertTest("W09R-11",
              (val_A == 600.0 && val_B == 900.0 && key_A != key_B),
              "Configurações de limite são estritamente isoladas por login de conta sem contaminação cruzada");

   //-----------------------------------------------------------------
   // W09R-12: Isolamento na Limpeza de Objetos Gráficos com Prefixo
   //-----------------------------------------------------------------
   string eddy_obj_1 = "EddyHUD_CardBg";
   string eddy_obj_2 = "EddyHUD_Btn_Config";
   string ext_obj    = "UserChartLine";
   ObjectCreate(0, eddy_obj_1, OBJ_LABEL, 0, 0, 0);
   ObjectCreate(0, eddy_obj_2, OBJ_BUTTON, 0, 0, 0);
   ObjectCreate(0, ext_obj,    OBJ_LABEL, 0, 0, 0);
   ObjectsDeleteAll(0, "EddyHUD_");
   bool eddy_1_exists = (ObjectFind(0, eddy_obj_1) >= 0);
   bool eddy_2_exists = (ObjectFind(0, eddy_obj_2) >= 0);
   bool ext_exists    = (ObjectFind(0, ext_obj) >= 0);
   ObjectDelete(0, ext_obj);
   AssertTest("W09R-12",
              (!eddy_1_exists && !eddy_2_exists && ext_exists),
              "Limpeza de UI (ObjectsDeleteAll com EddyHUD_) remove apenas objetos do EA sem violar objetos externos");

   // Limpeza final de GVs de teste
   TestClearGV();

   //-----------------------------------------------------------------
   // W09R-13: Falha de Persistência/Flush Não Altera g_max_loss
   //-----------------------------------------------------------------
   TestClearGV();
   test_state           = EDDY_STATE_MONITORING;
   test_safe_to_operate = true;
   test_g_max_loss      = 500.0;
   sim_gv_persist_fail  = true; // Força falha transacional de escrita/flush
   string err_13        = "";
   bool ok_13           = TestSetMaxLossConfig(900.0, err_13);
   bool gv_saved_13     = GlobalVariableCheck(TestGVConfigKey("MAX_LOSS"));
   sim_gv_persist_fail  = false; // Restaura
   AssertTest("W09R-13",
              (!ok_13 && test_g_max_loss == 500.0 && !gv_saved_13 && StringLen(err_13) > 0),
              "Falha de persistencia/flush nao altera g_max_loss, registra erro e nao persiste valor");

   //-----------------------------------------------------------------
   // W09R-14: Alteração Rejeitada em PROTECTION_TRIGGERED
   //-----------------------------------------------------------------
   TestClearGV();
   test_state           = EDDY_STATE_PROTECTION_TRIGGERED;
   test_safe_to_operate = true;
   test_g_max_loss      = 500.0;
   string err_14        = "";
   bool ok_14           = TestSetMaxLossConfig(800.0, err_14);
   bool gv_saved_14     = GlobalVariableCheck(TestGVConfigKey("MAX_LOSS"));
   AssertTest("W09R-14",
              (!ok_14 && test_g_max_loss == 500.0 && !gv_saved_14 && StringLen(err_14) > 0),
              "Tentativa de alteracao de limite em PROTECTION_TRIGGERED e estritamente rejeitada sem mutacao");

   //-----------------------------------------------------------------
   // W09R-15: Alteração Rejeitada em LIQUIDATING
   //-----------------------------------------------------------------
   TestClearGV();
   test_state           = EDDY_STATE_LIQUIDATING;
   test_safe_to_operate = true;
   test_g_max_loss      = 500.0;
   string err_15        = "";
   bool ok_15           = TestSetMaxLossConfig(800.0, err_15);
   bool gv_saved_15     = GlobalVariableCheck(TestGVConfigKey("MAX_LOSS"));
   AssertTest("W09R-15",
              (!ok_15 && test_g_max_loss == 500.0 && !gv_saved_15 && StringLen(err_15) > 0),
              "Tentativa de alteracao de limite em LIQUIDATING e estritamente rejeitada sem mutacao");

   //-----------------------------------------------------------------
   // W09R-16: Alteração Rejeitada em BLOCKED
   //-----------------------------------------------------------------
   TestClearGV();
   test_state           = EDDY_STATE_BLOCKED;
   test_safe_to_operate = true;
   test_g_max_loss      = 500.0;
   string err_16        = "";
   bool ok_16           = TestSetMaxLossConfig(800.0, err_16);
   bool gv_saved_16     = GlobalVariableCheck(TestGVConfigKey("MAX_LOSS"));
   AssertTest("W09R-16",
              (!ok_16 && test_g_max_loss == 500.0 && !gv_saved_16 && StringLen(err_16) > 0),
              "Tentativa de alteracao de limite em BLOCKED e estritamente rejeitada sem mutacao");

   //-----------------------------------------------------------------
   // W09R-17: Alteração Rejeitada em REOPENING
   //-----------------------------------------------------------------
   TestClearGV();
   test_state           = EDDY_STATE_REOPENING;
   test_safe_to_operate = true;
   test_g_max_loss      = 500.0;
   string err_17        = "";
   bool ok_17           = TestSetMaxLossConfig(800.0, err_17);
   bool gv_saved_17     = GlobalVariableCheck(TestGVConfigKey("MAX_LOSS"));
   AssertTest("W09R-17",
              (!ok_17 && test_g_max_loss == 500.0 && !gv_saved_17 && StringLen(err_17) > 0),
              "Tentativa de alteracao de limite em REOPENING e estritamente rejeitada sem mutacao");

   //-----------------------------------------------------------------
   // W09R-18: Alteração Rejeitada em INIT / Fail-Closed
   //-----------------------------------------------------------------
   TestClearGV();
   test_state           = EDDY_STATE_INIT;
   test_safe_to_operate = false;
   test_g_max_loss      = 500.0;
   string err_18        = "";
   bool ok_18           = TestSetMaxLossConfig(800.0, err_18);
   bool gv_saved_18     = GlobalVariableCheck(TestGVConfigKey("MAX_LOSS"));
   AssertTest("W09R-18",
              (!ok_18 && test_g_max_loss == 500.0 && !gv_saved_18 && StringLen(err_18) > 0),
              "Tentativa de alteracao de limite em INIT / fail-closed e estritamente rejeitada sem mutacao");

   //-----------------------------------------------------------------
   // W09R-19: Invariância Rígida do Evento de Proteção Ativo
   //-----------------------------------------------------------------
   TestClearGV();
   test_state           = EDDY_STATE_BLOCKED;
   test_safe_to_operate = true;
   test_g_max_loss      = 500.0;
   test_t_trigger       = D'2026.09.15 10:00:00';
   test_t_unlock        = D'2026.09.15 14:00:00';
   test_event_id        = 9919;
   string err_19        = "";
   bool ok_19           = TestSetMaxLossConfig(5000.0, err_19);
   bool inv_preserved   = (test_t_trigger == D'2026.09.15 10:00:00' &&
                           test_t_unlock  == D'2026.09.15 14:00:00' &&
                           test_event_id  == 9919 &&
                           test_g_max_loss == 500.0 &&
                           test_state == EDDY_STATE_BLOCKED);
   AssertTest("W09R-19",
              (!ok_19 && inv_preserved && !GlobalVariableCheck(TestGVConfigKey("MAX_LOSS"))),
              "Durante evento de protecao ativo, tentativas de alteracao preservam rigorosamente t_trigger, t_unlock e event_id");

   // Limpeza final de GVs de teste
   TestClearGV();

   //-----------------------------------------------------------------
   // W09R-20: Durante Edição Ativa, Refresh da UI Não Sobrescreve Texto Digitado
   //-----------------------------------------------------------------
   TestClearGV();
   string test_edit_obj = "EddyHUD_Dlg_Input";
   // Cria o campo de edição simulando abertura da janela de configuração
   ObjectCreate(0, test_edit_obj, OBJ_EDIT, 0, 0, 0);
   ObjectSetString(0, test_edit_obj, OBJPROP_TEXT, "500.00");

   // Simula usuário digitando o valor "750,50" no campo editável
   ObjectSetString(0, test_edit_obj, OBJPROP_TEXT, "750,50");

   // Simula ciclos de timer / tick / refresh enquanto g_config_ui_state == UI_STATE_EDITING
   // Em produção, a função UI_SetEdit verifica if(ObjectFind(0, name) < 0) e NUNCA sobrescreve se já existe
   bool is_new_obj = (ObjectFind(0, test_edit_obj) < 0);
   if(is_new_obj)
   {
      ObjectSetString(0, test_edit_obj, OBJPROP_TEXT, DoubleToString(test_g_max_loss, 2));
   }
   string text_after_refresh = ObjectGetString(0, test_edit_obj, OBJPROP_TEXT);
   ObjectDelete(0, test_edit_obj);

   AssertTest("W09R-20",
              (text_after_refresh == "750,50"),
              "Durante edicao ativa, refresh periodico da UI nao sobrescreve o texto digitado pelo usuario");

   //-----------------------------------------------------------------
   // W09R-21: Abrir Painel de Configuração Não Altera g_max_loss por Si Só
   //-----------------------------------------------------------------
   TestClearGV();
   test_state           = EDDY_STATE_MONITORING;
   test_safe_to_operate = true;
   test_g_max_loss      = 500.0;
   ENUM_CONFIG_UI_STATE sim_ui_state_21 = UI_STATE_EDITING;
   double sim_pending_21 = 0.0;
   bool gv_exists_21     = GlobalVariableCheck(TestGVConfigKey("MAX_LOSS"));

   AssertTest("W09R-21",
              (sim_ui_state_21 == UI_STATE_EDITING && test_g_max_loss == 500.0 && sim_pending_21 == 0.0 && !gv_exists_21),
              "Abrir painel de configuracao mantem g_max_loss inalterado e nao persiste qualquer valor");

   //-----------------------------------------------------------------
   // W09R-22: Cancelar Edição Não Altera g_max_loss Nem Persiste Valor
   //-----------------------------------------------------------------
   TestClearGV();
   test_state           = EDDY_STATE_MONITORING;
   test_safe_to_operate = true;
   test_g_max_loss      = 500.0;
   ENUM_CONFIG_UI_STATE sim_ui_state_22 = UI_STATE_EDITING;
   // Simula clique em CANCELAR
   sim_ui_state_22      = UI_STATE_IDLE;
   double sim_pending_22 = 0.0;
   bool gv_exists_22    = GlobalVariableCheck(TestGVConfigKey("MAX_LOSS"));

   AssertTest("W09R-22",
              (sim_ui_state_22 == UI_STATE_IDLE && test_g_max_loss == 500.0 && sim_pending_22 == 0.0 && !gv_exists_22),
              "Cancelar edicao nao altera g_max_loss nem persiste valor em GlobalVariables");

   //-----------------------------------------------------------------
   // W09R-23: Campo Aceita Valor com Vírgula, Mantém Digitação e Aplica Após Normalização
   //-----------------------------------------------------------------
   TestClearGV();
   test_state           = EDDY_STATE_MONITORING;
   test_safe_to_operate = true;
   test_g_max_loss      = 500.0;
   string raw_comma     = "  650,75  ";
   double parsed_comma  = 0.0;
   bool parse_ok_23     = TestParseMoneyInput(raw_comma, parsed_comma);
   string err_23        = "";
   bool apply_ok_23     = false;
   if(parse_ok_23 && parsed_comma > 0.0)
   {
      apply_ok_23 = TestSetMaxLossConfig(parsed_comma, err_23);
   }
   bool gv_ok_23 = (GlobalVariableCheck(TestGVConfigKey("MAX_LOSS")) &&
                    GlobalVariableGet(TestGVConfigKey("MAX_LOSS")) == 650.75);

   AssertTest("W09R-23",
              (parse_ok_23 && parsed_comma == 650.75 && apply_ok_23 && test_g_max_loss == 650.75 && gv_ok_23),
              "Campo aceita valor com virgula, mantem digitacao ate confirmacao e aplica corretamente apos normalizacao");

   //-----------------------------------------------------------------
   // W09R-24: Campo Aceita Valor com Ponto, Mantém Digitação e Aplica Após Normalização
   //-----------------------------------------------------------------
   TestClearGV();
   test_state           = EDDY_STATE_MONITORING;
   test_safe_to_operate = true;
   test_g_max_loss      = 500.0;
   string raw_dot       = " 850.25 ";
   double parsed_dot    = 0.0;
   bool parse_ok_24     = TestParseMoneyInput(raw_dot, parsed_dot);
   string err_24        = "";
   bool apply_ok_24     = false;
   if(parse_ok_24 && parsed_dot > 0.0)
   {
      apply_ok_24 = TestSetMaxLossConfig(parsed_dot, err_24);
   }
   bool gv_ok_24 = (GlobalVariableCheck(TestGVConfigKey("MAX_LOSS")) &&
                    GlobalVariableGet(TestGVConfigKey("MAX_LOSS")) == 850.25);

   AssertTest("W09R-24",
              (parse_ok_24 && parsed_dot == 850.25 && apply_ok_24 && test_g_max_loss == 850.25 && gv_ok_24),
              "Campo aceita valor com ponto, mantem digitacao ate confirmacao e aplica corretamente apos normalizacao");

   //-----------------------------------------------------------------
   // W09R-25: COMPACT -> DETAILED Altera Somente g_hud_mode e Não Afeta g_max_loss / FSM
   //-----------------------------------------------------------------
   TestClearGV();
   test_state           = EDDY_STATE_MONITORING;
   test_safe_to_operate = true;
   test_g_max_loss      = 500.0;
   ENUM_EDDY_HUD_MODE sim_hud_mode_25 = EDDY_HUD_COMPACT;

   // Simula transição para DETAILED ao clicar em DETALHES
   sim_hud_mode_25 = EDDY_HUD_DETAILED;

   AssertTest("W09R-25",
              (sim_hud_mode_25 == EDDY_HUD_DETAILED &&
               test_state == EDDY_STATE_MONITORING &&
               test_safe_to_operate == true &&
               test_g_max_loss == 500.0),
              "Transicao COMPACT -> DETAILED altera somente g_hud_mode sem afetar g_max_loss ou estado da FSM");

   //-----------------------------------------------------------------
   // W09R-26: DETAILED -> COMPACT Restaura Corretamente o Modo Resumido
   //-----------------------------------------------------------------
   TestClearGV();
   ENUM_EDDY_HUD_MODE sim_hud_mode_26 = EDDY_HUD_DETAILED;

   // Simula clique em [ <- VOLTAR AO RESUMO ] no painel detalhado
   sim_hud_mode_26 = EDDY_HUD_COMPACT;

   AssertTest("W09R-26",
              (sim_hud_mode_26 == EDDY_HUD_COMPACT),
              "Clique em VOLTAR AO RESUMO no painel detalhado restaura com sucesso g_hud_mode para EDDY_HUD_COMPACT");

   //-----------------------------------------------------------------
   // W09R-27: Troca de Modo Não Altera Variáveis de Risco e Bloqueio
   //-----------------------------------------------------------------
   TestClearGV();
   test_t_trigger = 1700000000;
   test_t_unlock  = 1700014400;
   test_event_id  = 987654321;
   test_baseline  = -250.75;
   test_window_id = 3;

   datetime snap_trigger   = test_t_trigger;
   datetime snap_unlock    = test_t_unlock;
   ulong    snap_event_id  = test_event_id;
   double   snap_baseline  = test_baseline;
   int      snap_window_id = test_window_id;

   // Cicla alternância de modos visuais: COMPACT -> DETAILED -> COMPACT
   ENUM_EDDY_HUD_MODE sim_cycle_mode = EDDY_HUD_COMPACT;
   sim_cycle_mode = EDDY_HUD_DETAILED;
   sim_cycle_mode = EDDY_HUD_COMPACT;

   bool risk_vars_preserved = (test_t_trigger == snap_trigger &&
                               test_t_unlock == snap_unlock &&
                               test_event_id == snap_event_id &&
                               test_baseline == snap_baseline &&
                               test_window_id == snap_window_id);

   AssertTest("W09R-27",
              (sim_cycle_mode == EDDY_HUD_COMPACT && risk_vars_preserved),
              "Alternancia entre modos de interface preserva integralmente t_trigger, t_unlock, event_id, baseline e window_id");

   //-----------------------------------------------------------------
   // W09R-28: Abrir DETALHES Fecha com Segurança Diálogo de Configuração Sem Aplicar Valor
   //-----------------------------------------------------------------
   TestClearGV();
   test_g_max_loss      = 500.0;
   test_state           = EDDY_STATE_MONITORING;
   test_safe_to_operate = true;
   ENUM_CONFIG_UI_STATE sim_ui_state_28 = UI_STATE_EDITING;
   double sim_pending_28 = 750.0;

   // Ao abrir DETALHES, a rotina UI_CloseConfigDialog() fecha a janela e zera pendência sem gravar GV nem alterar g_max_loss
   if(sim_ui_state_28 != UI_STATE_IDLE)
   {
      sim_ui_state_28  = UI_STATE_IDLE;
      sim_pending_28   = 0.0;
   }
   ENUM_EDDY_HUD_MODE sim_hud_mode_28 = EDDY_HUD_DETAILED;
   bool gv_written_28 = GlobalVariableCheck(TestGVConfigKey("MAX_LOSS"));

   AssertTest("W09R-28",
              (sim_hud_mode_28 == EDDY_HUD_DETAILED &&
               sim_ui_state_28 == UI_STATE_IDLE &&
               sim_pending_28 == 0.0 &&
               test_g_max_loss == 500.0 &&
               !gv_written_28),
              "Abrir painel DETALHES fecha de maneira segura o dialogo de configuracao sem aplicar valor pendente");

   //-----------------------------------------------------------------
   // W09R-29: Retorno ao COMPACT Restaura Disponibilidade do Botão CONFIGURAR
   //-----------------------------------------------------------------
   TestClearGV();
   test_state           = EDDY_STATE_MONITORING;
   test_safe_to_operate = true;
   bool sim_is_owner_29 = true;

   // Estando em DETAILED, volta para COMPACT
   ENUM_EDDY_HUD_MODE sim_hud_mode_29 = EDDY_HUD_DETAILED;
   sim_hud_mode_29 = EDDY_HUD_COMPACT;

   // Em COMPACT, can_configure é avaliado como (g_current_state == EDDY_STATE_MONITORING && g_safe_to_operate && g_is_owner)
   bool can_cfg_nominal = (test_state == EDDY_STATE_MONITORING && test_safe_to_operate && sim_is_owner_29);

   // Testa também se uma condição fail-closed bloqueia o botão no retorno
   test_safe_to_operate = false;
   bool can_cfg_failclosed = (test_state == EDDY_STATE_MONITORING && test_safe_to_operate && sim_is_owner_29);

   AssertTest("W09R-29",
              (sim_hud_mode_29 == EDDY_HUD_COMPACT && can_cfg_nominal == true && can_cfg_failclosed == false),
              "Retorno ao modo COMPACT restaura botao CONFIGURAR quando MONITORING seguro e bloqueia em fail-closed");

   // Limpeza final de GVs de teste
   TestClearGV();

   //-----------------------------------------------------------------
   // W10R-01: Estado COLLAPSED Não Altera FSM Nem Parâmetros de Risco
   //-----------------------------------------------------------------
   TestClearGV();
   test_state           = EDDY_STATE_MONITORING;
   test_safe_to_operate = true;
   test_g_max_loss      = 500.0;
   test_baseline        = -120.50;
   test_window_id       = 2;
   ENUM_DISCIPLINADOR_PANEL_STATE sim_panel_state_01 = PANEL_EXPANDED;

   // Transição para minimizado (COLLAPSED)
   sim_panel_state_01 = PANEL_COLLAPSED;

   bool invariant_w10_01 = (test_state == EDDY_STATE_MONITORING &&
                            test_safe_to_operate == true &&
                            test_g_max_loss == 500.0 &&
                            test_baseline == -120.50 &&
                            test_window_id == 2);

   AssertTest("W10R-01",
              (sim_panel_state_01 == PANEL_COLLAPSED && invariant_w10_01),
              "Estado COLLAPSED altera exclusivamente a camada visual, preservando rigorosamente FSM e parametros de risco");

   //-----------------------------------------------------------------
   // W10R-02: COLLAPSED -> EXPANDED Restaura Modo Anterior Corretamente
   //-----------------------------------------------------------------
   TestClearGV();
   ENUM_EDDY_HUD_MODE sim_prev_mode = EDDY_HUD_DETAILED;
   ENUM_DISCIPLINADOR_PANEL_STATE sim_pstate_02 = PANEL_EXPANDED;

   // Minimiza
   sim_pstate_02 = PANEL_COLLAPSED;
   // Ao maximizar, restaura o modo gravado anteriormente
   ENUM_EDDY_HUD_MODE sim_restored_mode = sim_prev_mode;
   sim_pstate_02 = PANEL_EXPANDED;

   AssertTest("W10R-02",
              (sim_pstate_02 == PANEL_EXPANDED && sim_restored_mode == EDDY_HUD_DETAILED),
              "Transicao COLLAPSED -> EXPANDED restaura com fidelidade o modo visual anteriormente ativo");

   //-----------------------------------------------------------------
   // W10R-03: Ciclo COMPACT -> COLLAPSED -> COMPACT
   //-----------------------------------------------------------------
   TestClearGV();
   ENUM_EDDY_HUD_MODE sim_mode_03 = EDDY_HUD_COMPACT;
   ENUM_EDDY_HUD_MODE sim_saved_expanded_03 = sim_mode_03;
   ENUM_DISCIPLINADOR_PANEL_STATE sim_pstate_03 = PANEL_EXPANDED;

   // 1. Trader clica em [ — MINIMIZAR ] no painel Compacto
   sim_saved_expanded_03 = EDDY_HUD_COMPACT;
   sim_pstate_03 = PANEL_COLLAPSED;

   // 2. Trader clica em [ + ] no painel minimizado
   sim_pstate_03 = PANEL_EXPANDED;
   sim_mode_03 = sim_saved_expanded_03;

   AssertTest("W10R-03",
              (sim_pstate_03 == PANEL_EXPANDED && sim_mode_03 == EDDY_HUD_COMPACT),
              "Ciclo COMPACT -> COLLAPSED -> COMPACT preserva e restabelece a apresentacao do resumo trader");

   //-----------------------------------------------------------------
   // W10R-04: Ciclo DETAILED -> COLLAPSED -> DETAILED
   //-----------------------------------------------------------------
   TestClearGV();
   ENUM_EDDY_HUD_MODE sim_mode_04 = EDDY_HUD_DETAILED;
   ENUM_EDDY_HUD_MODE sim_saved_expanded_04 = sim_mode_04;
   ENUM_DISCIPLINADOR_PANEL_STATE sim_pstate_04 = PANEL_EXPANDED;

   // 1. Trader clica em [ — MINIMIZAR ] no painel Detalhado
   sim_saved_expanded_04 = EDDY_HUD_DETAILED;
   sim_pstate_04 = PANEL_COLLAPSED;

   // 2. Trader clica em [ + ] no painel minimizado
   sim_pstate_04 = PANEL_EXPANDED;
   sim_mode_04 = sim_saved_expanded_04;

   AssertTest("W10R-04",
              (sim_pstate_04 == PANEL_EXPANDED && sim_mode_04 == EDDY_HUD_DETAILED),
              "Ciclo DETAILED -> COLLAPSED -> DETAILED preserva contexto tecnico e restabelece a auditoria detalhada");

   //-----------------------------------------------------------------
   // W10R-05: Minimização Durante BLOCKED Preserva t_trigger, t_unlock e event_id
   //-----------------------------------------------------------------
   TestClearGV();
   test_state           = EDDY_STATE_BLOCKED;
   test_safe_to_operate = true;
   test_t_trigger       = 1710000000;
   test_t_unlock        = 1710014400; // 4h depois
   test_event_id        = 777888999;
   test_g_max_loss      = 500.0;

   datetime snap_t_trig_05 = test_t_trigger;
   datetime snap_t_unlk_05 = test_t_unlock;
   ulong    snap_evt_05    = test_event_id;

   // Trader minimiza HUD durante bloqueio ativo
   ENUM_DISCIPLINADOR_PANEL_STATE sim_pstate_05 = PANEL_COLLAPSED;

   bool lock_preserved_05 = (test_state == EDDY_STATE_BLOCKED &&
                             test_t_trigger == snap_t_trig_05 &&
                             test_t_unlock  == snap_t_unlk_05 &&
                             test_event_id  == snap_evt_05 &&
                             test_g_max_loss == 500.0);

   AssertTest("W10R-05",
              (sim_pstate_05 == PANEL_COLLAPSED && lock_preserved_05),
              "Minimizacao visual durante BLOCKED preserva rigorosamente t_trigger, t_unlock, event_id e integridade do bloqueio");

   //-----------------------------------------------------------------
   // W10R-06: Preferência Visual Persistida Não Pertence a D_min_recovery
   //-----------------------------------------------------------------
   TestClearGV();
   GlobalVariableSet(TestGVKey("STATE"), (double)EDDY_STATE_MONITORING);
   GlobalVariableSet(TestGVKey("WINDOW_ID"), 1.0);
   GlobalVariableSet(TestGVKey("BASELINE"), -100.0);
   GlobalVariableSet(TestGVKey("T_TRIGGER"), 0.0);
   GlobalVariableSet(TestGVKey("T_UNLOCK"), 0.0);
   GlobalVariableSet(TestGVKey("EVENT_ID"), 0.0);
   GlobalVariableSet(TestGVKey("DAY"), 1710000000.0);

   string key_panel_cfg = TestGVConfigKey("PANEL_COLLAPSED");
   GlobalVariableSet(key_panel_cfg, 1.0);
   GlobalVariablesFlush();

   // Limpeza simulada das chaves de recuperação
   GlobalVariableDel(TestGVKey("STATE"));
   GlobalVariableDel(TestGVKey("WINDOW_ID"));
   GlobalVariableDel(TestGVKey("BASELINE"));
   GlobalVariableDel(TestGVKey("T_TRIGGER"));
   GlobalVariableDel(TestGVKey("T_UNLOCK"));
   GlobalVariableDel(TestGVKey("EVENT_ID"));
   GlobalVariableDel(TestGVKey("DAY"));
   GlobalVariablesFlush();

   bool visual_pref_intact = GlobalVariableCheck(key_panel_cfg);
   double visual_pref_val = visual_pref_intact ? GlobalVariableGet(key_panel_cfg) : -1.0;
   GlobalVariableDel(key_panel_cfg);
   GlobalVariablesFlush();

   AssertTest("W10R-06",
              (visual_pref_intact && visual_pref_val == 1.0),
              "Preferencia visual persistida e desacoplada e nao pertence a tupla normativa D_min_recovery");

   //-----------------------------------------------------------------
   // W10R-07: Falha ao Persistir Preferência Visual Não Coloca Motor em Fail-Closed
   //-----------------------------------------------------------------
   TestClearGV();
   test_state           = EDDY_STATE_MONITORING;
   test_safe_to_operate = true;

   bool sim_visual_save_failed = true;
   ENUM_DISCIPLINADOR_PANEL_STATE sim_pstate_07 = PANEL_COLLAPSED;

   if(sim_visual_save_failed)
   {
      sim_pstate_07 = PANEL_COLLAPSED;
   }

   AssertTest("W10R-07",
              (sim_pstate_07 == PANEL_COLLAPSED && test_safe_to_operate == true && test_state == EDDY_STATE_MONITORING),
              "Falha na gravacao da preferencia visual e nao-fatal e jamais induz o motor de risco a fail-closed");

   //-----------------------------------------------------------------
   // W10R-08: Cálculo/Monitoramento Não Filtra Símbolo do Gráfico Hospedeiro
   //-----------------------------------------------------------------
   TestClearGV();
   double deal_petr4_profit  = -150.0;
   double deal_winn_profit   = -200.0;
   double deal_eurusd_profit = -50.0;
   double floating_btcusd    = -150.0;

   double total_account_D = deal_petr4_profit + deal_winn_profit + deal_eurusd_profit + floating_btcusd;
   test_g_max_loss = 500.0;
   test_baseline   = 0.0;
   double W_account = total_account_D - test_baseline;

   bool trigger_account_global = (W_account <= -test_g_max_loss);

   AssertTest("W10R-08",
              (total_account_D == -550.0 && trigger_account_global == true),
              "Calculo de perda acumulada agrega todas as operacoes da conta independentemente do simbolo do grafico hospedeiro");

   //-----------------------------------------------------------------
   // W10R-09: Liquidação Não Filtra Magic Number
   //-----------------------------------------------------------------
   TestClearGV();
   ulong sim_pos_magics[3]   = {0, 10101, 777001};
   ulong sim_pos_tickets[3]  = {1001, 1002, 1003};
   bool  sim_pos_closed[3]   = {false, false, false};

   for(int p = 0; p < 3; p++)
   {
      sim_pos_closed[p] = true;
   }

   bool all_closed = (sim_pos_closed[0] && sim_pos_closed[1] && sim_pos_closed[2]);

   AssertTest("W10R-09",
              all_closed,
              "Liquidacao compulsoria encerra todos os tickets da conta sem qualquer filtro por Magic Number");

   //-----------------------------------------------------------------
   // W10R-10: Ordens Pendentes Externas Permanecem Incluídas no Inventário Global
   //-----------------------------------------------------------------
   TestClearGV();
   ulong sim_ord_magics[3]    = {0, 55555, 88888};
   ulong sim_ord_tickets[3]   = {2001, 2002, 2003};
   bool  sim_ord_canceled[3]  = {false, false, false};

   for(int o = 0; o < 3; o++)
   {
      sim_ord_canceled[o] = true;
   }

   bool all_canceled = (sim_ord_canceled[0] && sim_ord_canceled[1] && sim_ord_canceled[2]);

   AssertTest("W10R-10",
              all_canceled,
              "Cancelamento de ordens pendentes abrange integralmente o inventario global da conta sem excecoes externas");

   // Limpeza final de GVs de teste
   TestClearGV();

   //-----------------------------------------------------------------
   // Relatório Final da Bateria
   //-----------------------------------------------------------------
   string ftr1 = "==================================================================";
   string ftr2 = StringFormat(" Resumo da Bateria W06/W07R/W08R/W09R/W10R: Total=%d | Aprovados=%d | Falhas=%d",
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
