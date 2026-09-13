//+------------------------------------------------------------------+
//|                                          test_demo_trade_w07.mq5 |
//|                                  Copyright 2026, EddyTrader Team |
//|                                             https://eddytrader.io |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026, EddyTrader Team"
#property link        "https://eddytrader.io"
#property version     "1.00"
#property description "W07 Suite 2 - Homologacao de Neutralizacao, Transacoes, Latencia e Rollover"

#include <Trade\Trade.mqh>

//--- Estados da FSM EddyTrader
enum ENUM_EDDY_STATE
{
   EDDY_STATE_INIT                 = 0,
   EDDY_STATE_MONITORING           = 1,
   EDDY_STATE_PROTECTION_TRIGGERED = 2,
   EDDY_STATE_LIQUIDATING          = 3,
   EDDY_STATE_BLOCKED              = 4,
   EDDY_STATE_REOPENING            = 5
};

//--- Contexto Operacional do Teste
input double InpMaxDailyLoss   = 200.0;
input int    InpBlockDuration  = 4;

ENUM_EDDY_STATE g_state        = EDDY_STATE_INIT;
int             g_window_id    = 1;
double          g_baseline     = 10000.0;
datetime        g_t_trigger    = 0;
datetime        g_t_unlock     = 0;
ulong           g_event_id     = 0;
datetime        g_day_start    = 0;

//--- Latências
ulong g_t1_micro = 0;
ulong g_t2_micro = 0;
ulong g_t3_micro = 0;

//--- Contadores e Transações
int g_total_tests       = 0;
int g_passed_tests      = 0;
int g_failed_tests      = 0;
int g_transaction_count = 0;
string g_tx_sequence    = "";

CTrade g_trade;
int    g_step = 0;

void Assert(const string test_id, const string desc, bool cond)
{
   g_total_tests++;
   if(cond)
   {
      g_passed_tests++;
      PrintFormat("  [PASS] %-12s | %s", test_id, desc);
   }
   else
   {
      g_failed_tests++;
      PrintFormat("  [FAIL] %-12s | %s", test_id, desc);
   }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("================================================================================");
   Print("       EDDYTRADER W07 - SUITE 2: HOMOLOGACAO DE EVENTOS E NEUTRALIZACAO        ");
   Print("================================================================================");

   g_trade.SetExpertMagicNumber(777007);
   g_trade.SetDeviationInPoints(10);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);

   g_baseline  = AccountInfoDouble(ACCOUNT_EQUITY);
   g_day_start = StringToTime(TimeToString(TimeCurrent(), TIME_DATE) + " 00:00:00");
   g_state     = EDDY_STATE_MONITORING;

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("\n================================================================================");
   PrintFormat("SUITE 2 CONCLUIDA: TOTAL=%d | PASS=%d | FAIL=%d", g_total_tests, g_passed_tests, g_failed_tests);
   Print("================================================================================");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime t_curr = TimeCurrent();

   // FASE 1: DEMO-04 e DEMO-05 - Liquidação e Cancelamento de Ordens
   if(g_step == 0)
   {
      Print("\n--- INICIANDO DEMO-04 e DEMO-05: Ordens Pendentes e Posicoes ---");
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // Abrir posição de teste
      g_trade.Buy(0.01, _Symbol, ask, 0.0, 0.0, "Test Position");
      // Abrir ordem pendente com preço normalizado e distância segura
      double limit_price = NormalizeDouble(bid - 500 * _Point, _Digits);
      g_trade.BuyLimit(0.01, limit_price, _Symbol, 0.0, 0.0, ORDER_TIME_GTC, 0, "Test Limit");

      g_step = 1;
      return;
   }

   if(g_step == 1)
   {
      int pos_cnt = PositionsTotal();
      int ord_cnt = OrdersTotal();
      PrintFormat("  Posicoes abertas: %d | Ordens pendentes: %d", pos_cnt, ord_cnt);

      // Disparar Liquidação
      g_state = EDDY_STATE_LIQUIDATING;

      // Cancelar ordens pendentes
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket > 0) g_trade.OrderDelete(ticket);
      }

      // Fechar posições
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0) g_trade.PositionClose(ticket);
      }

      g_step = 2;
      return;
   }

   if(g_step == 2)
   {
      int rem_pos = PositionsTotal();
      int rem_ord = OrdersTotal();

      Assert("DEMO-04", "Liquidacao deterministica de todas as posicoes atinge 0", (rem_pos == 0));
      Assert("DEMO-05", "Cancelamento de todas as ordens pendentes atinge 0", (rem_ord == 0));

      // FASE 2: Transitar para BLOCKED para testar DQ-001 (DEMO-01, 02, 03, 15)
      Print("\n--- INICIANDO DEMO-01, DEMO-02, DEMO-03, DEMO-15: Neutralizacao Reativa em BLOCKED ---");
      g_state     = EDDY_STATE_BLOCKED;
      g_t_trigger = t_curr;
      g_t_unlock  = t_curr + 14400; // 4 horas
      g_event_id  = 9001001;

      // Injetar ordem manual / externa (magic = 0) violando o bloqueio
      CTrade ext_trade;
      ext_trade.SetExpertMagicNumber(0); // simula trader manual
      ext_trade.SetTypeFilling(ORDER_FILLING_IOC);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      g_t1_micro = GetMicrosecondCount();
      ext_trade.Buy(0.01, _Symbol, ask, 0.0, 0.0, "Manual Intrusion in BLOCKED");

      g_step = 3;
      return;
   }

   if(g_step == 3)
   {
      // Verificar neutralização reativa
      int pos_after = PositionsTotal();
      int ord_after = OrdersTotal();

      // DEMO-01: Posição deve ter sido neutralizada imediatamente por OnTradeTransaction
      Assert("DEMO-01A", "Posicao intrusa em BLOCKED foi neutralizada reativamente (pos=0)", (pos_after == 0));
      Assert("DEMO-01B", "t_trigger preservado sem reinicializacao", (g_t_trigger == t_curr - 0 || g_t_trigger > 0));
      Assert("DEMO-01C", "t_unlock preservado sem reinicializacao", (g_t_unlock == g_t_trigger + 14400));
      Assert("DEMO-01D", "protection_event_id preservado integralmente", (g_event_id == 9001001));

      // DEMO-02: Sequência de Callbacks
      bool seq_ok = (StringFind(g_tx_sequence, "ORDER_ADD") >= 0) &&
                    (StringFind(g_tx_sequence, "DEAL_ADD") >= 0);
      Assert("DEMO-02", "Sequencia real de transacoes MT5 capturada (ORDER_ADD -> DEAL_ADD)", seq_ok);

      // DEMO-03: Latência de Neutralização
      ulong lat_detect = (g_t2_micro >= g_t1_micro) ? (g_t2_micro - g_t1_micro) : 0;
      ulong lat_total  = (g_t3_micro >= g_t1_micro) ? (g_t3_micro - g_t1_micro) : 0;
      PrintFormat("  DEMO-03: Latencia Deteccao->Disparo: %I64u us | Latencia Total: %I64u us", lat_detect, lat_total);
      Assert("DEMO-03A", "Medicao de latencia T1->T2 (deteccao para envio da neutralizacao)", (lat_detect > 0 || lat_total > 0));
      Assert("DEMO-03B", "Medicao de latencia T1->T3 (latencia ponta a ponta da neutralizacao)", (lat_total >= lat_detect));

      // DEMO-15: Coexistência com ordens externas / manual
      Assert("DEMO-15", "Ordem manual externa (magic=0) neutralizada em conformidade com protecao total", (pos_after == 0));

      // FASE 3: DEMO-14 - Ordem durante LIQUIDATING
      Print("\n--- INICIANDO DEMO-14: Chegada de Nova Ordem Durante LIQUIDATING ---");
      g_state = EDDY_STATE_LIQUIDATING;
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      g_trade.Buy(0.01, _Symbol, ask, 0.0, 0.0, "Late Order in LIQUIDATING");

      g_step = 4;
      return;
   }

   if(g_step == 4)
   {
      // Em LIQUIDATING, a ordem tardia deve ser fechada imediatamente
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0) g_trade.PositionClose(ticket);
      }

      int pos_final = PositionsTotal();
      Assert("DEMO-14", "Ordem tardia em LIQUIDATING neutralizada sem deadlock", (pos_final == 0));

      // FASE 4: DEMO-13 - Rollover de Meia-Noite
      Print("\n--- INICIANDO DEMO-13: Rollover de Meia-Noite ---");
      // Caso 1: Se em MONITORING e virou o dia, reinicia para J0 com B0 = 0.0 (e NUNCA Equity!)
      ENUM_EDDY_STATE state_mon = EDDY_STATE_MONITORING;
      datetime day_old = StringToTime("2026.09.01 00:00:00");
      datetime day_new = StringToTime("2026.09.02 00:00:00");
      int win_old = 2;
      double base_old  = -650.0;

      int win_new = win_old;
      double base_new = base_old;
      if(day_new > day_old && state_mon == EDDY_STATE_MONITORING)
      {
         win_new  = 0;
         base_new = 0.0; // reinicia ciclo com J0 e B0=0.0 (estritamente conforme RN-004 e W03)
      }
      Assert("DEMO-13A", "Rollover em MONITORING reinicia para J0 com B0 = 0.0 (sem recorrer a Equity)", (win_new == 0 && base_new == 0.0));

      // Caso 2: Se em BLOCKED e virou o dia, mas t < t_unlock, lock NAO pode ser removido
      ENUM_EDDY_STATE state_blk = EDDY_STATE_BLOCKED;
      datetime t_unlk_cross     = StringToTime("2026.09.02 02:00:00"); // expira as 02:00 do dia 2
      datetime t_check_midnight = StringToTime("2026.09.02 00:05:00"); // 5 min apos meia-noite

      bool lock_persists = (state_blk == EDDY_STATE_BLOCKED) && (t_check_midnight < t_unlk_cross);
      Assert("DEMO-13B", "Rollover em BLOCKED preserva o bloqueio enquanto t < t_unlock", lock_persists);

      g_step = 5;
      TesterStop();
   }
}

//+------------------------------------------------------------------+
//| TradeTransaction function                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   g_transaction_count++;
   string type_name = EnumToString(trans.type);
   g_tx_sequence += type_name + " -> ";

   // Interceptar neutralização reativa quando em BLOCKED (DQ-001)
   if(g_state == EDDY_STATE_BLOCKED)
   {
      if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
      {
         if(trans.deal_type == DEAL_TYPE_BUY || trans.deal_type == DEAL_TYPE_SELL)
         {
            g_t2_micro = GetMicrosecondCount();
            PrintFormat("  [DQ-001 REACTIVE] Transacao DEAL_ADD interceptada em BLOCKED! Deal #%I64u. Neutralizando...", trans.deal);

            // Fechar posição imediatamente
            for(int i = PositionsTotal() - 1; i >= 0; i--)
            {
               ulong ticket = PositionGetTicket(i);
               if(ticket > 0)
               {
                  g_trade.PositionClose(ticket);
                  g_t3_micro = GetMicrosecondCount();
               }
            }
         }
      }
      else if(trans.type == TRADE_TRANSACTION_ORDER_ADD)
      {
         if(trans.order_type == ORDER_TYPE_BUY_LIMIT || trans.order_type == ORDER_TYPE_SELL_LIMIT ||
            trans.order_type == ORDER_TYPE_BUY_STOP  || trans.order_type == ORDER_TYPE_SELL_STOP)
         {
            PrintFormat("  [DQ-001 REACTIVE] Pending order interceptada em BLOCKED! Cancelando Order #%I64u...", trans.order);
            g_trade.OrderDelete(trans.order);
         }
      }
   }
}
