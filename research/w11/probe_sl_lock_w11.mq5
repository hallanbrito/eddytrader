//+------------------------------------------------------------------+
//|                                          probe_sl_lock_w11.mq5   |
//|                                  Copyright 2026, EddyTrader Team |
//+------------------------------------------------------------------+
// RESEARCH ONLY: observational harness for W11 / GAP-007.
// This EA never sends, modifies, cancels or closes an order.
// It is intentionally isolated from src/EddyTrader.mq5.
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, EddyTrader Team"
#property version   "1.10"
#property description "[RESEARCH ONLY] Observational Stop Loss event probe for W11"
#property strict

input group "=== LAB SAFETY ==="
input bool InpConfirmDemoLab = false; // Must be true; real accounts are always rejected

input group "=== OBSERVATION ==="
input int  InpTimerIntervalMs = 500;  // Reconciliation interval
input bool InpLogAllTransactions = true;
input bool InpVerboseUnchangedScans = false;

#define MAX_TRACKED_POSITIONS 256

ulong  g_tickets[MAX_TRACKED_POSITIONS];
double g_locked_sl[MAX_TRACKED_POSITIONS];
int    g_direction[MAX_TRACKED_POSITIONS];
string g_symbol[MAX_TRACKED_POSITIONS];
int    g_count = 0;
int    g_file = INVALID_HANDLE;
ulong  g_txn_count = 0;

void ProbeLog(const string level, const string message)
{
   string line = StringFormat("[PROBE-SL-W11][%s] %s", level, message);
   Print(line);
   if(g_file != INVALID_HANDLE)
   {
      FileWriteString(g_file,
                      TimeToString(TimeTradeServer(), TIME_DATE|TIME_SECONDS) + " " + line + "\r\n");
      FileFlush(g_file);
   }
}

int CacheFind(const ulong ticket)
{
   for(int i = 0; i < g_count; i++)
      if(g_tickets[i] == ticket) return i;
   return -1;
}

bool CacheInsert(const ulong ticket, const string symbol, const int direction, const double sl)
{
   if(g_count >= MAX_TRACKED_POSITIONS)
   {
      ProbeLog("ERROR", "Cache capacity reached; observation is incomplete.");
      return false;
   }

   g_tickets[g_count] = ticket;
   g_symbol[g_count] = symbol;
   g_direction[g_count] = direction;
   g_locked_sl[g_count] = sl;
   g_count++;
   return true;
}

void CacheRemoveAt(const int index)
{
   if(index < 0 || index >= g_count) return;
   for(int i = index; i < g_count - 1; i++)
   {
      g_tickets[i] = g_tickets[i + 1];
      g_symbol[i] = g_symbol[i + 1];
      g_direction[i] = g_direction[i + 1];
      g_locked_sl[i] = g_locked_sl[i + 1];
   }
   g_count--;
}

string ClassifySLChange(const int direction,
                        const double locked_sl,
                        const double server_sl,
                        const double tick_size)
{
   double tolerance = (tick_size > 0.0 ? tick_size * 0.5 : 1e-10);

   if(locked_sl != 0.0 && server_sl == 0.0)
      return "VIOLATION_REMOVAL";
   if(locked_sl == 0.0 && server_sl != 0.0)
      return "BASELINE_SET";
   if(MathAbs(server_sl - locked_sl) < tolerance)
      return "NO_CHANGE";
   if(direction == POSITION_TYPE_BUY)
      return (server_sl < locked_sl ? "VIOLATION_WIDENING" : "IMPROVEMENT_TIGHTENING");
   return (server_sl > locked_sl ? "VIOLATION_WIDENING" : "IMPROVEMENT_TIGHTENING");
}

void ObserveSelectedPosition(const ulong ticket, const string source)
{
   if(!PositionSelectByTicket(ticket))
   {
      int stale = CacheFind(ticket);
      if(stale >= 0)
      {
         ProbeLog("CLOSED", StringFormat("source=%s ticket=#%I64u locked_sl=%.5f",
                                          source, ticket, g_locked_sl[stale]));
         CacheRemoveAt(stale);
      }
      return;
   }

   string symbol = PositionGetString(POSITION_SYMBOL);
   int direction = (int)PositionGetInteger(POSITION_TYPE);
   double server_sl = PositionGetDouble(POSITION_SL);
   double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   long stops_level = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze_level = SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   int index = CacheFind(ticket);

   if(index < 0)
   {
      if(CacheInsert(ticket, symbol, direction, server_sl))
      {
         ProbeLog(server_sl == 0.0 ? "FIRST_SEEN_NO_SL" : "FIRST_SEEN_WITH_SL",
                  StringFormat("source=%s ticket=#%I64u symbol=%s dir=%s sl=%.5f tick=%.5f stops=%d freeze=%d",
                               source, ticket, symbol,
                               (direction == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                               server_sl, tick_size, stops_level, freeze_level));
      }
      return;
   }

   string classification = ClassifySLChange(direction, g_locked_sl[index], server_sl, tick_size);
   if(classification == "NO_CHANGE")
   {
      if(InpVerboseUnchangedScans)
         ProbeLog("UNCHANGED", StringFormat("source=%s ticket=#%I64u sl=%.5f", source, ticket, server_sl));
      return;
   }

   ProbeLog("SL_CHANGE",
            StringFormat("source=%s ticket=#%I64u symbol=%s dir=%s locked=%.5f server=%.5f tick=%.5f stops=%d freeze=%d class=%s",
                         source, ticket, symbol,
                         (direction == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                         g_locked_sl[index], server_sl, tick_size,
                         stops_level, freeze_level, classification));

   if(classification == "BASELINE_SET" || classification == "IMPROVEMENT_TIGHTENING")
   {
      g_locked_sl[index] = server_sl;
      ProbeLog("CACHE_ADVANCED", StringFormat("ticket=#%I64u new_locked_sl=%.5f", ticket, server_sl));
   }
   else
   {
      ProbeLog("VIOLATION_OBSERVED",
               StringFormat("ticket=#%I64u retained_locked_sl=%.5f observed_sl=%.5f; no corrective request sent",
                            ticket, g_locked_sl[index], server_sl));
   }
}

void ReconcilePositions(const string source)
{
   bool seen[MAX_TRACKED_POSITIONS];
   ArrayInitialize(seen, false);

   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      ObserveSelectedPosition(ticket, source);
      int index = CacheFind(ticket);
      if(index >= 0) seen[index] = true;
   }

   for(int i = g_count - 1; i >= 0; i--)
   {
      if(!seen[i] && !PositionSelectByTicket(g_tickets[i]))
      {
         ProbeLog("CLOSED", StringFormat("source=%s ticket=#%I64u locked_sl=%.5f",
                                          source, g_tickets[i], g_locked_sl[i]));
         CacheRemoveAt(i);
      }
   }
}

int OnInit()
{
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) != ACCOUNT_TRADE_MODE_DEMO)
   {
      Print("[PROBE-SL-W11][CRITICAL] Real/contest execution rejected; DEMO only.");
      return INIT_FAILED;
   }
   if(!InpConfirmDemoLab)
   {
      Print("[PROBE-SL-W11][ERROR] Set InpConfirmDemoLab=true to acknowledge research-only execution.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpTimerIntervalMs < 100 || InpTimerIntervalMs > 60000)
   {
      Print("[PROBE-SL-W11][ERROR] InpTimerIntervalMs must be between 100 and 60000.");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_file = FileOpen("probe_sl_lock_w11_log.txt",
                     FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   if(g_file != INVALID_HANDLE)
      FileSeek(g_file, 0, SEEK_END);

   ProbeLog("INIT",
            StringFormat("RESEARCH ONLY; no OrderSend. account=%I64u server=%s margin_mode=%s timer_ms=%d",
                         AccountInfoInteger(ACCOUNT_LOGIN),
                         AccountInfoString(ACCOUNT_SERVER),
                         EnumToString((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)),
                         InpTimerIntervalMs));

   ReconcilePositions("INIT");
   EventSetMillisecondTimer(InpTimerIntervalMs);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ProbeLog("DEINIT", StringFormat("reason=%d transactions=%I64u tracked=%d", reason, g_txn_count, g_count));
   if(g_file != INVALID_HANDLE) FileClose(g_file);
   g_file = INVALID_HANDLE;
}

void OnTimer()
{
   ReconcilePositions("TIMER");
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   g_txn_count++;
   if(InpLogAllTransactions)
   {
      ProbeLog("TXN",
               StringFormat("seq=%I64u type=%s order=#%I64u deal=#%I64u position=#%I64u symbol=%s price=%.5f price_sl=%.5f request_id=%u retcode=%u",
                            g_txn_count, EnumToString(trans.type), trans.order, trans.deal,
                            trans.position, trans.symbol, trans.price, trans.price_sl,
                            result.request_id, result.retcode));
   }

   // Server inventory is authoritative; event order is not assumed.
   if(trans.position > 0)
      ObserveSelectedPosition(trans.position, EnumToString(trans.type));
   else
      ReconcilePositions(EnumToString(trans.type));

   if(trans.type == TRADE_TRANSACTION_ORDER_ADD ||
      trans.type == TRADE_TRANSACTION_ORDER_UPDATE ||
      trans.type == TRADE_TRANSACTION_ORDER_DELETE)
   {
      ProbeLog("PENDING_ORDER_EVENT",
               StringFormat("type=%s order=#%I64u symbol=%s price=%.5f price_sl=%.5f; observation only",
                            EnumToString(trans.type), trans.order, trans.symbol,
                            trans.price, trans.price_sl));
   }
}

void OnTick()
{
   // Intentionally empty. Observation is event/timer driven.
}
