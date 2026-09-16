//+------------------------------------------------------------------+
//|                              probe_pending_order_gate_w11.mq5   |
//|                                  Copyright 2026, EddyTrader Team |
//+------------------------------------------------------------------+
// RESEARCH ONLY — W11 Gate: Ordens Pendentes com SL/TP Anexados.
//
// Objetivo: observar o ciclo completo de vida de Buy Limit, Sell Limit,
// Buy Stop e Sell Stop configuradas previamente com SL e TP validos,
// verificando se e como o SL/TP chegam a posicao apos a ativacao
// e quais eventos OnTradeTransaction sao emitidos.
//
// Separacao explicita do probe_sl_lock_w11.mq5 (observacional):
//   - Este probe ENVIA ordens pendentes experimentais controladas.
//   - O probe observacional NAO envia ordens.
//
// Restricoes absolutas:
//   1. Exige ACCOUNT_TRADE_MODE_DEMO - rejeita Real e Contest.
//   2. Exige InpConfirmDemoLab = true (input explicito do operador).
//   3. Nao implementa restauracao, fechamento corretivo, OCO, trailing.
//   4. Nao toca src/EddyTrader.mq5 nem qualquer codigo de producao.
//   5. Limpeza final por ticket - apenas dos objetos criados por este probe.
//   6. Nunca interfere em posicoes/ordens externas (filtro por magic).
//   7. Se o simbolo nao oferece condicoes seguras (stops level),
//      o probe registra BLOCKED e nao coloca ordens.
//
// Protocolo de execucao:
//   - Ao ativar (InpRunProbe = true), tenta colocar as 4 ordens pendentes
//     (Buy Limit, Sell Limit, Buy Stop, Sell Stop), cada uma com SL e TP.
//   - Registra em log os eventos recebidos e o inventario real pos-ativacao.
//   - Aguarda ativacao. Apos InpTimerCyclesMax ciclos sem ativacao,
//     cancela as pendentes e registra BLOCKED.
//   - Cleanup ao deinit: cancela todas as ordens pending com o magic deste probe.
//
// NAO GERE PASS sem evidencia empirica observada:
//   cada celula da matriz requer evento e inventario real capturados.
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, EddyTrader Team"
#property version   "1.01"
#property description "[RESEARCH ONLY] Pending Order Gate - W11 / GAP-007"
#property strict

//--- Safety inputs
input group "=== LAB SAFETY ==="
input bool   InpConfirmDemoLab   = false; // Must be TRUE; Real/Contest always rejected
input bool   InpRunProbe         = false; // Must be TRUE to place experimental orders

//--- Probe parameters
input group "=== PROBE PARAMETERS ==="
input string InpSymbol           = "GBPUSD"; // Symbol for experimental orders
input double InpVolumeLot        = 0.01;      // Minimum allowed volume
input int    InpOffsetPoints     = 100;       // Points offset from current price for pending price
input int    InpSlPoints         = 150;       // Points offset for SL (from pending price)
input int    InpTpPoints         = 150;       // Points offset for TP (from pending price)
input int    InpTimerCyclesMax   = 600;       // Max timer cycles (~5 min at 500ms) before cleanup
input int    InpTimerMs          = 500;       // Reconciliation timer interval (ms)
input bool   InpVerboseScans     = false;     // Log unchanged scans

//--- Magic number identifying this probe's orders
#define PROBE_MAGIC  20261101

//--- State machine
enum EProbeState
{
   PROBE_IDLE,       // Not yet started
   PROBE_PLACING,    // Placing 4 pending orders
   PROBE_MONITORING, // Waiting for activation / observing events
   PROBE_CLEANUP,    // Cancelling remaining pending orders
   PROBE_DONE        // Finished; report generated
};

//--- Per-order observation record
struct SPendingRecord
{
   ulong           ticket;
   string          label;          // "BUY_LIMIT", "SELL_LIMIT", "BUY_STOP", "SELL_STOP"
   ENUM_ORDER_TYPE order_type;
   double          price_req;
   double          sl_req;
   double          tp_req;
   double          price_acc;      // accepted by server (from OrderSelect)
   double          sl_acc;
   double          tp_acc;
   bool            placed;
   bool            activated;
   bool            cancelled;
   ulong           position_ticket;
   double          pos_sl_first;   // SL on position at first inventory snapshot (-1 = not yet)
   double          pos_tp_first;
   string          sl_class;       // "BASELINE_SET" or "WAIT_FIRST_SL"
   int             events_seen;
};

//--- Order definition helper (named struct to avoid MQL5 anonymous-struct limitation)
struct SOrderDef
{
   string          lbl;
   ENUM_ORDER_TYPE t;
   double          p;
   double          s;
   double          tp;
};

//--- Globals
EProbeState     g_state           = PROBE_IDLE;
SPendingRecord  g_records[4];
int             g_record_count    = 0;
int             g_cycles_waited   = 0;
int             g_file            = INVALID_HANDLE;
ulong           g_txn_count       = 0;
double          g_tick_size       = 0.0;
long            g_stops_level     = 0;
long            g_freeze_level    = 0;
int             g_digits          = 5;
ENUM_SYMBOL_TRADE_EXECUTION g_exec_mode = SYMBOL_TRADE_EXECUTION_REQUEST;
string          g_margin_mode_str = "";

//+------------------------------------------------------------------+
//| Logging                                                          |
//+------------------------------------------------------------------+
void PLog(const string level, const string msg)
{
   string line = StringFormat("[PROBE-PENDING-W11][%s] %s", level, msg);
   Print(line);
   if(g_file != INVALID_HANDLE)
   {
      FileWriteString(g_file,
                      TimeToString(TimeTradeServer(), TIME_DATE|TIME_SECONDS) +
                      " " + line + "\r\n");
      FileFlush(g_file);
   }
}

//+------------------------------------------------------------------+
//| Classify first-seen SL of position (W11-DEC-02)                 |
//+------------------------------------------------------------------+
string ClassifyFirstSL(const double position_sl)
{
   return (position_sl > 0.0 ? "BASELINE_SET" : "WAIT_FIRST_SL");
}

//+------------------------------------------------------------------+
//| Normalize price to symbol digits                                 |
//+------------------------------------------------------------------+
double NormP(const double price)
{
   return NormalizeDouble(price, g_digits);
}

//+------------------------------------------------------------------+
//| Validate symbol conditions for safe order placement             |
//+------------------------------------------------------------------+
bool ValidateSymbolConditions(const double ask, const double bid)
{
   if(ask <= 0.0 || bid <= 0.0)
   {
      PLog("BLOCKED", "Invalid ask/bid quotes; cannot place orders.");
      return false;
   }
   if(g_tick_size <= 0.0)
   {
      PLog("BLOCKED", "Tick size is zero or negative; cannot compute offsets.");
      return false;
   }

   double spread_pts = (ask - bid) / g_tick_size;

   PLog("SYMBOL",
        StringFormat("sym=%s digits=%d tick=%.5f stops_level=%d freeze_level=%d "
                     "spread_pts=%.1f exec_mode=%s margin_mode=%s ask=%.5f bid=%.5f",
                     InpSymbol, g_digits, g_tick_size,
                     (int)g_stops_level, (int)g_freeze_level,
                     spread_pts, EnumToString(g_exec_mode), g_margin_mode_str,
                     ask, bid));

   if((long)InpOffsetPoints <= g_stops_level)
   {
      PLog("BLOCKED",
           StringFormat("InpOffsetPoints=%d <= stops_level=%d; increase offset to place safely.",
                        InpOffsetPoints, (int)g_stops_level));
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Place one pending order; returns ticket or 0 on failure         |
//+------------------------------------------------------------------+
ulong PlacePendingOrder(const string label,
                        const ENUM_ORDER_TYPE type,
                        const double price,
                        const double sl,
                        const double tp)
{
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action      = TRADE_ACTION_PENDING;
   req.symbol      = InpSymbol;
   req.volume      = InpVolumeLot;
   req.price       = NormP(price);
   req.sl          = NormP(sl);
   req.tp          = NormP(tp);
   req.type        = type;
   req.type_filling = ORDER_FILLING_FOK;
   req.magic       = PROBE_MAGIC;
   req.comment     = StringFormat("W11-GATE-%s", label);
   req.type_time   = ORDER_TIME_GTC;

   PLog("ORDER_REQ",
        StringFormat("label=%s type=%s price=%.5f sl=%.5f tp=%.5f vol=%.2f magic=%d",
                     label, EnumToString(type),
                     req.price, req.sl, req.tp, req.volume, req.magic));

   bool ok = OrderSend(req, res);

   PLog("ORDER_RESULT",
        StringFormat("label=%s ok=%s retcode=%u order=#%I64u comment=%s",
                     label, (ok ? "true" : "false"),
                     res.retcode, res.order, res.comment));

   if(!ok || (res.retcode != TRADE_RETCODE_PLACED &&
              res.retcode != TRADE_RETCODE_DONE))
   {
      PLog("ORDER_FAILED",
           StringFormat("label=%s retcode=%u — order not placed.",
                        label, res.retcode));
      return 0;
   }
   return res.order;
}

//+------------------------------------------------------------------+
//| Place all 4 pending orders of the matrix                        |
//+------------------------------------------------------------------+
bool PlaceAllPendingOrders()
{
   double ask = SymbolInfoDouble(InpSymbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(InpSymbol, SYMBOL_BID);

   if(!ValidateSymbolConditions(ask, bid)) return false;

   double offset  = InpOffsetPoints * g_tick_size;
   double sl_dist = InpSlPoints     * g_tick_size;
   double tp_dist = InpTpPoints     * g_tick_size;

   // BUY LIMIT  — price below ask; SL below entry; TP above entry
   double bl_price = ask - offset;
   double bl_sl    = bl_price - sl_dist;
   double bl_tp    = bl_price + tp_dist;

   // SELL LIMIT — price above bid; SL above entry; TP below entry
   double sll_price = bid + offset;
   double sll_sl    = sll_price + sl_dist;
   double sll_tp    = sll_price - tp_dist;

   // BUY STOP   — price above ask; SL below entry; TP above entry
   double bs_price = ask + offset;
   double bs_sl    = bs_price - sl_dist;
   double bs_tp    = bs_price + tp_dist;

   // SELL STOP  — price below bid; SL above entry; TP below entry
   double ss_price = bid - offset;
   double ss_sl    = ss_price + sl_dist;
   double ss_tp    = ss_price - tp_dist;

   // Build order definitions using named struct array
   SOrderDef defs[4];
   defs[0].lbl = "BUY_LIMIT";  defs[0].t = ORDER_TYPE_BUY_LIMIT;
   defs[0].p   = bl_price;     defs[0].s = bl_sl;   defs[0].tp = bl_tp;

   defs[1].lbl = "SELL_LIMIT"; defs[1].t = ORDER_TYPE_SELL_LIMIT;
   defs[1].p   = sll_price;    defs[1].s = sll_sl;  defs[1].tp = sll_tp;

   defs[2].lbl = "BUY_STOP";   defs[2].t = ORDER_TYPE_BUY_STOP;
   defs[2].p   = bs_price;     defs[2].s = bs_sl;   defs[2].tp = bs_tp;

   defs[3].lbl = "SELL_STOP";  defs[3].t = ORDER_TYPE_SELL_STOP;
   defs[3].p   = ss_price;     defs[3].s = ss_sl;   defs[3].tp = ss_tp;

   g_record_count = 0;

   for(int i = 0; i < 4; i++)
   {
      SPendingRecord rec;
      ZeroMemory(rec);
      rec.label           = defs[i].lbl;
      rec.order_type      = defs[i].t;
      rec.price_req       = defs[i].p;
      rec.sl_req          = defs[i].s;
      rec.tp_req          = defs[i].tp;
      rec.pos_sl_first    = -1.0;
      rec.pos_tp_first    = -1.0;
      rec.sl_class        = "UNKNOWN";

      ulong ticket = PlacePendingOrder(rec.label, rec.order_type,
                                       rec.price_req, rec.sl_req, rec.tp_req);
      if(ticket > 0)
      {
         rec.ticket = ticket;
         rec.placed = true;
         if(OrderSelect(ticket))
         {
            rec.price_acc = OrderGetDouble(ORDER_PRICE_OPEN);
            rec.sl_acc    = OrderGetDouble(ORDER_SL);
            rec.tp_acc    = OrderGetDouble(ORDER_TP);
            PLog("ORDER_ACCEPTED",
                 StringFormat("label=%s ticket=#%I64u "
                              "price_req=%.5f price_acc=%.5f "
                              "sl_req=%.5f sl_acc=%.5f "
                              "tp_req=%.5f tp_acc=%.5f",
                              rec.label, rec.ticket,
                              rec.price_req, rec.price_acc,
                              rec.sl_req,    rec.sl_acc,
                              rec.tp_req,    rec.tp_acc));
         }
         else
         {
            PLog("WARN",
                 StringFormat("label=%s ticket=#%I64u placed but OrderSelect "
                              "failed immediately.", rec.label, rec.ticket));
         }
      }
      g_records[g_record_count] = rec;
      g_record_count++;
   }

   int placed = 0;
   for(int i = 0; i < g_record_count; i++)
      if(g_records[i].placed) placed++;

   PLog("PLACEMENT_SUMMARY",
        StringFormat("%d/%d orders placed successfully.", placed, g_record_count));

   return (placed > 0);
}

//+------------------------------------------------------------------+
//| Find record index by order ticket                               |
//+------------------------------------------------------------------+
int FindRecordByTicket(const ulong ticket)
{
   for(int i = 0; i < g_record_count; i++)
      if(g_records[i].ticket == ticket) return i;
   return -1;
}

//+------------------------------------------------------------------+
//| Observe and record position state after activation              |
//+------------------------------------------------------------------+
void ObserveActivatedPosition(const int rec_idx,
                               const ulong pos_ticket,
                               const string source)
{
   if(rec_idx < 0 || rec_idx >= g_record_count) return;
   if(!PositionSelectByTicket(pos_ticket)) return;

   double pos_sl = PositionGetDouble(POSITION_SL);
   double pos_tp = PositionGetDouble(POSITION_TP);

   if(g_records[rec_idx].pos_sl_first < 0.0)
   {
      // First inventory snapshot — server is authoritative
      g_records[rec_idx].pos_sl_first = pos_sl;
      g_records[rec_idx].pos_tp_first = pos_tp;
      g_records[rec_idx].sl_class     = ClassifyFirstSL(pos_sl);

      PLog("POSITION_FIRST_INVENTORY",
           StringFormat("label=%s source=%s "
                        "order_ticket=#%I64u pos_ticket=#%I64u "
                        "pos_sl=%.5f pos_tp=%.5f sl_class=%s",
                        g_records[rec_idx].label, source,
                        g_records[rec_idx].ticket, pos_ticket,
                        pos_sl, pos_tp, g_records[rec_idx].sl_class));
   }
   else if(InpVerboseScans)
   {
      PLog("POSITION_SCAN",
           StringFormat("label=%s source=%s pos_ticket=#%I64u "
                        "pos_sl=%.5f pos_tp=%.5f",
                        g_records[rec_idx].label, source,
                        pos_ticket, pos_sl, pos_tp));
   }
}

//+------------------------------------------------------------------+
//| Cancel all probe pending orders (cleanup)                       |
//+------------------------------------------------------------------+
void CancelProbePendingOrders()
{
   PLog("CLEANUP",
        StringFormat("Cancelling remaining probe pending orders (magic=%d).",
                     PROBE_MAGIC));

   for(int i = 0; i < g_record_count; i++)
   {
      if(!g_records[i].placed  ||
          g_records[i].activated ||
          g_records[i].cancelled) continue;
      if(g_records[i].ticket == 0) continue;

      if(!OrderSelect(g_records[i].ticket))
      {
         // Already gone
         g_records[i].cancelled = true;
         continue;
      }

      MqlTradeRequest req;
      MqlTradeResult  res;
      ZeroMemory(req);
      ZeroMemory(res);
      req.action = TRADE_ACTION_REMOVE;
      req.order  = g_records[i].ticket;

      bool ok = OrderSend(req, res);
      PLog("CANCEL_ORDER",
           StringFormat("label=%s ticket=#%I64u retcode=%u ok=%s",
                        g_records[i].label, g_records[i].ticket,
                        res.retcode, (ok ? "true" : "false")));

      if(ok && (res.retcode == TRADE_RETCODE_DONE ||
                res.retcode == TRADE_RETCODE_PLACED))
         g_records[i].cancelled = true;
   }
}

//+------------------------------------------------------------------+
//| Print final matrix report                                       |
//+------------------------------------------------------------------+
void PrintFinalReport()
{
   PLog("REPORT_START",
        "=== MATRIX REPORT - W11 PENDING ORDER GATE ===");

   PLog("REPORT",
        StringFormat("Symbol=%s Digits=%d Tick=%.5f "
                     "StopsLv=%d FreezeLv=%d ExecMode=%s MarginMode=%s",
                     InpSymbol, g_digits, g_tick_size,
                     (int)g_stops_level, (int)g_freeze_level,
                     EnumToString(g_exec_mode), g_margin_mode_str));

   for(int i = 0; i < g_record_count; i++)
   {
      SPendingRecord r = g_records[i];

      string outcome = "BLOCKED";
      if(r.placed && r.activated)
         outcome = (r.pos_sl_first >= 0.0) ? "OBSERVED" : "ACTIVATED_NO_INVENTORY";
      else if(r.placed && r.cancelled)
         outcome = "CANCELLED_NOT_ACTIVATED";
      else if(!r.placed)
         outcome = "PLACEMENT_FAILED";

      PLog("MATRIX_ROW",
           StringFormat("label=%s outcome=%s ticket=#%I64u "
                        "placed=%s activated=%s "
                        "price_req=%.5f price_acc=%.5f "
                        "sl_req=%.5f sl_acc=%.5f "
                        "tp_req=%.5f tp_acc=%.5f "
                        "pos_ticket=#%I64u "
                        "pos_sl_first=%.5f pos_tp_first=%.5f "
                        "sl_class=%s events=%d",
                        r.label, outcome, r.ticket,
                        (r.placed ? "YES" : "NO"),
                        (r.activated ? "YES" : "NO"),
                        r.price_req, r.price_acc,
                        r.sl_req,    r.sl_acc,
                        r.tp_req,    r.tp_acc,
                        r.position_ticket,
                        r.pos_sl_first,
                        r.pos_tp_first,
                        r.sl_class,
                        r.events_seen));
   }

   PLog("REPORT",
        StringFormat("Total OnTradeTransaction events captured: %I64u",
                     g_txn_count));
   PLog("REPORT_END", "=== END MATRIX REPORT ===");
}

//+------------------------------------------------------------------+
//| True when all placed records have reached a terminal state      |
//+------------------------------------------------------------------+
bool AllRecordsDone()
{
   for(int i = 0; i < g_record_count; i++)
   {
      if(!g_records[i].placed) continue;
      if(!g_records[i].activated && !g_records[i].cancelled) return false;
   }
   return (g_record_count > 0);
}

//+------------------------------------------------------------------+
//| OnInit                                                          |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Guard 1: Demo only
   ENUM_ACCOUNT_TRADE_MODE mode =
      (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(mode != ACCOUNT_TRADE_MODE_DEMO)
   {
      Print("[PROBE-PENDING-W11][CRITICAL] Account is NOT Demo (",
            EnumToString(mode), "). Refusing. RESEARCH ONLY.");
      return INIT_FAILED;
   }

   //--- Guard 2: explicit operator confirmation
   if(!InpConfirmDemoLab)
   {
      Print("[PROBE-PENDING-W11][ERROR] Set InpConfirmDemoLab=true to acknowledge "
            "research-only execution. EA will not start.");
      return INIT_PARAMETERS_INCORRECT;
   }

   //--- Guard 3: trading allowed
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
   {
      Print("[PROBE-PENDING-W11][ERROR] Trading not allowed on this account.");
      return INIT_FAILED;
   }

   //--- Symbol metadata
   g_tick_size    = SymbolInfoDouble(InpSymbol, SYMBOL_TRADE_TICK_SIZE);
   g_stops_level  = SymbolInfoInteger(InpSymbol, SYMBOL_TRADE_STOPS_LEVEL);
   g_freeze_level = SymbolInfoInteger(InpSymbol, SYMBOL_TRADE_FREEZE_LEVEL);
   g_digits       = (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS);
   g_exec_mode    = (ENUM_SYMBOL_TRADE_EXECUTION)
                    SymbolInfoInteger(InpSymbol, SYMBOL_TRADE_EXEMODE);
   g_margin_mode_str = EnumToString(
      (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE));

   if(g_tick_size <= 0.0)
   {
      Print("[PROBE-PENDING-W11][ERROR] Invalid tick size for symbol ", InpSymbol);
      return INIT_FAILED;
   }

   //--- Open log file (append)
   g_file = FileOpen("probe_pending_order_gate_w11_log.txt",
                     FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   if(g_file != INVALID_HANDLE)
      FileSeek(g_file, 0, SEEK_END);

   PLog("INIT",
        StringFormat("RESEARCH ONLY - W11 Pending Order Gate. "
                     "account=%I64u server=%s margin_mode=%s "
                     "sym=%s digits=%d tick=%.5f stops=%d freeze=%d exec=%s "
                     "run_probe=%s",
                     AccountInfoInteger(ACCOUNT_LOGIN),
                     AccountInfoString(ACCOUNT_SERVER),
                     g_margin_mode_str,
                     InpSymbol, g_digits, g_tick_size,
                     (int)g_stops_level, (int)g_freeze_level,
                     EnumToString(g_exec_mode),
                     (InpRunProbe ? "YES" : "NO (standby)")));

   if(!InpRunProbe)
   {
      PLog("STANDBY",
           "InpRunProbe=false. No orders will be placed. "
           "Re-attach with InpRunProbe=true to activate.");
   }

   g_state = (InpRunProbe ? PROBE_PLACING : PROBE_IDLE);
   EventSetMillisecondTimer(InpTimerMs);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();

   if(g_state == PROBE_MONITORING || g_state == PROBE_PLACING)
   {
      PLog("DEINIT_CLEANUP",
           "EA deinitialized mid-session; cancelling remaining probe orders.");
      CancelProbePendingOrders();
      PrintFinalReport();
   }

   PLog("DEINIT",
        StringFormat("reason=%d state=%d txn=%I64u records=%d",
                     reason, (int)g_state, g_txn_count, g_record_count));

   if(g_file != INVALID_HANDLE) FileClose(g_file);
   g_file = INVALID_HANDLE;
}

//+------------------------------------------------------------------+
//| OnTimer — main reconciliation loop                              |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(g_state == PROBE_IDLE) return;

   if(g_state == PROBE_PLACING)
   {
      if(!PlaceAllPendingOrders())
      {
         PLog("PLACING_FAILED",
              "No orders placed. Probe entering DONE without observation.");
         PrintFinalReport();
         g_state = PROBE_DONE;
         return;
      }
      g_state = PROBE_MONITORING;
      g_cycles_waited = 0;
      PLog("MONITORING_START",
           StringFormat("Monitoring %d pending orders. "
                        "Max timer cycles: %d (~%d sec at %d ms/cycle).",
                        g_record_count, InpTimerCyclesMax,
                        InpTimerCyclesMax * InpTimerMs / 1000,
                        InpTimerMs));
      return;
   }

   if(g_state == PROBE_MONITORING)
   {
      // Timer-based fallback reconciliation
      for(int i = 0; i < g_record_count; i++)
      {
         if(!g_records[i].placed  ||
             g_records[i].activated ||
             g_records[i].cancelled) continue;
         if(g_records[i].ticket == 0) continue;

         if(!OrderSelect(g_records[i].ticket))
         {
            // Order left pending list — check if it became a position
            PLog("TIMER_ORDER_GONE",
                 StringFormat("label=%s ticket=#%I64u no longer in "
                              "pending orders. Checking position inventory.",
                              g_records[i].label, g_records[i].ticket));

            // Netting: position ticket == order ticket
            ulong pos_t = g_records[i].ticket;
            if(PositionSelectByTicket(pos_t))
            {
               g_records[i].activated       = true;
               g_records[i].position_ticket = pos_t;
               ObserveActivatedPosition(i, pos_t, "TIMER_FALLBACK");
            }
            else if(!g_records[i].activated)
            {
               g_records[i].cancelled = true;
               PLog("TIMER_ORDER_CANCELLED",
                    StringFormat("label=%s ticket=#%I64u presumed cancelled "
                                 "(no pending order, no matching position).",
                                 g_records[i].label, g_records[i].ticket));
            }
         }
         else if(g_records[i].activated)
         {
            ObserveActivatedPosition(i, g_records[i].position_ticket, "TIMER_SCAN");
         }
      }

      g_cycles_waited++;

      if(InpVerboseScans)
         PLog("TIMER_CYCLE",
              StringFormat("cycle=%d / max=%d", g_cycles_waited, InpTimerCyclesMax));

      if(g_cycles_waited >= InpTimerCyclesMax && !AllRecordsDone())
      {
         PLog("TIMEOUT",
              StringFormat("Waited %d cycles without all orders activating. "
                           "Proceeding to cleanup.", g_cycles_waited));
         g_state = PROBE_CLEANUP;
         return;
      }

      if(AllRecordsDone())
      {
         PLog("ALL_DONE", "All probe records reached terminal state.");
         PrintFinalReport();
         g_state = PROBE_DONE;
      }
      return;
   }

   if(g_state == PROBE_CLEANUP)
   {
      CancelProbePendingOrders();
      PrintFinalReport();
      g_state = PROBE_DONE;
      return;
   }
   // PROBE_DONE — nothing to do
}

//+------------------------------------------------------------------+
//| OnTradeTransaction — primary event capture                      |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   g_txn_count++;

   PLog("TXN",
        StringFormat("seq=%I64u type=%s order=#%I64u deal=#%I64u "
                     "position=#%I64u sym=%s "
                     "price=%.5f price_sl=%.5f price_tp=%.5f vol=%.2f "
                     "req_magic=%d req_id=%u retcode=%u",
                     g_txn_count, EnumToString(trans.type),
                     trans.order, trans.deal, trans.position,
                     trans.symbol, trans.price,
                     trans.price_sl, trans.price_tp, trans.volume,
                     request.magic, result.request_id, result.retcode));

   if(g_state != PROBE_MONITORING && g_state != PROBE_PLACING) return;

   // Correlate transaction to probe records via order or position ticket
   int rec_idx = FindRecordByTicket(trans.order);
   if(rec_idx < 0 && trans.position > 0)
      rec_idx = FindRecordByTicket(trans.position);
   if(rec_idx < 0)
   {
      if(InpVerboseScans)
         PLog("TXN_UNRELATED",
              StringFormat("order=#%I64u not from this probe.", trans.order));
      return;
   }

   g_records[rec_idx].events_seen++;

   PLog("TXN_PROBE",
        StringFormat("label=%s type=%s order=#%I64u deal=#%I64u "
                     "position=#%I64u price_sl_t=%.5f price_tp_t=%.5f",
                     g_records[rec_idx].label, EnumToString(trans.type),
                     trans.order, trans.deal, trans.position,
                     trans.price_sl, trans.price_tp));

   if(trans.type == TRADE_TRANSACTION_ORDER_ADD)
   {
      PLog("ORDER_SERVER_CONFIRM",
           StringFormat("label=%s ticket=#%I64u confirmed on server.",
                        g_records[rec_idx].label, trans.order));
   }

   if(trans.type == TRADE_TRANSACTION_ORDER_UPDATE)
   {
      PLog("ORDER_SERVER_UPDATE",
           StringFormat("label=%s ticket=#%I64u updated.",
                        g_records[rec_idx].label, trans.order));
   }

   if(trans.type == TRADE_TRANSACTION_ORDER_DELETE)
   {
      PLog("ORDER_SERVER_DELETE",
           StringFormat("label=%s ticket=#%I64u deleted from pending list.",
                        g_records[rec_idx].label, trans.order));
      // Defer activation mark to DEAL_ADD (which follows and confirms execution)
   }

   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal > 0)
   {
      ulong pos_ticket = trans.position;
      PLog("DEAL_ADD",
           StringFormat("label=%s ticket=#%I64u deal=#%I64u pos_ticket=#%I64u "
                        "price=%.5f price_sl_trans=%.5f price_tp_trans=%.5f",
                        g_records[rec_idx].label, trans.order,
                        trans.deal, pos_ticket,
                        trans.price, trans.price_sl, trans.price_tp));

      if(!g_records[rec_idx].activated)
      {
         g_records[rec_idx].activated       = true;
         g_records[rec_idx].position_ticket = pos_ticket;
         // First reconcile right after deal — server authoritative
         ObserveActivatedPosition(rec_idx, pos_ticket, "DEAL_ADD");
      }
   }

   // POSITION event carries the updated SL/TP after server applies them
   if(trans.type == TRADE_TRANSACTION_POSITION)
   {
      ulong pos_ticket = trans.position;
      PLog("POSITION_EVENT",
           StringFormat("label=%s pos_ticket=#%I64u "
                        "price_sl_trans=%.5f price_tp_trans=%.5f",
                        g_records[rec_idx].label, pos_ticket,
                        trans.price_sl, trans.price_tp));
      ObserveActivatedPosition(rec_idx, pos_ticket, "POSITION_EVENT");
   }
}

//+------------------------------------------------------------------+
//| OnTick — additional reconciliation for first inventory capture  |
//+------------------------------------------------------------------+
void OnTick()
{
   if(g_state != PROBE_MONITORING) return;

   for(int i = 0; i < g_record_count; i++)
   {
      if(g_records[i].activated     &&
         g_records[i].position_ticket > 0 &&
         g_records[i].pos_sl_first < 0.0)
      {
         ObserveActivatedPosition(i, g_records[i].position_ticket, "TICK");
      }
   }
}
