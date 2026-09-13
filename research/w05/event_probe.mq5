//+------------------------------------------------------------------+
//|                                                  event_probe.mq5 |
//|                                      W05 EXPERIMENTAL SPIKE      |
//|                                      NOT PRODUCTION CODE         |
//+------------------------------------------------------------------+
#property copyright "EddyTrader W05 Spike"
#property link      "https://github.com/eddytrader"
#property version   "1.00"

#include <Trade\Trade.mqh>

input bool InpSimulateBlockedState = false; // Simular estado BLOCKED (neutralizar novas operacoes)
input bool InpLogAllTransactions   = true;  // Registrar todas as transacoes no Journal

CTrade ExtTrade;
ulong  ExtLastDealTicket = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== [W05 EXPERIMENTAL SPIKE] EVENT PROBE INITIALIZED ===");
   PrintFormat("InpSimulateBlockedState: %s", InpSimulateBlockedState ? "TRUE" : "FALSE");
   PrintFormat("Terminal Connected: %s", TerminalInfoInteger(TERMINAL_CONNECTED) ? "YES" : "NO");
   PrintFormat("Trade Allowed: %s", MQLInfoInteger(MQL_TRADE_ALLOWED) ? "YES" : "NO");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   PrintFormat("=== [W05 EXPERIMENTAL SPIKE] EVENT PROBE DEINITIALIZED (Reason: %d) ===", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // OnTick pulsa apenas para o ativo do gráfico
}

//+------------------------------------------------------------------+
//| Trade transaction event handler                                  |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   ulong t_recv_us = GetMicrosecondCount();
   datetime t_srv = TimeTradeServer();

   if(InpLogAllTransactions)
   {
      PrintFormat("[OnTradeTransaction] SrvTime: %s | Type: %s (%d) | Order: %I64u | Deal: %I64u | PosID: %I64u | Sym: %s",
                  TimeToString(t_srv, TIME_DATE|TIME_SECONDS),
                  EnumToString(trans.type),
                  (int)trans.type,
                  trans.order,
                  trans.deal,
                  trans.position,
                  trans.symbol);

      if(trans.type == TRADE_TRANSACTION_REQUEST)
      {
         PrintFormat("  -> Request: Action: %s | Retcode: %u (%s)",
                     EnumToString(request.action),
                     result.retcode,
                     result.comment);
      }
   }

   // Analise de nova posicao ou ordem durante estado BLOCKED (TECH-02)
   if(InpSimulateBlockedState)
   {
      // Caso 1: Negocio executado gerando/alterando posicao
      if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal != 0 && trans.deal != ExtLastDealTicket)
      {
         ExtLastDealTicket = trans.deal;
         PrintFormat("[TECH-02 NEUTRALIZATION] Nova negociacao detectada durante BLOQUEIO! Deal: %I64u | Pos: %I64u | Simbolo: %s",
                     trans.deal, trans.position, trans.symbol);

         ulong t_action_start = GetMicrosecondCount();
         bool closed = false;
         if(trans.position > 0)
         {
            closed = ExtTrade.PositionClose(trans.position);
         }
         else if(trans.symbol != "")
         {
            closed = ExtTrade.PositionClose(trans.symbol);
         }
         ulong t_action_end = GetMicrosecondCount();

         PrintFormat("[TECH-02 NEUTRALIZATION RESULT] Retcode: %u (%s) | ReqAccepted: %s | Latencia Neutralizacao: %I64u us",
                     ExtTrade.ResultRetcode(),
                     ExtTrade.ResultRetcodeDescription(),
                     closed ? "TRUE" : "FALSE",
                     (t_action_end - t_action_start));
      }

      // Caso 2: Ordem pendente criada durante bloqueio
      if(trans.type == TRADE_TRANSACTION_ORDER_ADD && trans.order > 0)
      {
         PrintFormat("[TECH-02 NEUTRALIZATION] Nova ordem pendente detectada durante BLOQUEIO! Order: %I64u", trans.order);
         ulong t_action_start = GetMicrosecondCount();
         bool deleted = ExtTrade.OrderDelete(trans.order);
         ulong t_action_end = GetMicrosecondCount();

         PrintFormat("[TECH-02 NEUTRALIZATION ORDER RESULT] Retcode: %u (%s) | CancelAccepted: %s | Latencia: %I64u us",
                     ExtTrade.ResultRetcode(),
                     ExtTrade.ResultRetcodeDescription(),
                     deleted ? "TRUE" : "FALSE",
                     (t_action_end - t_action_start));
      }
   }
}

//+------------------------------------------------------------------+
//| Legacy Trade event handler                                       |
//+------------------------------------------------------------------+
void OnTrade()
{
   // OnTrade e chamado apos OnTradeTransaction, mas nao passa parametros
   PrintFormat("[OnTrade] SrvTime: %s | PositionsTotal: %d | OrdersTotal: %d",
               TimeToString(TimeTradeServer(), TIME_DATE|TIME_SECONDS),
               PositionsTotal(),
               OrdersTotal());
}
//+------------------------------------------------------------------+
