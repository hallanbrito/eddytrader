//+------------------------------------------------------------------+
//|                                                history_probe.mq5 |
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
   Print("=== [W05 EXPERIMENTAL SPIKE] HISTORY PROBE START ===");

   datetime t_server = TimeTradeServer();
   MqlDateTime dt;
   TimeToStruct(t_server, dt);

   // Inicio do dia operacional: 00:00:00 do horario do servidor
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   datetime t_start_day = StructToTime(dt);

   PrintFormat("[TECH-10 / TECH-12] Janela Contabil Diaria: %s ate %s (Servidor)",
               TimeToString(t_start_day, TIME_DATE|TIME_SECONDS),
               TimeToString(t_server, TIME_DATE|TIME_SECONDS));

   // Seleciona historico do dia
   if(!HistorySelect(t_start_day, t_server))
   {
      PrintFormat("[ERRO] HistorySelect falhou! Codigo: %d", GetLastError());
      return;
   }

   int total_deals  = HistoryDealsTotal();
   int total_orders = HistoryOrdersTotal();
   PrintFormat("[HISTORICO NATIVO] Deals Total: %d | Orders Total: %d", total_deals, total_orders);

   double R_day_gross_profit = 0.0;
   double R_day_commission   = 0.0;
   double R_day_swap         = 0.0;
   double R_day_fee          = 0.0;

   double deposits_total     = 0.0;
   double withdrawals_total  = 0.0;
   double external_credits   = 0.0;

   int trade_deals_count   = 0;
   int balance_deals_count = 0;

   for(int i = 0; i < total_deals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      ENUM_DEAL_TYPE deal_type   = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
      ENUM_DEAL_ENTRY deal_entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      datetime deal_time         = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      string sym                 = HistoryDealGetString(ticket, DEAL_SYMBOL);
      double profit              = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      double commission          = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      double swap                = HistoryDealGetDouble(ticket, DEAL_SWAP);
      double fee                 = HistoryDealGetDouble(ticket, DEAL_FEE);
      string comment             = HistoryDealGetString(ticket, DEAL_COMMENT);
      long pos_id                = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);

      // Tratamento de Movimentacoes de Capital (INV-008: EXCLUIR)
      if(deal_type == DEAL_TYPE_BALANCE)
      {
         balance_deals_count++;
         if(profit > 0) deposits_total += profit;
         else           withdrawals_total += MathAbs(profit);

         PrintFormat("  [CAPITAL / BALANCE] Deal: %I64u | Time: %s | Valor: %.2f | Comment: '%s' (EXCLUIDO de R_day)",
                     ticket, TimeToString(deal_time, TIME_DATE|TIME_SECONDS), profit, comment);
         continue;
      }

      if(deal_type == DEAL_TYPE_CREDIT)
      {
         external_credits += profit;
         PrintFormat("  [CREDITO EXTERNO] Deal: %I64u | Time: %s | Valor: %.2f (EXCLUIDO de R_day)",
                     ticket, TimeToString(deal_time, TIME_DATE|TIME_SECONDS), profit);
         continue;
      }

      // Deals Operacionais de Trading
      if(deal_type == DEAL_TYPE_BUY || deal_type == DEAL_TYPE_SELL)
      {
         trade_deals_count++;

         // Nota sobre DEAL_ENTRY:
         // DEAL_ENTRY_IN: abertura (lucro geralmente 0.0, mas pode haver comissao/taxa)
         // DEAL_ENTRY_OUT / DEAL_ENTRY_INOUT: fechamento/reversao (lucro realizado da variacao de preco)
         R_day_gross_profit += profit;
         R_day_commission   += commission;
         R_day_swap         += swap;
         R_day_fee          += fee;

         PrintFormat("  [TRADE DEAL] Ticket: %I64u | PosID: %I64d | Entry: %s | Type: %s | Sym: %s | Profit: %.2f | Comm: %.2f | Swap: %.2f | Fee: %.2f | Time: %s",
                     ticket, pos_id, EnumToString(deal_entry), EnumToString(deal_type), sym,
                     profit, commission, swap, fee, TimeToString(deal_time, TIME_DATE|TIME_SECONDS));
      }
      else
      {
         // Outros tipos operacionais (ex: ajuste de comissao)
         PrintFormat("  [OUTRO DEAL TIPO %d] Ticket: %I64u | Profit: %.2f | Comm: %.2f | Comment: '%s'",
                     (int)deal_type, ticket, profit, commission, comment);
         R_day_commission += commission;
         R_day_gross_profit += profit;
      }
   }

   double R_day_net = R_day_gross_profit + R_day_commission + R_day_swap + R_day_fee;

   Print("--- RESUMO CONTABIL DO DIA (TECH-10 / INV-008 / INV-009) ---");
   PrintFormat("Deals de Trading: %d | Deals de Capital: %d", trade_deals_count, balance_deals_count);
   PrintFormat("Lucro/Prejuizo Bruto (Gross PnL): %.2f", R_day_gross_profit);
   PrintFormat("Comissoes de Trading: %.2f", R_day_commission);
   PrintFormat("Swaps Realizados: %.2f", R_day_swap);
   PrintFormat("Taxas / Fees: %.2f", R_day_fee);
   PrintFormat("-> R_day(t) RESULTADO LIQUIDO REALIZADO: %.2f", R_day_net);
   PrintFormat("Total Depositos (Excluidos): %.2f | Total Saques (Excluidos): %.2f", deposits_total, withdrawals_total);
   Print("=== [W05 EXPERIMENTAL SPIKE] HISTORY PROBE COMPLETE ===");
}
//+------------------------------------------------------------------+
