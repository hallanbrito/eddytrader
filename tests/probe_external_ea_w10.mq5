//+------------------------------------------------------------------+
//|                                       probe_external_ea_w10.mq5  |
//|                                  Copyright 2026, EddyTrader Team |
//|                                             https://eddytrader.io |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026, EddyTrader Team"
#property link        "https://eddytrader.io"
#property version     "1.00"
#property description "[LAB ONLY - COMPAT-01] Probe de Laboratório para Simulação de EA Externo (W10)"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Parâmetros de Entrada de Segurança Estrita                       |
//+------------------------------------------------------------------+
input group "=== SEGURANÇA E HOMOLOGAÇÃO DE LABORATÓRIO ==="
input bool   InpConfirmLabExecution = false;  // Confirmar Execução em Laboratório (Obrigatório true)
input ulong  InpProbeMagicNumber    = 777001; // Magic Number do EA Externo (Independente)
input double InpProbeVolume         = 0.01;   // Volume Mínimo de Teste (Lotes)
input ulong  InpProbeDeviation      = 10;     // Desvio / Slippage Máximo

//--- Objetos de Negociação e Estado
CTrade g_probe_trade;
#define PROBE_UI_PREFIX "ProbeEA_W10_"

//+------------------------------------------------------------------+
//| Primitivas de UI do Probe                                        |
//+------------------------------------------------------------------+
void Probe_CreateButton(const string name, int x, int y, int w, int h, const string text, color bg_clr, color text_clr)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg_clr);
   ObjectSetInteger(0, name, OBJPROP_COLOR, text_clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI");
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
}

void Probe_CreateLabel(const string name, int x, int y, const string text, color clr)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI");
}

void Probe_RenderUI()
{
   Probe_CreateLabel(PROBE_UI_PREFIX + "Title", 220, 15, "PROBE EA EXTERNO (W10 LAB ONLY)", C'255,165,0');
   Probe_CreateLabel(PROBE_UI_PREFIX + "Info",  220, 32, StringFormat("Magic: %I64u | Vol: %.2f", InpProbeMagicNumber, InpProbeVolume), clrWhite);
   Probe_CreateButton(PROBE_UI_PREFIX + "Btn_Buy",   220, 52, 210, 24, "[ EXECUTAR BUY 0.01 ]", C'39,174,96', clrWhite);
   Probe_CreateButton(PROBE_UI_PREFIX + "Btn_Limit", 220, 80, 210, 24, "[ CRIAR BUY LIMIT ]", C'0,122,204', clrWhite);
   Probe_CreateButton(PROBE_UI_PREFIX + "Btn_Clean", 220, 108, 210, 24, "[ CANCELAR TESTES ]", C'70,75,85', clrWhite);
   ChartRedraw(0);
}

void Probe_DeleteUI()
{
   ObjectsDeleteAll(0, PROBE_UI_PREFIX);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Inicialização do Probe                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("[PROBE W10][INFO] ==================================================");
   Print("[PROBE W10][INFO] Inicializando Probe Externo de Homologação (COMPAT-01)");
   Print("[PROBE W10][INFO] Finalidade: Simular ordens/posições de outro EA em gráfico separado");
   Print("[PROBE W10][INFO] ==================================================");

   // 1. Salvaguarda Inegociável: Recusa Terminante em Conta REAL
   ENUM_ACCOUNT_TRADE_MODE mode = (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(mode != ACCOUNT_TRADE_MODE_DEMO)
   {
      Print("[PROBE W10][CRITICAL] EXECUCAO VETADA EM CONTA REAL! Este probe e exclusivo para laboratório DEMO.");
      return INIT_FAILED;
   }

   // 2. Salvaguarda de Consentimento Explícito
   if(!InpConfirmLabExecution)
   {
      Print("[PROBE W10][ERROR] Execução abortada: Parâmetro InpConfirmLabExecution deve ser explicitamente TRUE.");
      return INIT_PARAMETERS_INCORRECT;
   }

   // 3. Configuração do CTrade
   g_probe_trade.SetExpertMagicNumber(InpProbeMagicNumber);
   g_probe_trade.SetDeviationInPoints(InpProbeDeviation);

   // 4. Renderização dos controles manuais on-chart (NENHUMA ordem é disparada no OnInit)
   Probe_RenderUI();

   PrintFormat("[PROBE W10][INFO] Probe carregado com segurança. Magic=#%I64u, Símbolo=%s. Aguardando comando interativo.",
               InpProbeMagicNumber, _Symbol);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Desinicialização                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Probe_DeleteUI();
   PrintFormat("[PROBE W10][INFO] Probe descarregado do gráfico. Razão: %d", reason);
}

//+------------------------------------------------------------------+
//| Tratamento de Eventos de Gráfico (Ações Manuais sob Demanda)     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   // 1. Abrir Posição a Mercado de Teste
   if(sparam == PROBE_UI_PREFIX + "Btn_Buy")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      PrintFormat("[PROBE W10][ACTION] Enviando BUY de teste: Vol=%.2f, Sym=%s, Ask=%.5f, Magic=#%I64u",
                  InpProbeVolume, _Symbol, ask, InpProbeMagicNumber);

      ResetLastError();
      if(g_probe_trade.Buy(InpProbeVolume, _Symbol, ask, 0.0, 0.0, "COMPAT-01 Probe Buy"))
      {
         PrintFormat("[PROBE W10][SUCCESS] Posição aberta com sucesso! Ticket=#%I64u, Deal=#%I64u",
                     g_probe_trade.ResultOrder(), g_probe_trade.ResultDeal());
      }
      else
      {
         PrintFormat("[PROBE W10][ERROR] Falha ao abrir compra de teste! Retcode=%u (%s), LastError=%d",
                     g_probe_trade.ResultRetcode(), g_probe_trade.ResultRetcodeDescription(), GetLastError());
      }
      return;
   }

   // 2. Criar Ordem Pendente de Teste
   if(sparam == PROBE_UI_PREFIX + "Btn_Limit")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double limit_price = bid - (100.0 * point); // 100 pontos abaixo do mercado

      PrintFormat("[PROBE W10][ACTION] Enviando BUY LIMIT de teste: Vol=%.2f, Sym=%s, Preço=%.5f, Magic=#%I64u",
                  InpProbeVolume, _Symbol, limit_price, InpProbeMagicNumber);

      ResetLastError();
      if(g_probe_trade.BuyLimit(InpProbeVolume, limit_price, _Symbol, 0.0, 0.0, ORDER_TIME_GTC, 0, "COMPAT-01 Probe Limit"))
      {
         PrintFormat("[PROBE W10][SUCCESS] Ordem pendente criada com sucesso! Ticket=#%I64u",
                     g_probe_trade.ResultOrder());
      }
      else
      {
         PrintFormat("[PROBE W10][ERROR] Falha ao criar Buy Limit! Retcode=%u (%s), LastError=%d",
                     g_probe_trade.ResultRetcode(), g_probe_trade.ResultRetcodeDescription(), GetLastError());
      }
      return;
   }

   // 3. Limpar Ordens Pendentes do Probe
   if(sparam == PROBE_UI_PREFIX + "Btn_Clean")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      Print("[PROBE W10][ACTION] Limpando ordens pendentes do Magic #777001...");
      int total = OrdersTotal();
      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket > 0 && OrderGetInteger(ORDER_MAGIC) == InpProbeMagicNumber)
         {
            g_probe_trade.OrderDelete(ticket);
            PrintFormat("[PROBE W10][INFO] Ordem pendente de laboratório #%I64u cancelada.", ticket);
         }
      }
      return;
   }
}
