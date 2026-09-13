//+------------------------------------------------------------------+
//|                                                account_probe.mq5 |
//|                                      W05 EXPERIMENTAL SPIKE      |
//|                                      NOT PRODUCTION CODE         |
//+------------------------------------------------------------------+
#property copyright "EddyTrader W05 Spike"
#property link      "https://github.com/eddytrader"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== [W05 EXPERIMENTAL SPIKE] ACCOUNT PROBE START ===");

   // 1. Investigacao de Tempo do Servidor (TECH-09)
   datetime t_curr = TimeCurrent();
   datetime t_srv  = TimeTradeServer();
   datetime t_loc  = TimeLocal();
   datetime t_gmt  = TimeGMT();
   PrintFormat("[TECH-09 TEMPO] TimeTradeServer(): %s (%lld) | TimeCurrent(): %s (%lld) | Delta: %d s",
               TimeToString(t_srv, TIME_DATE|TIME_SECONDS), (long)t_srv,
               TimeToString(t_curr, TIME_DATE|TIME_SECONDS), (long)t_curr,
               (int)(t_srv - t_curr));
   PrintFormat("[TECH-09 TEMPO] TimeLocal(): %s | TimeGMT(): %s | Servidor GMT-Offset est.: %d s (%.1f h)",
               TimeToString(t_loc, TIME_DATE|TIME_SECONDS),
               TimeToString(t_gmt, TIME_DATE|TIME_SECONDS),
               (int)(t_srv - t_gmt), (double)(t_srv - t_gmt) / 3600.0);

   // 2. Modo de Margem (TECH-06 / TECH-07)
   ENUM_ACCOUNT_MARGIN_MODE margin_mode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   string margin_name = "DESCONHECIDO";
   if(margin_mode == ACCOUNT_MARGIN_MODE_RETAIL_NETTING)  margin_name = "RETAIL_NETTING";
   if(margin_mode == ACCOUNT_MARGIN_MODE_EXCHANGE)        margin_name = "EXCHANGE";
   if(margin_mode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)  margin_name = "RETAIL_HEDGING";
   PrintFormat("[TECH-06/07 MARGEM] ACCOUNT_MARGIN_MODE: %s (%d)", margin_name, (int)margin_mode);

   // 3. Inventario Global de Posicoes Abertas (TECH-03 e TECH-11)
   int total_pos = PositionsTotal();
   PrintFormat("[TECH-03 POSICOES] Total de posicoes abertas: %d", total_pos);

   double F_total_profit = 0.0;
   double F_total_swap   = 0.0;
   double F_total_comm   = 0.0;

   for(int i = 0; i < total_pos; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
      {
         PrintFormat("  [AVISO] Falha ao obter ticket no indice %d (Erro: %d)", i, GetLastError());
         continue;
      }

      string sym      = PositionGetString(POSITION_SYMBOL);
      long type       = PositionGetInteger(POSITION_TYPE);
      double vol      = PositionGetDouble(POSITION_VOLUME);
      double price_op = PositionGetDouble(POSITION_PRICE_OPEN);
      double price_cur= PositionGetDouble(POSITION_PRICE_CURRENT);
      double profit   = PositionGetDouble(POSITION_PROFIT);
      double swap     = PositionGetDouble(POSITION_SWAP);
      long magic      = PositionGetInteger(POSITION_MAGIC);
      long pos_id     = PositionGetInteger(POSITION_IDENTIFIER);
      datetime t_op   = (datetime)PositionGetInteger(POSITION_TIME);

      F_total_profit += profit;
      F_total_swap   += swap;

      PrintFormat("  Pos[%d] Ticket: %I64u | ID: %I64u | Sym: %s | Type: %s | Vol: %.2f | Open: %.5f | Cur: %.5f | Profit: %.2f | Swap: %.2f | Magic: %I64d | OpenTime: %s",
                  i, ticket, pos_id, sym, (type == POSITION_TYPE_BUY ? "BUY" : "SELL"), vol, price_op, price_cur, profit, swap, magic,
                  TimeToString(t_op, TIME_DATE|TIME_SECONDS));
   }

   double F_consolidado = F_total_profit + F_total_swap;
   PrintFormat("[TECH-11 FLUTUANTE F(t)] Total Profit: %.2f | Total Swap: %.2f | F(t) Consolidado: %.2f",
               F_total_profit, F_total_swap, F_consolidado);
   PrintFormat("[TECH-11 CONFERENCIA] AccountInfoDouble(ACCOUNT_PROFIT): %.2f | Delta com F(t): %.2f",
               AccountInfoDouble(ACCOUNT_PROFIT),
               (AccountInfoDouble(ACCOUNT_PROFIT) - F_consolidado));

   // 4. Inventario Global de Ordens Pendentes (TECH-04)
   int total_orders = OrdersTotal();
   PrintFormat("[TECH-04 ORDENS] Total de ordens pendentes: %d", total_orders);

   for(int j = 0; j < total_orders; j++)
   {
      ulong order_ticket = OrderGetTicket(j);
      if(order_ticket == 0)
      {
         PrintFormat("  [AVISO] Falha ao obter ticket da ordem no indice %d (Erro: %d)", j, GetLastError());
         continue;
      }

      string o_sym     = OrderGetString(ORDER_SYMBOL);
      long o_type      = OrderGetInteger(ORDER_TYPE);
      double o_vol_init= OrderGetDouble(ORDER_VOLUME_INITIAL);
      double o_vol_cur = OrderGetDouble(ORDER_VOLUME_CURRENT);
      double o_price   = OrderGetDouble(ORDER_PRICE_OPEN);
      long o_magic     = OrderGetInteger(ORDER_MAGIC);
      datetime o_time  = (datetime)OrderGetInteger(ORDER_TIME_SETUP);

      PrintFormat("  Order[%d] Ticket: %I64u | Sym: %s | Type: %s (%d) | VolInit: %.2f | VolCur: %.2f | Price: %.5f | Magic: %I64d | Time: %s",
                  j, order_ticket, o_sym, EnumToString((ENUM_ORDER_TYPE)o_type), (int)o_type,
                  o_vol_init, o_vol_cur, o_price, o_magic, TimeToString(o_time, TIME_DATE|TIME_SECONDS));
   }

   Print("=== [W05 EXPERIMENTAL SPIKE] ACCOUNT PROBE COMPLETE ===");
}
//+------------------------------------------------------------------+
