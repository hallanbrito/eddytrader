//+------------------------------------------------------------------+
//|                                      test_sl_monotonic_w11.mq5   |
//+------------------------------------------------------------------+
#property version "1.00"
#property description "Pure classification tests for W11 SL monotonicity"
#property strict

int g_total = 0;
int g_passed = 0;
int g_file = INVALID_HANDLE;

string Classify(const int direction,
                const double locked_sl,
                const double new_sl,
                const double tick_size)
{
   double tolerance = (tick_size > 0.0 ? tick_size * 0.5 : 1e-10);
   if(locked_sl != 0.0 && new_sl == 0.0) return "VIOLATION_REMOVAL";
   if(locked_sl == 0.0 && new_sl != 0.0) return "BASELINE_SET";
   if(MathAbs(new_sl - locked_sl) < tolerance) return "NO_CHANGE";
   if(direction == POSITION_TYPE_BUY)
      return (new_sl < locked_sl ? "VIOLATION_WIDENING" : "IMPROVEMENT_TIGHTENING");
   return (new_sl > locked_sl ? "VIOLATION_WIDENING" : "IMPROVEMENT_TIGHTENING");
}

void AssertCase(const string id, const bool condition)
{
   g_total++;
   if(condition) g_passed++;
   string line = StringFormat("[%s] %s", (condition ? "PASS" : "FAIL"), id);
   Print(line);
   if(g_file != INVALID_HANDLE) FileWriteString(g_file, line + "\r\n");
}

int OnInit()
{
   g_file = FileOpen("test_sl_monotonic_w11.txt", FILE_WRITE|FILE_TXT|FILE_ANSI);
   AssertCase("W11-MATH-01 BUY tightening", Classify(POSITION_TYPE_BUY, 1.1000, 1.1010, 0.0001) == "IMPROVEMENT_TIGHTENING");
   AssertCase("W11-MATH-02 BUY widening", Classify(POSITION_TYPE_BUY, 1.1000, 1.0990, 0.0001) == "VIOLATION_WIDENING");
   AssertCase("W11-MATH-03 SELL tightening", Classify(POSITION_TYPE_SELL, 1.1000, 1.0990, 0.0001) == "IMPROVEMENT_TIGHTENING");
   AssertCase("W11-MATH-04 SELL widening", Classify(POSITION_TYPE_SELL, 1.1000, 1.1010, 0.0001) == "VIOLATION_WIDENING");
   AssertCase("W11-MATH-05 removal", Classify(POSITION_TYPE_BUY, 1.1000, 0.0, 0.0001) == "VIOLATION_REMOVAL");
   AssertCase("W11-MATH-06 first SL", Classify(POSITION_TYPE_BUY, 0.0, 1.1000, 0.0001) == "BASELINE_SET");
   AssertCase("W11-MATH-07 tick noise", Classify(POSITION_TYPE_BUY, 1.10000, 1.10004, 0.0001) == "NO_CHANGE");

   string summary = StringFormat("W11 SL monotonic classification: %d/%d PASS", g_passed, g_total);
   Print(summary);
   if(g_file != INVALID_HANDLE)
   {
      FileWriteString(g_file, summary + "\r\n");
      FileClose(g_file);
      g_file = INVALID_HANDLE;
   }
   return (g_passed == g_total ? INIT_SUCCEEDED : INIT_FAILED);
}

void OnTick()
{
   ExpertRemove();
}
