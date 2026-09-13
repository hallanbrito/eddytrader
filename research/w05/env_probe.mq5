//+------------------------------------------------------------------+
//|                                                    env_probe.mq5 |
//|                                      W05 EXPERIMENTAL SPIKE      |
//|                                      NOT PRODUCTION CODE         |
//+------------------------------------------------------------------+
#property copyright "EddyTrader W05 Spike"
#property link      "https://github.com/eddytrader"
#property version   "1.00"
#property script_show_inputs

void OnStart()
{
   Print("=== [W05 EXPERIMENTAL SPIKE] ENVIRONMENT PROBE ===");
   
   // Terminal Info
   PrintFormat("Terminal Build: %d", TerminalInfoInteger(TERMINAL_BUILD));
   PrintFormat("Terminal Path: %s", TerminalInfoString(TERMINAL_PATH));
   PrintFormat("Data Path: %s", TerminalInfoString(TERMINAL_DATA_PATH));
   PrintFormat("Common Data Path: %s", TerminalInfoString(TERMINAL_COMMONDATA_PATH));
   PrintFormat("Connected: %s", TerminalInfoInteger(TERMINAL_CONNECTED) ? "YES" : "NO");
   PrintFormat("Trade Allowed (Terminal): %s", TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ? "YES" : "NO");

   // Account Info
   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   ENUM_ACCOUNT_TRADE_MODE trade_mode = (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   string mode_str = "UNKNOWN";
   if(trade_mode == ACCOUNT_TRADE_MODE_DEMO) mode_str = "DEMO";
   else if(trade_mode == ACCOUNT_TRADE_MODE_CONTEST) mode_str = "CONTEST";
   else if(trade_mode == ACCOUNT_TRADE_MODE_REAL) mode_str = "REAL";

   ENUM_ACCOUNT_MARGIN_MODE margin_mode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   string margin_str = "UNKNOWN";
   if(margin_mode == ACCOUNT_MARGIN_MODE_RETAIL_NETTING) margin_str = "RETAIL_NETTING";
   else if(margin_mode == ACCOUNT_MARGIN_MODE_EXCHANGE) margin_str = "EXCHANGE";
   else if(margin_mode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) margin_str = "RETAIL_HEDGING";

   PrintFormat("Account Login: %I64d", login);
   PrintFormat("Account Trade Mode: %s (%d)", mode_str, (int)trade_mode);
   PrintFormat("Account Margin Mode: %s (%d)", margin_str, (int)margin_mode);
   PrintFormat("Account Server: %s", AccountInfoString(ACCOUNT_SERVER));
   PrintFormat("Account Company: %s", AccountInfoString(ACCOUNT_COMPANY));
   PrintFormat("Account Currency: %s", AccountInfoString(ACCOUNT_CURRENCY));
   PrintFormat("Account Balance: %.2f", AccountInfoDouble(ACCOUNT_BALANCE));
   PrintFormat("Account Equity: %.2f", AccountInfoDouble(ACCOUNT_EQUITY));
   PrintFormat("Account Profit: %.2f", AccountInfoDouble(ACCOUNT_PROFIT));

   // Time Info
   datetime t_curr = TimeCurrent();
   datetime t_server = TimeTradeServer();
   datetime t_local = TimeLocal();
   datetime t_gmt = TimeGMT();
   PrintFormat("TimeCurrent(): %s (%lld)", TimeToString(t_curr, TIME_DATE|TIME_SECONDS), (long)t_curr);
   PrintFormat("TimeTradeServer(): %s (%lld)", TimeToString(t_server, TIME_DATE|TIME_SECONDS), (long)t_server);
   PrintFormat("TimeLocal(): %s (%lld)", TimeToString(t_local, TIME_DATE|TIME_SECONDS), (long)t_local);
   PrintFormat("TimeGMT(): %s (%lld)", TimeToString(t_gmt, TIME_DATE|TIME_SECONDS), (long)t_gmt);

   Print("=== [W05 EXPERIMENTAL SPIKE] PROBE COMPLETE ===");
}
//+------------------------------------------------------------------+
