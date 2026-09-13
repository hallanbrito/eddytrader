//+------------------------------------------------------------------+
//|                                            liquidation_probe.mq5 |
//|                                      W05 EXPERIMENTAL SPIKE      |
//|                                      NOT PRODUCTION CODE         |
//+------------------------------------------------------------------+
#property copyright "EddyTrader W05 Spike"
#property link      "https://github.com/eddytrader"
#property version   "1.00"

#include <Trade\Trade.mqh>

input bool InpExecuteRealClosure = false; // Se false, apenas simula inventario; se true, executa ordens

CTrade ExtTrade;

//+------------------------------------------------------------------+
//| Executa liquidacao compulsória e cancelamento global da conta    |
//+------------------------------------------------------------------+
void ExecuteGlobalLiquidation()
{
   Print("=== [TECH-05 / TECH-08] INICIO DE LIQUIDACAO COMPULSORIA GLOBAL ===");
   PrintFormat("InpExecuteRealClosure: %s | Account Trade Allowed: %s",
               InpExecuteRealClosure ? "TRUE" : "FALSE",
               MQLInfoInteger(MQL_TRADE_ALLOWED) ? "YES" : "NO");

   // Passo 1: Coleta estavel de tickets de posicoes abertas
   // IMPORTANTE: Coletar tickets em array antes de fechar para evitar deslocamento de indice
   int total_pos = PositionsTotal();
   ulong pos_tickets[];
   ArrayResize(pos_tickets, total_pos);
   int collected_pos = 0;

   for(int i = 0; i < total_pos; i++)
   {
      ulong t = PositionGetTicket(i);
      if(t > 0)
      {
         pos_tickets[collected_pos++] = t;
      }
   }
   ArrayResize(pos_tickets, collected_pos);
   PrintFormat("[INVENTARIO] Posicoes identificadas para encerramento: %d", collected_pos);

   int pos_closed_ok  = 0;
   int pos_failed     = 0;

   for(int i = 0; i < collected_pos; i++)
   {
      ulong t = pos_tickets[i];
      if(!PositionSelectByTicket(t))
      {
         PrintFormat("  [AVISO] Posicao %I64u ja inexistente ou nao selecionavel", t);
         continue;
      }

      string sym = PositionGetString(POSITION_SYMBOL);
      double vol = PositionGetDouble(POSITION_VOLUME);

      if(!InpExecuteRealClosure)
      {
         PrintFormat("  [DRY-RUN] Fechar Posicao Ticket: %I64u | Sym: %s | Vol: %.2f", t, sym, vol);
         pos_closed_ok++;
         continue;
      }

      // Execucao real de fechamento por TICKET
      ulong t_start = GetMicrosecondCount();
      bool res = ExtTrade.PositionClose(t);
      ulong t_end = GetMicrosecondCount();
      uint retcode = ExtTrade.ResultRetcode();
      string desc = ExtTrade.ResultRetcodeDescription();

      if(res && (retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL))
      {
         pos_closed_ok++;
         PrintFormat("  [SUCESSO] Fechada Posicao %I64u (%s) | Retcode: %u (%s) | Tempo: %I64u us",
                     t, sym, retcode, desc, (t_end - t_start));
      }
      else
      {
         pos_failed++;
         PrintFormat("  [FALHA ISOLADA] Erro ao fechar Posicao %I64u (%s) | Retcode: %u (%s) | Continua processamento!",
                     t, sym, retcode, desc);
         // RN-009: A falha individual NAO aborta o loop das demais posicoes
      }
   }

   // Passo 2: Coleta estavel e cancelamento de ordens pendentes
   int total_orders = OrdersTotal();
   ulong order_tickets[];
   ArrayResize(order_tickets, total_orders);
   int collected_orders = 0;

   for(int j = 0; j < total_orders; j++)
   {
      ulong ot = OrderGetTicket(j);
      if(ot > 0)
      {
         order_tickets[collected_orders++] = ot;
      }
   }
   ArrayResize(order_tickets, collected_orders);
   PrintFormat("[INVENTARIO] Ordens pendentes identificadas para cancelamento: %d", collected_orders);

   int orders_deleted_ok = 0;
   int orders_failed     = 0;

   for(int j = 0; j < collected_orders; j++)
   {
      ulong ot = order_tickets[j];
      if(!InpExecuteRealClosure)
      {
         PrintFormat("  [DRY-RUN] Cancelar Ordem Ticket: %I64u", ot);
         orders_deleted_ok++;
         continue;
      }

      ulong t_start = GetMicrosecondCount();
      bool del_res = ExtTrade.OrderDelete(ot);
      ulong t_end = GetMicrosecondCount();
      uint retcode = ExtTrade.ResultRetcode();
      string desc = ExtTrade.ResultRetcodeDescription();

      if(del_res && (retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL))
      {
         orders_deleted_ok++;
         PrintFormat("  [SUCESSO] Cancelada Ordem %I64u | Retcode: %u (%s) | Tempo: %I64u us",
                     ot, retcode, desc, (t_end - t_start));
      }
      else
      {
         orders_failed++;
         PrintFormat("  [FALHA ISOLADA] Erro ao cancelar Ordem %I64u | Retcode: %u (%s) | Continua processamento!",
                     ot, retcode, desc);
      }
   }

   // Passo 3: Avaliacao de Residuo e Estado Resultante (RN-009 / TECH-08)
   int remaining_pos    = PositionsTotal();
   int remaining_orders = OrdersTotal();

   Print("--- RESUMO DE EXECUCAO DA LIQUIDACAO ---");
   PrintFormat("Posicoes: %d fechadas com sucesso | %d com falha | %d remanescentes",
               pos_closed_ok, pos_failed, remaining_pos);
   PrintFormat("Ordens: %d canceladas com sucesso | %d com falha | %d remanescentes",
               orders_deleted_ok, orders_failed, remaining_orders);

   if(remaining_pos == 0 && remaining_orders == 0)
   {
      Print("[RESULTADO] EXPOSICAO ZERO (100% neutralizada) -> Autorizado transitar para BLOCKED!");
   }
   else
   {
      PrintFormat("[RESULTADO] EXPOSICAO RESIDUAL (%d posicoes, %d ordens) -> RETER ESTREITAMENTE EM LIQUIDATING E AGENDAR RETRY!",
                  remaining_pos, remaining_orders);
   }
   Print("=== [W05 EXPERIMENTAL SPIKE] LIQUIDATION PROBE COMPLETE ===");
}

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
   ExecuteGlobalLiquidation();
}
//+------------------------------------------------------------------+
