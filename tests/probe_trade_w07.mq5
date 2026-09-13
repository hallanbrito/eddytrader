//+------------------------------------------------------------------+
//|                                                probe_trade_w07.mq5 |
//|                                  Copyright 2026, EddyTrader Team |
//|                                             https://eddytrader.io |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, EddyTrader Team"
#property link      "https://eddytrader.io"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

void LogMsg(int file, string msg)
{
   Print(msg);
   if(file != INVALID_HANDLE)
   {
      FileWriteString(file, msg + "\r\n");
      FileFlush(file);
   }
}

void OnStart()
{
   int file = FileOpen("probe_trade_w07.txt", FILE_WRITE|FILE_TXT|FILE_ANSI);
   LogMsg(file, "==================================================");
   LogMsg(file, "[PROBE TRADE W07] Teste de Ordem no Servidor Demo");
   LogMsg(file, "==================================================");

   ENUM_ACCOUNT_TRADE_MODE trade_mode = (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(trade_mode != ACCOUNT_TRADE_MODE_DEMO)
   {
      LogMsg(file, "ABORTAR: Conta NAO e Demo! Operacao cancelada.");
      FileClose(file);
      return;
   }

   string sym = "EURUSD";
   datetime t_serv = TimeTradeServer();
   MqlDateTime dt;
   TimeToStruct(t_serv, dt);
   LogMsg(file, StringFormat("Server Time: %s (Dia da semana: %d, Hora: %02d:%02d)",
                             TimeToString(t_serv, TIME_DATE|TIME_SECONDS), dt.day_of_week, dt.hour, dt.min));

   // Checar sessoes de negociacao para hoje
   datetime from_t, to_t;
   int session_idx = 0;
   LogMsg(file, StringFormat("--- SESSOES DE TRADING PARA O DIA %d (%s) ---", dt.day_of_week, sym));
   while(SymbolInfoSessionTrade(sym, (ENUM_DAY_OF_WEEK)dt.day_of_week, session_idx, from_t, to_t))
   {
      LogMsg(file, StringFormat("  Sessao [%d]: De %s ate %s", session_idx,
                                TimeToString(from_t, TIME_MINUTES), TimeToString(to_t, TIME_MINUTES)));
      session_idx++;
   }
   if(session_idx == 0)
   {
      LogMsg(file, "  Nenhuma sessao de trading configurada para hoje neste ativo.");
   }

   // 1. Teste de ordem a mercado (0.01 EURUSD)
   CTrade trade;
   trade.SetExpertMagicNumber(999001);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   LogMsg(file, StringFormat("Precos atuais EURUSD: Bid=%.5f, Ask=%.5f", bid, ask));

   LogMsg(file, "--- TESTE 1: Envio de Buy a mercado (0.01 lot) ---");
   ResetLastError();
   bool buy_ok = trade.Buy(0.01, sym, ask, 0.0, 0.0, "W07 Test Buy");
   uint retcode = trade.ResultRetcode();
   string desc = trade.ResultRetcodeDescription();
   ulong order_id = trade.ResultOrder();
   ulong deal_id = trade.ResultDeal();
   int last_err = GetLastError();

   LogMsg(file, StringFormat("Resultado Buy: ok=%s | retcode=%u (%s) | order=%I64u | deal=%I64u | LastError=%d",
                             (buy_ok ? "TRUE" : "FALSE"), retcode, desc, order_id, deal_id, last_err));

   // 2. Teste de ordem pendente (Buy Limit bem abaixo do preco)
   LogMsg(file, "--- TESTE 2: Envio de Buy Limit pendente (0.01 lot a 1.10000) ---");
   ResetLastError();
   bool limit_ok = trade.BuyLimit(0.01, 1.10000, sym, 0.0, 0.0, ORDER_TIME_GTC, 0, "W07 Test Limit");
   uint limit_retcode = trade.ResultRetcode();
   string limit_desc = trade.ResultRetcodeDescription();
   ulong limit_order = trade.ResultOrder();
   int limit_err = GetLastError();

   LogMsg(file, StringFormat("Resultado BuyLimit: ok=%s | retcode=%u (%s) | order=%I64u | LastError=%d",
                             (limit_ok ? "TRUE" : "FALSE"), limit_retcode, limit_desc, limit_order, limit_err));

   if(limit_ok && limit_order > 0)
   {
      LogMsg(file, StringFormat("Limpando ordem pendente de teste #%I64u...", limit_order));
      trade.OrderDelete(limit_order);
      LogMsg(file, StringFormat("OrderDelete retcode=%u (%s)", trade.ResultRetcode(), trade.ResultRetcodeDescription()));
   }

   // 3. Teste em todos os outros ativos abertos
   string other_symbols[] = {"GBPUSD", "USDJPY", "BTCUSD", "ETHUSD"};
   for(int i = 0; i < ArraySize(other_symbols); i++)
   {
      string s = other_symbols[i];
      ResetLastError();
      SymbolSelect(s, true);
      double a = SymbolInfoDouble(s, SYMBOL_ASK);
      if(a > 0)
      {
         LogMsg(file, StringFormat("--- TESTE em %s (Ask=%.5f) ---", s, a));
         bool ok = trade.Buy(0.01, s, a, 0.0, 0.0, "W07 Probe");
         LogMsg(file, StringFormat("Resultado %s: ok=%s | retcode=%u (%s)",
                                   s, (ok ? "TRUE" : "FALSE"), trade.ResultRetcode(), trade.ResultRetcodeDescription()));
      }
   }

   LogMsg(file, "==================================================");
   FileClose(file);
}
