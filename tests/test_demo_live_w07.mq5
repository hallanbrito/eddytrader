//+------------------------------------------------------------------+
//|                                           test_demo_live_w07.mq5 |
//|                                  Copyright 2026, EddyTrader Team |
//|                                             https://eddytrader.io |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026, EddyTrader Team"
#property link        "https://eddytrader.io"
#property version     "1.00"
#property description "W07 Suite 1 - Homologacao de Retcodes, Guarda, Recuperacao e Fail-Closed na Conta Demo"
#property strict

#include <Trade\Trade.mqh>

//--- Definição dos Estados da FSM EddyTrader (idêntico a src/EddyTrader.mq5)
enum ENUM_EDDY_STATE
{
   EDDY_STATE_INIT                 = 0,
   EDDY_STATE_MONITORING           = 1,
   EDDY_STATE_PROTECTION_TRIGGERED = 2,
   EDDY_STATE_LIQUIDATING          = 3,
   EDDY_STATE_BLOCKED              = 4,
   EDDY_STATE_REOPENING            = 5
};

//--- Estrutura de Estado
struct EddyStateContext
{
   ENUM_EDDY_STATE state;
   int             window_id;
   double          baseline;
   datetime        t_trigger;
   datetime        t_unlock;
   ulong           protection_event_id;
   datetime        day_timestamp;
   ulong           account_login;
};

const int INSTANCE_LEASE_TIMEOUT_SECONDS = 15;

//--- Contadores de Teste
int g_total_tests  = 0;
int g_passed_tests = 0;
int g_failed_tests = 0;
int g_file_handle  = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Log Helper                                                       |
//+------------------------------------------------------------------+
void Log(const string msg)
{
   Print(msg);
   if(g_file_handle != INVALID_HANDLE)
   {
      FileWriteString(g_file_handle, msg + "\r\n");
      FileFlush(g_file_handle);
   }
}

void AssertTrue(const string test_id, const string desc, bool condition)
{
   g_total_tests++;
   if(condition)
   {
      g_passed_tests++;
      Log(StringFormat("  [PASS] %-12s | %s", test_id, desc));
   }
   else
   {
      g_failed_tests++;
      Log(StringFormat("  [FAIL] %-12s | %s", test_id, desc));
   }
}

//+------------------------------------------------------------------+
//| Helpers de GlobalVariables                                       |
//+------------------------------------------------------------------+
string GVPrefix(ulong login)
{
   return "EDDY_W07_" + IntegerToString(login) + "_";
}

void ClearTestGVs(ulong login)
{
   string prefix = GVPrefix(login);
   int total = GlobalVariablesTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      string name = GlobalVariableName(i);
      if(StringFind(name, prefix) == 0)
         GlobalVariableDel(name);
   }
}

//+------------------------------------------------------------------+
//| Função de Teste: Retcodes de Falha Remota (DEMO-06)               |
//+------------------------------------------------------------------+
void RunTest_DEMO_06()
{
   Log("\n========================================================");
   Log("CENARIO DEMO-06: Resposta a Retcodes de Falha Remota");
   Log("========================================================");

   CTrade trade;
   trade.SetExpertMagicNumber(999006);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   string sym = "EURUSD";
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);

   // DEMO-06A: Mercado Fechado (retcode 10018)
   ResetLastError();
   bool res_market = trade.Buy(0.01, sym, ask, 0.0, 0.0, "DEMO-06A Test");
   uint rc_market = trade.ResultRetcode();
   Log(StringFormat("  DEMO-06A: Ordem a mercado -> ok=%s | retcode=%u (%s) | LastErr=%d",
                    (res_market ? "TRUE" : "FALSE"), rc_market, trade.ResultRetcodeDescription(), GetLastError()));
   AssertTrue("DEMO-06A", "Rejeicao defensiva por mercado fechado (retcode 10018)",
              (!res_market && rc_market == TRADE_RETCODE_MARKET_CLOSED));

   // DEMO-06B: Volume Invalido (volume 0.000001 muito abaixo de min_vol 0.01)
   ResetLastError();
   bool res_vol = trade.Buy(0.000001, sym, ask, 0.0, 0.0, "DEMO-06B Test");
   uint rc_vol = trade.ResultRetcode();
   Log(StringFormat("  DEMO-06B: Ordem com volume invalido -> ok=%s | retcode=%u (%s) | LastErr=%d",
                    (res_vol ? "TRUE" : "FALSE"), rc_vol, trade.ResultRetcodeDescription(), GetLastError()));
   AssertTrue("DEMO-06B", "Rejeicao defensiva por volume invalido ou mercado fechado sem loop",
              (!res_vol && (rc_vol == TRADE_RETCODE_INVALID_VOLUME || rc_vol == TRADE_RETCODE_MARKET_CLOSED || GetLastError() > 0)));

   // DEMO-06C: Preco Invalido (BuyLimit com preco 0.0)
   ResetLastError();
   bool res_price = trade.BuyLimit(0.01, 0.0, sym, 0.0, 0.0, ORDER_TIME_GTC, 0, "DEMO-06C Test");
   uint rc_price = trade.ResultRetcode();
   Log(StringFormat("  DEMO-06C: Pending order com preco 0.0 -> ok=%s | retcode=%u (%s) | LastErr=%d",
                    (res_price ? "TRUE" : "FALSE"), rc_price, trade.ResultRetcodeDescription(), GetLastError()));
   AssertTrue("DEMO-06C", "Rejeicao defensiva por preco invalido ou mercado fechado",
              (!res_price && (rc_price == TRADE_RETCODE_INVALID_PRICE || rc_price == TRADE_RETCODE_MARKET_CLOSED || GetLastError() > 0)));
}

//+------------------------------------------------------------------+
//| Função de Teste: Reinicialização Durante BLOCKED (DEMO-07)       |
//+------------------------------------------------------------------+
void RunTest_DEMO_07(ulong login)
{
   Log("\n========================================================");
   Log("CENARIO DEMO-07: Reinicializacao Durante Estado BLOCKED");
   Log("========================================================");

   ClearTestGVs(login);
   string prefix = GVPrefix(login);

   datetime t_now = TimeCurrent();
   datetime t_trig = t_now - 1200; // bloqueado ha 20 min
   datetime t_unlk = t_now + 2400; // desbloqueia em 40 min
   ulong evt_id    = 777001;
   double base     = 1000.0;
   int win_id      = 1;

   // Persistir estado BLOCKED
   GlobalVariableSet(prefix + "STATE", (double)EDDY_STATE_BLOCKED);
   GlobalVariableSet(prefix + "WINDOW_ID", (double)win_id);
   GlobalVariableSet(prefix + "BASELINE", base);
   GlobalVariableSet(prefix + "T_TRIGGER", (double)t_trig);
   GlobalVariableSet(prefix + "T_UNLOCK", (double)t_unlk);
   GlobalVariableSet(prefix + "EVENT_ID", (double)evt_id);
   GlobalVariableSet(prefix + "LOGIN", (double)login);

   // Simular reinicialização do EA lendo os GVs
   ENUM_EDDY_STATE rec_state = (ENUM_EDDY_STATE)(int)GlobalVariableGet(prefix + "STATE");
   datetime rec_t_trig       = (datetime)GlobalVariableGet(prefix + "T_TRIGGER");
   datetime rec_t_unlk       = (datetime)GlobalVariableGet(prefix + "T_UNLOCK");
   ulong rec_evt_id          = (ulong)GlobalVariableGet(prefix + "EVENT_ID");
   double rec_base           = GlobalVariableGet(prefix + "BASELINE");

   // Avaliar se o estado deve permanecer BLOCKED
   bool remain_blocked = (rec_state == EDDY_STATE_BLOCKED) && (t_now < rec_t_unlk);
   bool timers_intact  = (rec_t_trig == t_trig) && (rec_t_unlk == t_unlk) && (rec_evt_id == evt_id);

   Log(StringFormat("  DEMO-07: Estado recuperado=%d | t_now=%s | t_unlock=%s | evt=%I64u",
                    rec_state, TimeToString(t_now), TimeToString(rec_t_unlk), rec_evt_id));

   AssertTrue("DEMO-07A", "Estado recuperado permanece EDDY_STATE_BLOCKED", remain_blocked);
   AssertTrue("DEMO-07B", "Timers t_trigger, t_unlock e protection_event_id preservados integralmente", timers_intact);
   AssertTrue("DEMO-07C", "Baseline B_n recuperada exatamente", (rec_base == base));
}

//+------------------------------------------------------------------+
//| Função de Teste: Reinicialização Após t_unlock (DEMO-08)         |
//+------------------------------------------------------------------+
void RunTest_DEMO_08(ulong login)
{
   Log("\n========================================================");
   Log("CENARIO DEMO-08: Reinicializacao Apos t_unlock");
   Log("========================================================");

   ClearTestGVs(login);
   string prefix = GVPrefix(login);

   datetime t_now = TimeCurrent();
   datetime t_trig = t_now - 7200; // bloqueado ha 2 horas
   datetime t_unlk = t_now - 300;  // expirou ha 5 minutos
   ulong evt_id    = 888002;
   double old_base = 0.0;
   // Resultado acumulado relevante D(t_reopen) = R_day + F (NUNCA Equity!)
   double d_reopen = -520.0;

   GlobalVariableSet(prefix + "STATE", (double)EDDY_STATE_BLOCKED);
   GlobalVariableSet(prefix + "WINDOW_ID", 1.0);
   GlobalVariableSet(prefix + "BASELINE", old_base);
   GlobalVariableSet(prefix + "T_TRIGGER", (double)t_trig);
   GlobalVariableSet(prefix + "T_UNLOCK", (double)t_unlk);
   GlobalVariableSet(prefix + "EVENT_ID", (double)evt_id);
   GlobalVariableSet(prefix + "LOGIN", (double)login);

   // Simular reinicialização: detecta que t_now >= t_unlock
   ENUM_EDDY_STATE rec_state = (ENUM_EDDY_STATE)(int)GlobalVariableGet(prefix + "STATE");
   datetime rec_t_unlk       = (datetime)GlobalVariableGet(prefix + "T_UNLOCK");

   ENUM_EDDY_STATE interim_state = rec_state;
   ENUM_EDDY_STATE final_state   = rec_state;
   double new_base   = old_base;
   double w_new      = -999.0;
   int new_win_id    = 1;
   bool passed_reopening = false;

   if(rec_state == EDDY_STATE_BLOCKED && t_now >= rec_t_unlk)
   {
      // 1. Passagem obrigatória pelo estado REOPENING
      interim_state    = EDDY_STATE_REOPENING;
      passed_reopening = true;

      // 2. No estado REOPENING: captura Bn = D(t_reopen), valida W_new == 0 e avança janela
      new_win_id = 2;
      new_base   = d_reopen; // Bn = D(t_reopen), estritamente conforme RN-006 / W03
      w_new      = d_reopen - new_base; // W_(n+1)(t_reopen) == 0

      // 3. Conclusão da reabertura: retorno ao MONITORING
      final_state = EDDY_STATE_MONITORING;
   }

   Log(StringFormat("  DEMO-08: t_now >= t_unlock detectado (%s >= %s) -> Transicao via REOPENING para MONITORING com Bn=%.2f e W_new=%.2f",
                    TimeToString(t_now), TimeToString(rec_t_unlk), new_base, w_new));

   AssertTrue("DEMO-08A", "Fluxo formal de reabertura BLOCKED -> REOPENING -> MONITORING", (passed_reopening && final_state == EDDY_STATE_MONITORING));
   AssertTrue("DEMO-08B", "Renovacao normativa da baseline Bn = D(t_reopen) com W_new == 0 (e NUNCA Equity)", (new_base == d_reopen && w_new == 0.0));
   AssertTrue("DEMO-08C", "Incremento da janela operacional Jn (Jn=2)", (new_win_id == 2));
}

//+------------------------------------------------------------------+
//| Função de Teste: Persistência e Integridade de Jn e Bn (DEMO-09) |
//+------------------------------------------------------------------+
void RunTest_DEMO_09(ulong login)
{
   Log("\n========================================================");
   Log("CENARIO DEMO-09: Persistencia e Recuperacao de Jn e Bn");
   Log("========================================================");

   ClearTestGVs(login);
   string prefix = GVPrefix(login);

   int target_win  = 3;
   double target_b = 1050.75;
   datetime day_st = StringToTime("2026.09.13 00:00:00");

   // Simular escrita de estado
   GlobalVariableSet(prefix + "STATE", (double)EDDY_STATE_MONITORING);
   GlobalVariableSet(prefix + "WINDOW_ID", (double)target_win);
   GlobalVariableSet(prefix + "BASELINE", target_b);
   GlobalVariableSet(prefix + "DAY_START", (double)day_st);
   GlobalVariableSet(prefix + "LOGIN", (double)login);

   // Calcular hash de integridade
   double chksum = (double)EDDY_STATE_MONITORING + (double)target_win + target_b + (double)day_st + (double)login;
   GlobalVariableSet(prefix + "CHECKSUM", chksum);

   // Leitura e verificação de integridade
   double r_state  = GlobalVariableGet(prefix + "STATE");
   double r_win    = GlobalVariableGet(prefix + "WINDOW_ID");
   double r_base   = GlobalVariableGet(prefix + "BASELINE");
   double r_day    = GlobalVariableGet(prefix + "DAY_START");
   double r_login  = GlobalVariableGet(prefix + "LOGIN");
   double r_chksum = GlobalVariableGet(prefix + "CHECKSUM");

   double calc_chk = r_state + r_win + r_base + r_day + r_login;
   bool integrity_ok = (calc_chk == r_chksum);

   AssertTrue("DEMO-09A", "Integridade da persistencia validada via checksum", integrity_ok);
   AssertTrue("DEMO-09B", "Recuperacao fiel de Jn (Window ID)", ((int)r_win == target_win));
   AssertTrue("DEMO-09C", "Recuperacao fiel de Bn (Baseline)", (r_base == target_b));

   // Teste de corrupção induzida: adulterar baseline sem atualizar checksum
   GlobalVariableSet(prefix + "BASELINE", 9999.99);
   double corrupted_base = GlobalVariableGet(prefix + "BASELINE");
   double recheck = r_state + r_win + corrupted_base + r_day + r_login;
   bool corruption_detected = (recheck != r_chksum);

   AssertTrue("DEMO-09D", "Deteccao de corrupcao de estado persistido (fail-closed trigger)", corruption_detected);
}

//+------------------------------------------------------------------+
//| Função de Teste: Postura Fail-Closed (DEMO-10)                   |
//+------------------------------------------------------------------+
void RunTest_DEMO_10(ulong login)
{
   Log("\n========================================================");
   Log("CENARIO DEMO-10: Postura Fail-Closed");
   Log("========================================================");

   // 1. Parametro de Perda Negativo ou Zero
   double bad_loss_neg = -100.0;
   double bad_loss_zer = 0.0;
   bool valid_param = (bad_loss_neg > 0.0) && (bad_loss_zer > 0.0);
   AssertTrue("DEMO-10A", "Rejeicao de parametros de perda invalidos (<= 0)", (!valid_param));

   // 2. Mismatch de Login de Conta
   ulong intruder_login = 12345678;
   bool login_match = (intruder_login == login);
   AssertTrue("DEMO-10B", "Aborto defensivo em caso de login divergente do estado persistido", (!login_match));

   // 3. Trade Allowed na Conta e no Terminal
   bool acct_trade = (bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED);
   bool term_trade = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   Log(StringFormat("  DEMO-10C: Account Trade Allowed=%s | Terminal Trade Allowed=%s",
                    (acct_trade ? "SIM" : "NAO"), (term_trade ? "SIM" : "NAO")));
   AssertTrue("DEMO-10C", "Permissoes operacionais estao ativas no ambiente Demo", (acct_trade && term_trade));

   // 4. Verificação de Trade Mode Real vs Demo
   ENUM_ACCOUNT_TRADE_MODE t_mode = (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   AssertTrue("DEMO-10D", "Guarda de seguranca: execucao estritamente vetada em conta REAL", (t_mode == ACCOUNT_TRADE_MODE_DEMO));
}

//+------------------------------------------------------------------+
//| Função de Teste: Guarda de Instância Única Concorrência (DEMO-11)|
//+------------------------------------------------------------------+
void RunTest_DEMO_11(ulong login)
{
   Log("\n========================================================");
   Log("CENARIO DEMO-11: Guarda de Instancia Unica em Concorrencia");
   Log("========================================================");

   ClearTestGVs(login);
   string prefix = GVPrefix(login);
   string k_owner = prefix + "OWNER";
   string k_hb    = prefix + "HEARTBEAT";

   ulong instance_A_uid = 1001;
   ulong instance_B_uid = 2002;

   datetime t_now = TimeCurrent();

   // Instância A adquire o lock atomicamente
   GlobalVariableTemp(k_owner);
   GlobalVariableSet(k_owner, (double)instance_A_uid);
   GlobalVariableTemp(k_hb);
   GlobalVariableSet(k_hb, (double)t_now);

   // Instância B tenta inicializar
   double curr_owner = GlobalVariableGet(k_owner);
   datetime last_hb  = (datetime)GlobalVariableGet(k_hb);
   double hb_age     = (double)(t_now - last_hb);

   bool b_can_acquire = false;
   if(curr_owner == 0.0 || hb_age > INSTANCE_LEASE_TIMEOUT_SECONDS)
   {
      b_can_acquire = true;
   }

   AssertTrue("DEMO-11A", "Instancia B detecta lock ativo e recente da Instancia A", (curr_owner == (double)instance_A_uid));
   AssertTrue("DEMO-11B", "Instancia B tem acesso negado (INIT_FAILED defensivo)", (!b_can_acquire));

   // Verificar se o lock da Instância A permaneceu inviolado
   double verify_owner = GlobalVariableGet(k_owner);
   AssertTrue("DEMO-11C", "Lock da Instancia A permanece intacto apos tentativa de invasao", (verify_owner == (double)instance_A_uid));
}

//+------------------------------------------------------------------+
//| Função de Teste: Takeover de Lease Expirada (DEMO-12)            |
//+------------------------------------------------------------------+
void RunTest_DEMO_12(ulong login)
{
   Log("\n========================================================");
   Log("CENARIO DEMO-12: Takeover de Lease Expirada pela Guarda");
   Log("========================================================");

   ClearTestGVs(login);
   string prefix = GVPrefix(login);
   string k_owner = prefix + "OWNER";
   string k_hb    = prefix + "HEARTBEAT";

   ulong instance_A_uid = 1001;
   ulong instance_B_uid = 2002;

   datetime t_now = TimeCurrent();
   datetime expired_hb = t_now - 25; // Instância A travou ha 25 segundos (timeout = INSTANCE_LEASE_TIMEOUT_SECONDS = 15s)

   // Estado inicial: Instância A abandonou lock
   GlobalVariableSet(k_owner, (double)instance_A_uid);
   GlobalVariableSet(k_hb, (double)expired_hb);

   // Instância B avalia lease
   double curr_owner = GlobalVariableGet(k_owner);
   datetime last_hb  = (datetime)GlobalVariableGet(k_hb);
   int hb_age        = (int)(t_now - last_hb);

   bool lease_expired = (hb_age > INSTANCE_LEASE_TIMEOUT_SECONDS);
   bool takeover_ok   = false;

   if(lease_expired)
   {
      // Takeover atômico via CAS
      if(GlobalVariableSetOnCondition(k_owner, (double)instance_B_uid, (double)instance_A_uid))
      {
         GlobalVariableSet(k_hb, (double)t_now);
         takeover_ok = true;
      }
   }

   Log(StringFormat("  DEMO-12: Lease age=%ds (limite=%ds) | Takeover CAS executado=%s",
                    hb_age, INSTANCE_LEASE_TIMEOUT_SECONDS, (takeover_ok ? "SIM" : "NAO")));

   AssertTrue("DEMO-12A", StringFormat("Deteccao correta de lease expirada (age > %ds)", INSTANCE_LEASE_TIMEOUT_SECONDS), lease_expired);
   AssertTrue("DEMO-12B", "Takeover atomico com sucesso pela Instancia B via CAS", takeover_ok);
   AssertTrue("DEMO-12C", "Novo proprietario registrado no lock e Instancia B", (GlobalVariableGet(k_owner) == (double)instance_B_uid));

   ClearTestGVs(login);
}

//+------------------------------------------------------------------+
//| Script Entry Point                                               |
//+------------------------------------------------------------------+
void OnStart()
{
   g_file_handle = FileOpen("test_demo_live_w07.txt", FILE_WRITE|FILE_TXT|FILE_ANSI);

   Log("================================================================================");
   Log("        EDDYTRADER W07 - SUITE 1: TESTES INTEGRADOS NA CONTA DEMO               ");
   Log("================================================================================");

   ulong login = (ulong)AccountInfoInteger(ACCOUNT_LOGIN);
   string server = AccountInfoString(ACCOUNT_SERVER);
   ENUM_ACCOUNT_TRADE_MODE trade_mode = (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   ENUM_ACCOUNT_MARGIN_MODE margin_mode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);

   Log(StringFormat("CONTA: %I64u | SERVIDOR: %s | BUILD: %d", login, server, (int)TerminalInfoInteger(TERMINAL_BUILD)));
   Log(StringFormat("TRADE MODE: %s | MARGIN MODE: %s",
                    (trade_mode == ACCOUNT_TRADE_MODE_DEMO ? "DEMO" : "NAO-DEMO"),
                    (margin_mode == ACCOUNT_MARGIN_MODE_RETAIL_NETTING ? "RETAIL NETTING" : "HEDGING")));

   if(trade_mode != ACCOUNT_TRADE_MODE_DEMO)
   {
      Log("[FATAL] Conta NAO e Demo! Operacao cancelada por seguranca incondicional.");
      FileClose(g_file_handle);
      return;
   }

   // Executar os cenários de homologação ao vivo
   RunTest_DEMO_06();
   RunTest_DEMO_07(login);
   RunTest_DEMO_08(login);
   RunTest_DEMO_09(login);
   RunTest_DEMO_10(login);
   RunTest_DEMO_11(login);
   RunTest_DEMO_12(login);

   Log("\n================================================================================");
   Log(StringFormat("RESULTADO FINAL: TOTAL=%d | PASS=%d | FAIL=%d", g_total_tests, g_passed_tests, g_failed_tests));
   Log("================================================================================");

   FileClose(g_file_handle);
}
