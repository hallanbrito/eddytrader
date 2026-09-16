//+------------------------------------------------------------------+
//|                         test_pending_sl_baseline_w11.mq5        |
//|                                  Copyright 2026, EddyTrader Team |
//+------------------------------------------------------------------+
// RESEARCH ONLY — Pure classification tests for W11-DEC-02:
// "SL attached to pending order becomes first baseline when position
//  is created; no SL means WAIT_FIRST_SL."
//
// Does NOT open real orders, positions or trades.
// Does NOT depend on ACCOUNT_TRADE_MODE.
// Must compile and run cleanly: 0 errors, 0 warnings.
// All 8 cases must pass for the test to return INIT_SUCCEEDED.
//+------------------------------------------------------------------+
#property version "1.00"
#property description "Pure baseline classification tests for W11 pending order gate"
#property strict

int g_total  = 0;
int g_passed = 0;
int g_file   = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Replicate ClassifyFirstSL from probe_pending_order_gate_w11     |
//+------------------------------------------------------------------+
string ClassifyFirstSL(const double position_sl)
{
   return (position_sl > 0.0 ? "BASELINE_SET" : "WAIT_FIRST_SL");
}

//+------------------------------------------------------------------+
//| Assert helper                                                   |
//+------------------------------------------------------------------+
void Assert(const string id, const bool condition, const string detail = "")
{
   g_total++;
   if(condition) g_passed++;
   string status = (condition ? "PASS" : "FAIL");
   string msg    = StringFormat("[%s] %s%s", status, id,
                                (detail != "" ? " | " + detail : ""));
   Print(msg);
   if(g_file != INVALID_HANDLE) FileWriteString(g_file, msg + "\r\n");
}

//+------------------------------------------------------------------+
//| OnInit — runs all tests                                         |
//+------------------------------------------------------------------+
int OnInit()
{
   g_file = FileOpen("test_pending_sl_baseline_w11.txt",
                     FILE_WRITE|FILE_TXT|FILE_ANSI);

   // --- W11-BASE-01: position arrives with SL > 0 → BASELINE_SET
   Assert("W11-BASE-01 pos SL=1.34500 → BASELINE_SET",
          ClassifyFirstSL(1.34500) == "BASELINE_SET",
          StringFormat("got=%s", ClassifyFirstSL(1.34500)));

   // --- W11-BASE-02: position arrives with SL = 0 → WAIT_FIRST_SL
   Assert("W11-BASE-02 pos SL=0.00000 → WAIT_FIRST_SL",
          ClassifyFirstSL(0.0) == "WAIT_FIRST_SL",
          StringFormat("got=%s", ClassifyFirstSL(0.0)));

   // --- W11-BASE-03: BUY LIMIT activated with SL > 0 → BASELINE_SET
   // Simulates: pending BUY LIMIT had sl=1.34300, position arrives with sl=1.34300
   double buy_limit_sl = 1.34300;
   Assert("W11-BASE-03 BUY_LIMIT pos SL=1.34300 → BASELINE_SET",
          ClassifyFirstSL(buy_limit_sl) == "BASELINE_SET",
          StringFormat("got=%s", ClassifyFirstSL(buy_limit_sl)));

   // --- W11-BASE-04: SELL LIMIT activated with SL > 0 → BASELINE_SET
   double sell_limit_sl = 1.35200;
   Assert("W11-BASE-04 SELL_LIMIT pos SL=1.35200 → BASELINE_SET",
          ClassifyFirstSL(sell_limit_sl) == "BASELINE_SET",
          StringFormat("got=%s", ClassifyFirstSL(sell_limit_sl)));

   // --- W11-BASE-05: BUY STOP activated with SL > 0 → BASELINE_SET
   double buy_stop_sl = 1.34050;
   Assert("W11-BASE-05 BUY_STOP pos SL=1.34050 → BASELINE_SET",
          ClassifyFirstSL(buy_stop_sl) == "BASELINE_SET",
          StringFormat("got=%s", ClassifyFirstSL(buy_stop_sl)));

   // --- W11-BASE-06: SELL STOP activated with SL > 0 → BASELINE_SET
   double sell_stop_sl = 1.34750;
   Assert("W11-BASE-06 SELL_STOP pos SL=1.34750 → BASELINE_SET",
          ClassifyFirstSL(sell_stop_sl) == "BASELINE_SET",
          StringFormat("got=%s", ClassifyFirstSL(sell_stop_sl)));

   // --- W11-BASE-07: edge case — very small but positive SL → BASELINE_SET
   Assert("W11-BASE-07 SL=0.00001 (min positive) → BASELINE_SET",
          ClassifyFirstSL(0.00001) == "BASELINE_SET",
          StringFormat("got=%s", ClassifyFirstSL(0.00001)));

   // --- W11-BASE-08: negative SL (invalid) treated as WAIT_FIRST_SL
   // A negative value from server should not be treated as valid baseline.
   // ClassifyFirstSL only checks > 0.0, so negative → WAIT_FIRST_SL.
   Assert("W11-BASE-08 SL=-0.00001 (invalid/negative) → WAIT_FIRST_SL",
          ClassifyFirstSL(-0.00001) == "WAIT_FIRST_SL",
          StringFormat("got=%s", ClassifyFirstSL(-0.00001)));

   // Summary
   string summary = StringFormat("W11 pending SL baseline classification: %d/%d PASS",
                                 g_passed, g_total);
   Print(summary);
   if(g_file != INVALID_HANDLE)
   {
      FileWriteString(g_file, summary + "\r\n");
      FileClose(g_file);
      g_file = INVALID_HANDLE;
   }

   return (g_passed == g_total ? INIT_SUCCEEDED : INIT_FAILED);
}

//+------------------------------------------------------------------+
void OnTick() { ExpertRemove(); }
