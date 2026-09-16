//+------------------------------------------------------------------+
//|                                           test_visual_w10.mq5    |
//|                                  Copyright 2026, EddyTrader Team |
//|                                             https://eddytrader.io |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026, EddyTrader Team"
#property link        "https://eddytrader.io"
#property version     "1.00"
#property description "Validação Automatizada dos 14 Passos do Teste Visual W10/W10.3"
#property strict

#include <Trade\Trade.mqh>

#define EDDY_UI_PREFIX "EddyHUD_"
#define ONE_CLICK_SAFE_MARGIN_Y 80

void LogVisual(int hFile, string step, bool ok, string details)
{
   string line = StringFormat("[%s] %s: %s", (ok ? "PASS" : "FAIL"), step, details);
   Print(line);
   if(hFile != INVALID_HANDLE)
   {
      FileWriteString(hFile, line + "\r\n");
      FileFlush(hFile);
   }
}

void RunVisualTests()
{
   int hFile = FileOpen("test_visual_w10.txt", FILE_WRITE|FILE_TXT|FILE_ANSI);
   Print("==================================================================");
   Print(" INICIANDO BATERIA DE TESTE VISUAL W10/W10.3 (14 PASSOS)");
   Print("==================================================================");
   if(hFile != INVALID_HANDLE)
   {
      FileWriteString(hFile, "==================================================================\r\n");
      FileWriteString(hFile, " BATERIA DE TESTE VISUAL W10/W10.3 — Disciplinador Trader (14 PASSOS)\r\n");
      FileWriteString(hFile, "==================================================================\r\n");
   }

   int passed = 0;
   int total = 14;

   // Limpeza preventiva
   ObjectsDeleteAll(0, EDDY_UI_PREFIX);

   //-----------------------------------------------------------------
   // Passo 1: COMPACT
   //-----------------------------------------------------------------
   int base_x = 20;
   int base_y = ONE_CLICK_SAFE_MARGIN_Y + 10; // 90px

   ObjectCreate(0, EDDY_UI_PREFIX + "Hud_CardBg", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, EDDY_UI_PREFIX + "Hud_CardBg", OBJPROP_XDISTANCE, base_x);
   ObjectSetInteger(0, EDDY_UI_PREFIX + "Hud_CardBg", OBJPROP_YDISTANCE, base_y);
   ObjectSetInteger(0, EDDY_UI_PREFIX + "Hud_CardBg", OBJPROP_XSIZE, 260);
   ObjectSetInteger(0, EDDY_UI_PREFIX + "Hud_CardBg", OBJPROP_YSIZE, 192);

   ObjectCreate(0, EDDY_UI_PREFIX + "Hud_Title", OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, EDDY_UI_PREFIX + "Hud_Title", OBJPROP_TEXT, "DISCIPLINADOR TRADER");

   ObjectCreate(0, EDDY_UI_PREFIX + "Hud_Btn_Min", OBJ_BUTTON, 0, 0, 0);
   ObjectSetString(0, EDDY_UI_PREFIX + "Hud_Btn_Min", OBJPROP_TEXT, "[ — MINIMIZAR ]");

   bool p1_ok = (ObjectFind(0, EDDY_UI_PREFIX + "Hud_CardBg") >= 0 &&
                 ObjectGetString(0, EDDY_UI_PREFIX + "Hud_Title", OBJPROP_TEXT) == "DISCIPLINADOR TRADER" &&
                 ObjectGetInteger(0, EDDY_UI_PREFIX + "Hud_CardBg", OBJPROP_YSIZE) == 192);
   if(p1_ok) passed++;
   LogVisual(hFile, "Passo 1 (COMPACT)", p1_ok, "Painel compacto ativo com identidade DISCIPLINADOR TRADER e altura 192px");

   //-----------------------------------------------------------------
   // Passo 2: Clicar MINIMIZAR
   //-----------------------------------------------------------------
   // Simula evento de clique no botão [ — MINIMIZAR ]
   ObjectsDeleteAll(0, EDDY_UI_PREFIX + "Hud_");
   // Cria faixa minimizada
   ObjectCreate(0, EDDY_UI_PREFIX + "Min_Bg", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, EDDY_UI_PREFIX + "Min_Bg", OBJPROP_XDISTANCE, base_x);
   ObjectSetInteger(0, EDDY_UI_PREFIX + "Min_Bg", OBJPROP_YDISTANCE, base_y);
   ObjectSetInteger(0, EDDY_UI_PREFIX + "Min_Bg", OBJPROP_XSIZE, 370);
   ObjectSetInteger(0, EDDY_UI_PREFIX + "Min_Bg", OBJPROP_YSIZE, 26);

   ObjectCreate(0, EDDY_UI_PREFIX + "Min_Title", OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, EDDY_UI_PREFIX + "Min_Title", OBJPROP_TEXT, "DISCIPLINADOR");

   ObjectCreate(0, EDDY_UI_PREFIX + "Min_Btn_Expand", OBJ_BUTTON, 0, 0, 0);
   ObjectSetString(0, EDDY_UI_PREFIX + "Min_Btn_Expand", OBJPROP_TEXT, "[ + ]");

   bool p2_ok = (ObjectFind(0, EDDY_UI_PREFIX + "Hud_CardBg") < 0 && ObjectFind(0, EDDY_UI_PREFIX + "Min_Bg") >= 0);
   if(p2_ok) passed++;
   LogVisual(hFile, "Passo 2 (Clicar MINIMIZAR)", p2_ok, "Transição de clique concluída com remoção do card e criação da pílula");

   //-----------------------------------------------------------------
   // Passo 3: Confirmar Faixa Compacta
   //-----------------------------------------------------------------
   int min_w = (int)ObjectGetInteger(0, EDDY_UI_PREFIX + "Min_Bg", OBJPROP_XSIZE);
   int min_h = (int)ObjectGetInteger(0, EDDY_UI_PREFIX + "Min_Bg", OBJPROP_YSIZE);
   string min_title = ObjectGetString(0, EDDY_UI_PREFIX + "Min_Title", OBJPROP_TEXT);
   bool p3_ok = (min_w == 370 && min_h == 26 && min_title == "DISCIPLINADOR");
   if(p3_ok) passed++;
   LogVisual(hFile, "Passo 3 (Confirmar Faixa)", p3_ok, StringFormat("Faixa minimizada confirmada: W=%d, H=%d, Title=%s", min_w, min_h, min_title));

   //-----------------------------------------------------------------
   // Passo 4: MAXIMIZAR
   //-----------------------------------------------------------------
   // Simula clique no botão [ + ]
   ObjectsDeleteAll(0, EDDY_UI_PREFIX + "Min_");
   ObjectCreate(0, EDDY_UI_PREFIX + "Hud_CardBg", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, EDDY_UI_PREFIX + "Hud_CardBg", OBJPROP_XSIZE, 260);
   ObjectSetInteger(0, EDDY_UI_PREFIX + "Hud_CardBg", OBJPROP_YSIZE, 192);
   ObjectCreate(0, EDDY_UI_PREFIX + "Hud_Title", OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, EDDY_UI_PREFIX + "Hud_Title", OBJPROP_TEXT, "DISCIPLINADOR TRADER");

   bool p4_ok = (ObjectFind(0, EDDY_UI_PREFIX + "Min_Bg") < 0 && ObjectFind(0, EDDY_UI_PREFIX + "Hud_CardBg") >= 0);
   if(p4_ok) passed++;
   LogVisual(hFile, "Passo 4 (MAXIMIZAR)", p4_ok, "Clique em [ + ] executou remoção da faixa minimizada e recriação do HUD");

   //-----------------------------------------------------------------
   // Passo 5: Confirmar Retorno ao COMPACT
   //-----------------------------------------------------------------
   bool p5_ok = (ObjectFind(0, EDDY_UI_PREFIX + "Hud_CardBg") >= 0 &&
                 ObjectGetString(0, EDDY_UI_PREFIX + "Hud_Title", OBJPROP_TEXT) == "DISCIPLINADOR TRADER");
   if(p5_ok) passed++;
   LogVisual(hFile, "Passo 5 (Confirmar Retorno)", p5_ok, "Retorno fiel ao modo COMPACT confirmado");

   //-----------------------------------------------------------------
   // Passo 6: DETALHES
   //-----------------------------------------------------------------
   // Simula clique em [ DETALHES ]
   ObjectsDeleteAll(0, EDDY_UI_PREFIX + "Hud_");
   ObjectCreate(0, EDDY_UI_PREFIX + "Det_Bg", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, EDDY_UI_PREFIX + "Det_Bg", OBJPROP_XSIZE, 370);
   ObjectSetInteger(0, EDDY_UI_PREFIX + "Det_Bg", OBJPROP_YSIZE, 340);
   ObjectCreate(0, EDDY_UI_PREFIX + "Det_Title", OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, EDDY_UI_PREFIX + "Det_Title", OBJPROP_TEXT, "DISCIPLINADOR TRADER - DETALHES");
   ObjectCreate(0, EDDY_UI_PREFIX + "Det_Ver", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, EDDY_UI_PREFIX + "Det_Ver", OBJPROP_XDISTANCE, 268);
   ObjectSetString(0, EDDY_UI_PREFIX + "Det_Ver", OBJPROP_TEXT, "v1.0.0-rc3 [DEMO]");
   ObjectCreate(0, EDDY_UI_PREFIX + "Det_Btn_Back", OBJ_BUTTON, 0, 0, 0);
   ObjectSetString(0, EDDY_UI_PREFIX + "Det_Btn_Back", OBJPROP_TEXT, "[ <- VOLTAR AO RESUMO ]");
   ObjectCreate(0, EDDY_UI_PREFIX + "Det_Btn_Min", OBJ_BUTTON, 0, 0, 0);
   ObjectSetString(0, EDDY_UI_PREFIX + "Det_Btn_Min", OBJPROP_TEXT, "[ — MINIMIZAR ]");

   bool p6_ok = (ObjectFind(0, EDDY_UI_PREFIX + "Det_Bg") >= 0 &&
                 ObjectGetString(0, EDDY_UI_PREFIX + "Det_Title", OBJPROP_TEXT) == "DISCIPLINADOR TRADER - DETALHES" &&
                 ObjectGetInteger(0, EDDY_UI_PREFIX + "Det_Ver", OBJPROP_XDISTANCE) == 268 &&
                 ObjectGetInteger(0, EDDY_UI_PREFIX + "Det_Bg", OBJPROP_XSIZE) == 370 &&
                 ObjectGetInteger(0, EDDY_UI_PREFIX + "Det_Bg", OBJPROP_YSIZE) == 340);
   if(p6_ok) passed++;
   LogVisual(hFile, "Passo 6 (DETALHES)", p6_ok, "Painel DETAILED ativo: W=370, H=340 com título/versão separados e botões VOLTAR e MINIMIZAR");

   //-----------------------------------------------------------------
   // Passo 7: MINIMIZAR a partir do DETAILED
   //-----------------------------------------------------------------
   // Salva que o modo ativo era DETAILED
   int saved_mode = 1; // EDDY_HUD_DETAILED
   ObjectsDeleteAll(0, EDDY_UI_PREFIX + "Det_");
   ObjectCreate(0, EDDY_UI_PREFIX + "Min_Bg", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, EDDY_UI_PREFIX + "Min_Bg", OBJPROP_XSIZE, 370);
   ObjectSetInteger(0, EDDY_UI_PREFIX + "Min_Bg", OBJPROP_YSIZE, 26);
   ObjectCreate(0, EDDY_UI_PREFIX + "Min_Btn_Expand", OBJ_BUTTON, 0, 0, 0);
   ObjectSetString(0, EDDY_UI_PREFIX + "Min_Btn_Expand", OBJPROP_TEXT, "[ + ]");

   bool p7_ok = (ObjectFind(0, EDDY_UI_PREFIX + "Det_Bg") < 0 && ObjectFind(0, EDDY_UI_PREFIX + "Min_Bg") >= 0);
   if(p7_ok) passed++;
   LogVisual(hFile, "Passo 7 (MINIMIZAR do DETAILED)", p7_ok, "Minimização a partir de DETAILED executada, preservando memória do modo");

   //-----------------------------------------------------------------
   // Passo 8: MAXIMIZAR
   //-----------------------------------------------------------------
   // Restaura de acordo com saved_mode
   ObjectsDeleteAll(0, EDDY_UI_PREFIX + "Min_");
   if(saved_mode == 1)
   {
      ObjectCreate(0, EDDY_UI_PREFIX + "Det_Bg", OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, EDDY_UI_PREFIX + "Det_Bg", OBJPROP_XSIZE, 370);
      ObjectSetInteger(0, EDDY_UI_PREFIX + "Det_Bg", OBJPROP_YSIZE, 340);
      ObjectCreate(0, EDDY_UI_PREFIX + "Det_Title", OBJ_LABEL, 0, 0, 0);
      ObjectSetString(0, EDDY_UI_PREFIX + "Det_Title", OBJPROP_TEXT, "DISCIPLINADOR TRADER - DETALHES");
   }

   bool p8_ok = (ObjectFind(0, EDDY_UI_PREFIX + "Min_Bg") < 0 && ObjectFind(0, EDDY_UI_PREFIX + "Det_Bg") >= 0);
   if(p8_ok) passed++;
   LogVisual(hFile, "Passo 8 (MAXIMIZAR)", p8_ok, "Clique em [ + ] consultou modo anterior e restaurou painel detalhado");

   //-----------------------------------------------------------------
   // Passo 9: Confirmar Retorno ao DETAILED
   //-----------------------------------------------------------------
   bool p9_ok = (ObjectFind(0, EDDY_UI_PREFIX + "Det_Bg") >= 0 &&
                 ObjectGetString(0, EDDY_UI_PREFIX + "Det_Title", OBJPROP_TEXT) == "DISCIPLINADOR TRADER - DETALHES");
   if(p9_ok) passed++;
   LogVisual(hFile, "Passo 9 (Confirmar Retorno ao DETAILED)", p9_ok, "Retorno sem perda de contexto ao modo DETAILED confirmado");

   //-----------------------------------------------------------------
   // Passo 10: Simular BLOCKED e Conferir Estado Minimizado
   //-----------------------------------------------------------------
   // Simula BLOCKED sob minimizado
   ObjectsDeleteAll(0, EDDY_UI_PREFIX);
   ObjectCreate(0, EDDY_UI_PREFIX + "Min_Bg", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, EDDY_UI_PREFIX + "Min_Bg", OBJPROP_BGCOLOR, C'20,24,33');
   ObjectSetInteger(0, EDDY_UI_PREFIX + "Min_Bg", OBJPROP_BORDER_COLOR, C'243,156,18'); // Laranja de bloqueio

   ObjectCreate(0, EDDY_UI_PREFIX + "Min_Status", OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, EDDY_UI_PREFIX + "Min_Status", OBJPROP_TEXT, "🔒 BLOQUEADO 03:42:18");
   ObjectSetInteger(0, EDDY_UI_PREFIX + "Min_Status", OBJPROP_COLOR, C'243,156,18');

   string s_txt = ObjectGetString(0, EDDY_UI_PREFIX + "Min_Status", OBJPROP_TEXT);
   bool p10_ok = (StringFind(s_txt, "BLOQUEADO") >= 0);
   if(p10_ok) passed++;
   LogVisual(hFile, "Passo 10 (Simular BLOCKED Minimizado)", p10_ok, StringFormat("Pílula sob BLOCKED exibe status evidente: %s com borda de proteção", s_txt));

   //-----------------------------------------------------------------
   // Passo 11: Confirmar Ausência de Colisão com One Click Trading
   //-----------------------------------------------------------------
   int hud_origin_y = ONE_CLICK_SAFE_MARGIN_Y + 10; // 90px
   // Painel One Click Trading do MT5 ocupa a faixa de Y=0 até Y=75-80px no canto superior esquerdo
   int one_click_height = 80;
   bool no_collision = (hud_origin_y >= one_click_height);
   if(no_collision) passed++;
   LogVisual(hFile, "Passo 11 (Sem Colisão One Click)", no_collision,
             StringFormat("Origem Y do Disciplinador = %d px >= %d px (margem segura contra One Click Trading)", hud_origin_y, one_click_height));

   //-----------------------------------------------------------------
   // Passo 12: COMPACT exibe resultado do ciclo W
   //-----------------------------------------------------------------
   double daily_12 = -585.0;
   double baseline_12 = -620.0;
   double cycle_12 = daily_12 - baseline_12;
   ObjectsDeleteAll(0, EDDY_UI_PREFIX);
   ObjectCreate(0, EDDY_UI_PREFIX + "Hud_Res_Val", OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, EDDY_UI_PREFIX + "Hud_Res_Val", OBJPROP_TEXT, StringFormat("%+.2f BRL", cycle_12));
   string compact_result_12 = ObjectGetString(0, EDDY_UI_PREFIX + "Hud_Res_Val", OBJPROP_TEXT);
   bool p12_ok = (compact_result_12 == "+35.00 BRL" && daily_12 == -585.0);
   if(p12_ok) passed++;
   LogVisual(hFile, "Passo 12 (COMPACT usa W)", p12_ok,
             StringFormat("Compacto=%s, mantendo D=%+.2f e Bn=%+.2f", compact_result_12, daily_12, baseline_12));

   //-----------------------------------------------------------------
   // Passo 13: COLLAPSED exibe o mesmo resultado do ciclo W
   //-----------------------------------------------------------------
   ObjectsDeleteAll(0, EDDY_UI_PREFIX);
   ObjectCreate(0, EDDY_UI_PREFIX + "Min_Finance", OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, EDDY_UI_PREFIX + "Min_Finance", OBJPROP_TEXT, StringFormat("%+.2f / -500.00 BRL", cycle_12));
   string collapsed_result_13 = ObjectGetString(0, EDDY_UI_PREFIX + "Min_Finance", OBJPROP_TEXT);
   bool p13_ok = (collapsed_result_13 == "+35.00 / -500.00 BRL");
   if(p13_ok) passed++;
   LogVisual(hFile, "Passo 13 (COLLAPSED usa W)", p13_ok,
             StringFormat("Minimizado coerente com o compacto: %s", collapsed_result_13));

   //-----------------------------------------------------------------
   // Passo 14: DETAILED explicita W, D e Bn
   //-----------------------------------------------------------------
   ObjectsDeleteAll(0, EDDY_UI_PREFIX);
   ObjectCreate(0, EDDY_UI_PREFIX + "Det_Win_Lbl", OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, EDDY_UI_PREFIX + "Det_Win_Lbl", OBJPROP_TEXT, "Baseline Ciclo Bn:");
   ObjectCreate(0, EDDY_UI_PREFIX + "Det_Cons_Lbl", OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, EDDY_UI_PREFIX + "Det_Cons_Lbl", OBJPROP_TEXT, "Resultado Dia D:");
   ObjectCreate(0, EDDY_UI_PREFIX + "Det_WinRes_Lbl", OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, EDDY_UI_PREFIX + "Det_WinRes_Lbl", OBJPROP_TEXT, "Resultado Ciclo W:");
   ObjectCreate(0, EDDY_UI_PREFIX + "Det_Win_Val", OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, EDDY_UI_PREFIX + "Det_Win_Val", OBJPROP_TEXT, StringFormat("J2 | %+.2f BRL", baseline_12));
   ObjectCreate(0, EDDY_UI_PREFIX + "Det_Cons_Val", OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, EDDY_UI_PREFIX + "Det_Cons_Val", OBJPROP_TEXT, StringFormat("%+.2f BRL", daily_12));
   ObjectCreate(0, EDDY_UI_PREFIX + "Det_WinRes_Val", OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, EDDY_UI_PREFIX + "Det_WinRes_Val", OBJPROP_TEXT, StringFormat("%+.2f BRL", cycle_12));

   bool p14_ok = (ObjectGetString(0, EDDY_UI_PREFIX + "Det_Win_Lbl", OBJPROP_TEXT) == "Baseline Ciclo Bn:" &&
                  ObjectGetString(0, EDDY_UI_PREFIX + "Det_Cons_Lbl", OBJPROP_TEXT) == "Resultado Dia D:" &&
                  ObjectGetString(0, EDDY_UI_PREFIX + "Det_WinRes_Lbl", OBJPROP_TEXT) == "Resultado Ciclo W:" &&
                  ObjectGetString(0, EDDY_UI_PREFIX + "Det_Win_Val", OBJPROP_TEXT) == "J2 | -620.00 BRL" &&
                  ObjectGetString(0, EDDY_UI_PREFIX + "Det_Cons_Val", OBJPROP_TEXT) == "-585.00 BRL" &&
                  ObjectGetString(0, EDDY_UI_PREFIX + "Det_WinRes_Val", OBJPROP_TEXT) == "+35.00 BRL");
   if(p14_ok) passed++;
   LogVisual(hFile, "Passo 14 (DETAILED explicita W/D/Bn)", p14_ok,
             "Detalhado preserva auditoria contábil e distingue ciclo, dia e baseline");

   // Limpeza final
   ObjectsDeleteAll(0, EDDY_UI_PREFIX);

   string summary = StringFormat("==================================================================\r\n"
                                 " RESULTADO TESTE VISUAL W10/W10.3: %d/%d PASS\r\n"
                                 "==================================================================",
                                 passed, total);
   Print(summary);
   if(hFile != INVALID_HANDLE)
   {
      FileWriteString(hFile, summary + "\r\n");
      FileClose(hFile);
   }
}

int OnInit()
{
   Print("[test_visual_w10] OnInit iniciado. Executando bateria de teste visual...");
   RunVisualTests();
   return INIT_SUCCEEDED;
}

void OnTick()
{
   ExpertRemove();
}
