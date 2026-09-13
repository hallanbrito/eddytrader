//+------------------------------------------------------------------+
//|                                                probe_env_w07.mq5 |
//|                                  Copyright 2026, EddyTrader Team |
//|                                             https://eddytrader.io |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, EddyTrader Team"
#property link      "https://eddytrader.io"
#property version   "1.00"
#property strict

void LogMsg(int file, string msg)
{
   Print(msg);
   if(file != INVALID_HANDLE)
   {
      FileWriteString(file, msg + "\r\n");
      FileFlush(file);
   }
}

int OnInit()
{
   int file = FileOpen("probe_env_w07.txt", FILE_WRITE|FILE_TXT|FILE_ANSI);
   
   LogMsg(file, "==================================================");
   LogMsg(file, "[PROBE W07] Sonda de Ambiente MT5 Demo (Expert Mode)");
   LogMsg(file, "==================================================");
   
   long login                           = AccountInfoInteger(ACCOUNT_LOGIN);
   string server                        = AccountInfoString(ACCOUNT_SERVER);
   ENUM_ACCOUNT_TRADE_MODE trade_mode   = (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   ENUM_ACCOUNT_MARGIN_MODE margin_mode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   double balance                       = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity                        = AccountInfoDouble(ACCOUNT_EQUITY);
   double free_margin                   = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   string currency                      = AccountInfoString(ACCOUNT_CURRENCY);
   bool trade_allowed                   = (bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED);
   bool term_trade_allowed              = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   bool connected                       = (bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   int build                            = (int)TerminalInfoInteger(TERMINAL_BUILD);
   datetime t_serv                      = TimeTradeServer();
   datetime t_curr                      = TimeCurrent();
   datetime t_loc                       = TimeLocal();
   
   string tm_str = (trade_mode == ACCOUNT_TRADE_MODE_DEMO) ? "DEMO" : ((trade_mode == ACCOUNT_TRADE_MODE_REAL) ? "REAL" : "CONTEST");
   string mm_str = (margin_mode == ACCOUNT_MARGIN_MODE_RETAIL_NETTING) ? "RETAIL NETTING" : 
                   ((margin_mode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) ? "RETAIL HEDGING" : "EXCHANGE");

   LogMsg(file, StringFormat("LOGIN: %I64u | SERVER: %s | BUILD: %d | CONNECTED: %s", login, server, build, (connected ? "SIM" : "NAO")));
   LogMsg(file, StringFormat("TRADE MODE: %s | MARGIN MODE: %s", tm_str, mm_str));
   LogMsg(file, StringFormat("BALANCE: %.2f %s | EQUITY: %.2f %s | FREE MARGIN: %.2f %s", balance, currency, equity, currency, free_margin, currency));
   LogMsg(file, StringFormat("TRADE ALLOWED (ACCOUNT): %s | ALGO TRADING (TERMINAL): %s", (trade_allowed ? "SIM" : "NAO"), (term_trade_allowed ? "SIM" : "NAO")));
   LogMsg(file, StringFormat("SERVER TIME: %s | CURRENT TICK TIME: %s | LOCAL TIME: %s",
                             TimeToString(t_serv, TIME_DATE|TIME_SECONDS),
                             TimeToString(t_curr, TIME_DATE|TIME_SECONDS),
                             TimeToString(t_loc, TIME_DATE|TIME_SECONDS)));

   if(trade_mode != ACCOUNT_TRADE_MODE_DEMO)
   {
      LogMsg(file, "[PROBE W07] ABORTAR: Conta NAO e Demo! Operacao vetada por seguranca.");
      FileClose(file);
      TerminalClose(0);
      return INIT_FAILED;
   }

   LogMsg(file, "--- VERIFICACAO DE ATIVOS DIRECIONADOS ---");
   string test_symbols[] = {"EURUSD", "GBPUSD", "USDJPY", "BTCUSD", "ETHUSD", "XAUUSD", "US500", "BTCUSD.", "ETHUSD."};
   for(int i = 0; i < ArraySize(test_symbols); i++)
   {
      string sym = test_symbols[i];
      ResetLastError();
      SymbolSelect(sym, true);
      double bid          = SymbolInfoDouble(sym, SYMBOL_BID);
      double ask          = SymbolInfoDouble(sym, SYMBOL_ASK);
      long trade_mode_sym = SymbolInfoInteger(sym, SYMBOL_TRADE_MODE);
      long spread         = SymbolInfoInteger(sym, SYMBOL_SPREAD);
      double min_vol      = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double step_vol     = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
      
      LogMsg(file, StringFormat("SIMBOLO: %-10s | TRADE_MODE: %d | BID: %10.5f | ASK: %10.5f | SPREAD: %4I64d | VOL_MIN: %.2f | STEP: %.2f",
                                sym, (int)trade_mode_sym, bid, ask, spread, min_vol, step_vol));
   }

   LogMsg(file, "--- VARREDURA DE ATIVOS TOTALMENTE ABERTOS (TRADE_MODE_FULL) ---");
   int total_symbols = SymbolsTotal(false);
   LogMsg(file, StringFormat("Total de Simbolos no Terminal: %d", total_symbols));
   int open_count = 0;
   for(int i = 0; i < total_symbols; i++)
   {
      string sym = SymbolName(i, false);
      long trade_mode_sym = SymbolInfoInteger(sym, SYMBOL_TRADE_MODE);
      if(trade_mode_sym == SYMBOL_TRADE_MODE_FULL)
      {
         SymbolSelect(sym, true);
         double bid = SymbolInfoDouble(sym, SYMBOL_BID);
         double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
         if(bid > 0)
         {
            open_count++;
            if(open_count <= 30)
            {
               LogMsg(file, StringFormat("-> ATIVO ABERTO: %-12s | BID: %10.5f | ASK: %10.5f | SPREAD: %4I64d | MIN_VOL: %.2f",
                                         sym, bid, ask, SymbolInfoInteger(sym, SYMBOL_SPREAD), SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN)));
            }
         }
      }
   }
   LogMsg(file, StringFormat("Total de Ativos Abertos e Cotando: %d", open_count));
   LogMsg(file, "==================================================");
   
   FileClose(file);
   return INIT_SUCCEEDED;
}

void OnTick() {}
//+------------------------------------------------------------------+
