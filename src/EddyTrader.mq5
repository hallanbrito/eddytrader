//+------------------------------------------------------------------+
//|                                                   EddyTrader.mq5 |
//|                                  Copyright 2026, EddyTrader Team |
//|                                             https://eddytrader.io |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026, EddyTrader Team"
#property link        "https://eddytrader.io"
#property version     "1.00"
#property description "Disciplinador Trader 1.0.0-rc3 - Núcleo Autônomo de Proteção de Capital e Gerenciador de Perda Diária"
#property strict

//--- Definições Formais do Produto e Versão
#define EDDY_PRODUCT_NAME "Disciplinador Trader"
#define EDDY_VERSION      "1.0.0-rc3"
#define EDDY_PURPOSE      "Guardião de Disciplina Operacional e Limite de Perda Diária (MQL5 Nativo)"

//--- Definições de Interface Gráfica (HUD)
#define EDDY_UI_PREFIX "EddyHUD_"

enum ENUM_EDDY_HUD_MODE
{
   EDDY_HUD_COMPACT   = 0, // Painel Compacto Trader (Interativo, no Gráfico)
   EDDY_HUD_DETAILED  = 1, // Painel Técnico Detalhado (Auditoria / Engenharia)
   EDDY_HUD_OFF       = 2  // HUD Desativado (Sem elementos no gráfico)
};

enum ENUM_DISCIPLINADOR_PANEL_STATE
{
   PANEL_EXPANDED  = 0, // HUD Aberto (Compacto ou Detalhado)
   PANEL_COLLAPSED = 1  // HUD Minimizado (Faixa Discreta / Pílula no Gráfico)
};

enum ENUM_CONFIG_UI_STATE
{
   UI_STATE_IDLE       = 0, // Exibição normal do painel compacto
   UI_STATE_EDITING    = 1, // Modal de edição de limite aberta
   UI_STATE_CONFIRMING = 2  // Modal de confirmação da alteração
};

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Parâmetros de Entrada (Inputs Mínimos Normativos)                |
//+------------------------------------------------------------------+
input group "=== Configurações de Risco ==="
input double InpMaxLoss            = 500.0; // Perda Máxima Inicial Padrão (Moeda da Conta, > 0.0)
input int    InpBlockDurationHours = 4;     // Duração Contínua do Bloqueio (Horas, 1 a 168h)

input group "=== Interface e Painel (UX) ==="
input ENUM_EDDY_HUD_MODE InpHudMode    = EDDY_HUD_COMPACT;       // Modo Visual do Painel
input ENUM_BASE_CORNER   InpHudCorner  = CORNER_LEFT_UPPER;      // Canto do Gráfico
input int                InpHudOffsetX = 20;                     // Distância Horizontal (X) em Pixels
input int                InpHudOffsetY = 10;                     // Distância Vertical Adicional (Y) em Pixels

input group "=== Configurações Operacionais ==="
input int    InpTimerIntervalMs    = 500;   // Intervalo de Varredura do Timer (Milissegundos, 50 a 5000)
input ulong  InpDeviationPoints    = 10;    // Desvio Máximo / Slippage Tolerado (Pontos, 0 a 500)

//+------------------------------------------------------------------+
//| Estados Operacionais da FSM (W04 / ADR 0004)                     |
//+------------------------------------------------------------------+
enum ENUM_EDDY_STATE
{
   EDDY_STATE_INIT                 = 0, // Inicialização e Reconstituição de Estado
   EDDY_STATE_MONITORING           = 1, // Vigilância Ativa de Risco
   EDDY_STATE_PROTECTION_TRIGGERED = 2, // Congelamento e Formalização do Gatilho
   EDDY_STATE_LIQUIDATING          = 3, // Contenção e Liquidação Compulsória Global
   EDDY_STATE_BLOCKED              = 4, // Bloqueio Temporal e Manutenção da Proteção
   EDDY_STATE_REOPENING            = 5  // Reabertura Controlada e Nova Baseline
};

//+------------------------------------------------------------------+
//| Estrutura de Estado Recuperável (ADR 0004 / ADR 0005)            |
//+------------------------------------------------------------------+
struct EddyRecoveryState
{
   ENUM_EDDY_STATE state;
   int             window_id;
   double          baseline;
   datetime        t_trigger;
   datetime        t_unlock;
   ulong           protection_event_id;
   datetime        day_timestamp;
};

//+------------------------------------------------------------------+
//| Variáveis Globais de Estado Operacional e Interface              |
//+------------------------------------------------------------------+
ENUM_EDDY_STATE      g_current_state          = EDDY_STATE_INIT;
int                  g_window_id              = 0;
double               g_baseline               = 0.0;
datetime             g_t_trigger              = 0;
datetime             g_t_unlock               = 0;
ulong                g_protection_event_id    = 0;
datetime             g_day_start              = 0;
bool                 g_safe_to_operate        = false;

// Estado mutável do limite de perda e painel UX
double                         g_max_loss               = 500.0;
ENUM_EDDY_HUD_MODE             g_hud_mode               = EDDY_HUD_COMPACT;
ENUM_EDDY_HUD_MODE             g_last_expanded_hud_mode = EDDY_HUD_COMPACT;
ENUM_DISCIPLINADOR_PANEL_STATE g_panel_state            = PANEL_EXPANDED;
ENUM_CONFIG_UI_STATE           g_config_ui_state        = UI_STATE_IDLE;
double                         g_pending_max_loss       = 0.0;
string                         g_config_feedback_msg    = "";
datetime                       g_config_feedback_expiry = 0;
string                         g_config_error_msg       = "";

ulong                g_account_login          = 0;
ulong                g_instance_id            = 0;
bool                 g_is_owner               = false;
CTrade               g_trade;

//+------------------------------------------------------------------+
//| Funções Auxiliares de Tempo e Servidor                           |
//+------------------------------------------------------------------+
datetime GetServerTimeSafe()
{
   datetime t = TimeTradeServer();
   if(t <= 0)
      t = TimeCurrent();
   return t;
}

datetime GetDayStart(datetime t)
{
   if(t <= 0)
      t = GetServerTimeSafe();
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt);
}

ulong GenerateProtectionEventId(datetime t_trigger)
{
   return ((ulong)t_trigger * 1000) + ((ulong)GetTickCount() % 1000);
}

//+------------------------------------------------------------------+
//| Persistência em Terminal Global Variables (ADR 0005 / GAP-005)   |
//+------------------------------------------------------------------+
string GVKey(const string suffix)
{
   return StringFormat("EDDY_%I64u_%s", g_account_login, suffix);
}

string GVConfigKey(const string suffix)
{
   return StringFormat("EDDY_%I64u_CONFIG_%s", g_account_login, suffix);
}

bool PersistState()
{
   ResetLastError();
   bool ok = true;
   if(GlobalVariableSet(GVKey("STATE"), (double)g_current_state) == 0 && GetLastError() != 0) ok = false;
   if(GlobalVariableSet(GVKey("WINDOW_ID"), (double)g_window_id) == 0 && GetLastError() != 0) ok = false;
   if(GlobalVariableSet(GVKey("BASELINE"), g_baseline) == 0 && GetLastError() != 0) ok = false;
   if(GlobalVariableSet(GVKey("T_TRIGGER"), (double)g_t_trigger) == 0 && GetLastError() != 0) ok = false;
   if(GlobalVariableSet(GVKey("T_UNLOCK"), (double)g_t_unlock) == 0 && GetLastError() != 0) ok = false;
   if(GlobalVariableSet(GVKey("EVENT_ID"), (double)g_protection_event_id) == 0 && GetLastError() != 0) ok = false;
   if(GlobalVariableSet(GVKey("DAY"), (double)g_day_start) == 0 && GetLastError() != 0) ok = false;
   GlobalVariablesFlush();

   if(!ok)
   {
      PrintFormat("[EddyTrader][CRITICAL] Falha na persistência de variáveis globais! Erro MT5: %d", GetLastError());
      g_safe_to_operate = false;
   }
   return ok;
}

bool LoadState(EddyRecoveryState &state)
{
   if(!GlobalVariableCheck(GVKey("STATE")))
      return false;

   state.state               = (ENUM_EDDY_STATE)(int)GlobalVariableGet(GVKey("STATE"));
   state.window_id           = (int)GlobalVariableGet(GVKey("WINDOW_ID"));
   state.baseline            = GlobalVariableGet(GVKey("BASELINE"));
   state.t_trigger           = (datetime)GlobalVariableGet(GVKey("T_TRIGGER"));
   state.t_unlock            = (datetime)GlobalVariableGet(GVKey("T_UNLOCK"));
   state.protection_event_id = (ulong)GlobalVariableGet(GVKey("EVENT_ID"));
   state.day_timestamp       = (datetime)GlobalVariableGet(GVKey("DAY"));
   return true;
}

// NOTA ADMINISTRATIVA: ClearState é um utilitário exclusivo para manutenção manual
// ou limpeza em ambiente de laboratório. O EddyTrader JAMAIS invoca esta função
// automaticamente em OnDeinit, reinicialização ou troca de perfil.
void ClearState()
{
   GlobalVariableDel(GVKey("STATE"));
   GlobalVariableDel(GVKey("WINDOW_ID"));
   GlobalVariableDel(GVKey("BASELINE"));
   GlobalVariableDel(GVKey("T_TRIGGER"));
   GlobalVariableDel(GVKey("T_UNLOCK"));
   GlobalVariableDel(GVKey("EVENT_ID"));
   GlobalVariableDel(GVKey("DAY"));
   GlobalVariablesFlush();
}

//+------------------------------------------------------------------+
//| Proteção Contra Múltiplas Instâncias: OWNER + HEARTBEAT LEASE    |
//+------------------------------------------------------------------+
const int INSTANCE_LEASE_TIMEOUT_SECONDS = 15;

ulong GenerateInstanceId()
{
   datetime now = TimeCurrent();
   if(now <= 0) now = TimeLocal();
   uint tick = (uint)GetTickCount();
   uint chart = (uint)(ChartID() & 0xFFFFFF);
   return ((ulong)now * 1000000ULL) + ((ulong)(tick ^ chart) % 1000000ULL);
}

bool AcquireInstanceGuard()
{
   if(g_instance_id == 0)
      g_instance_id = GenerateInstanceId();

   string owner_key = GVKey("INSTANCE_OWNER");
   string hb_key    = GVKey("HEARTBEAT");
   datetime now     = TimeCurrent();

   // 1. Bootstrap: se a chave de owner ainda não existe na conta, cria com valor neutro 0 (sem proprietário).
   // Como todas as instâncias escrevem o mesmo valor neutro 0, nenhuma adquire posse neste passo.
   if(!GlobalVariableCheck(owner_key))
   {
      GlobalVariableSet(owner_key, 0.0);
      GlobalVariablesFlush();
   }

   ulong current_owner = (ulong)GlobalVariableGet(owner_key);

   // 2. Mesma instância readquirindo (ex: recarga / troca de timeframe)
   if(current_owner == g_instance_id && g_instance_id != 0)
   {
      GlobalVariableSet(hb_key, (double)now);
      GlobalVariablesFlush();
      g_is_owner = true;
      return true;
   }

   // 3. Caso OWNER == 0: guarda livre (sem proprietário).
   // O heartbeat antigo é ignorado (sem efeito semântico quando OWNER==0).
   // Aquisição inicial puramente atômica via CAS: 0 -> g_instance_id
   if(current_owner == 0)
   {
      if(GlobalVariableSetOnCondition(owner_key, (double)g_instance_id, 0.0))
      {
         // Sucesso exclusivo no CAS: concede ownership
         GlobalVariableSet(hb_key, (double)now);
         GlobalVariablesFlush();
         g_is_owner = true;
         PrintFormat("[EddyTrader][INFO] Guarda adquirida com sucesso via CAS (0 -> Owner=#%I64u) na conta %I64u",
                     g_instance_id, g_account_login);
         return true;
      }
      // Se CAS falhou, outra instância concorrente venceu a disputa atômica.
      current_owner = (ulong)GlobalVariableGet(owner_key);
   }

   // 4. Caso OWNER != 0 e OWNER != g_instance_id: outro proprietário registrado
   if(current_owner != 0 && current_owner != g_instance_id)
   {
      // Avalia a validade temporal da lease
      if(GlobalVariableCheck(hb_key))
      {
         datetime last_hb = (datetime)GlobalVariableGet(hb_key);
         if(last_hb > 0 && now >= last_hb && (now - last_hb) <= INSTANCE_LEASE_TIMEOUT_SECONDS)
         {
            // Lease ativa e recente de outro proprietário legítimo: rejeição obrigatória
            PrintFormat("[EddyTrader][ERROR] Instância concorrente ativa detectada na conta %I64u (Owner=#%I64u, heartbeat há %d s <= limite %d s). Abortando carga.",
                        g_account_login, current_owner, (int)(now - last_hb), INSTANCE_LEASE_TIMEOUT_SECONDS);
            g_is_owner = false;
            return false;
         }
      }
      else
      {
         // Fail-safe: OWNER != 0 com HEARTBEAT inexistente é tratado como lease inconsistente
         PrintFormat("[EddyTrader][WARN] OWNER=#%I64u ativo com HEARTBEAT ausente. Tratando como lease inconsistente.",
                     current_owner);
      }

      // Heartbeat expirado (> 15s) ou lease inconsistente: tentativa de takeover atômico via CAS (current_owner -> g_instance_id)
      PrintFormat("[EddyTrader][INFO] Lease da instância anterior (#%I64u) expirada (>%d s). Tentando takeover atômico...",
                  current_owner, INSTANCE_LEASE_TIMEOUT_SECONDS);

      if(GlobalVariableSetOnCondition(owner_key, (double)g_instance_id, (double)current_owner))
      {
         // Takeover atômico bem-sucedido: grava imediatamente o novo heartbeat
         GlobalVariableSet(hb_key, (double)now);
         GlobalVariablesFlush();
         g_is_owner = true;
         PrintFormat("[EddyTrader][INFO] Takeover de guarda concluído via CAS! (#%I64u -> Novo Owner=#%I64u) na conta %I64u",
                     current_owner, g_instance_id, g_account_login);
         return true;
      }
      else
      {
         // Conflito no takeover: outra instância assumiu ou o proprietário mudou
         PrintFormat("[EddyTrader][ERROR] Conflito no takeover da guarda. Outra instância assumiu ownership. Abortando carga.");
         g_is_owner = false;
         return false;
      }
   }

   g_is_owner = false;
   return false;
}

void UpdateHeartbeat()
{
   if(!g_is_owner)
      return;

   string owner_key = GVKey("INSTANCE_OWNER");
   if(!GlobalVariableCheck(owner_key) || (ulong)GlobalVariableGet(owner_key) != g_instance_id)
   {
      // PERDA DE OWNERSHIP DETECTADA (Takeover ocorreu) -> FAIL-CLOSED
      PrintFormat("[EddyTrader][CRITICAL] Perda de ownership detectada na instância #%I64u! Outra instância assumiu o controle. Entrando em FAIL-CLOSED.",
                  g_instance_id);
      g_is_owner        = false;
      g_safe_to_operate = false;
      g_current_state   = EDDY_STATE_INIT;
      EventKillTimer();
      // Invariante de contenção: não encerra posições, não altera FSM da conta e não altera o lock de terceiros
      return;
   }

   GlobalVariableSet(GVKey("HEARTBEAT"), (double)TimeCurrent());
}

void ReleaseInstanceGuard()
{
   // REGRA DE SEGURANÇA: Somente se a instância foi marcada como proprietária
   if(!g_is_owner)
   {
      PrintFormat("[EddyTrader][INFO] OnDeinit: Instância #%I64u NÃO é proprietária do lock. Guarda preservada intacta.",
                  g_instance_id);
      return;
   }

   string owner_key = GVKey("INSTANCE_OWNER");

   // Liberação estritamente atômica via CAS: minha_instancia -> 0
   if(GlobalVariableSetOnCondition(owner_key, 0.0, (double)g_instance_id))
   {
      GlobalVariablesFlush();
      PrintFormat("[EddyTrader][INFO] Guarda liberada com sucesso via CAS (Owner=#%I64u -> 0).",
                  g_instance_id);
   }
   else
   {
      // Falha no CAS: ownership já havia sido perdida (ex: takeover ocorrido antes do OnDeinit)
      PrintFormat("[EddyTrader][WARN] OnDeinit: Falha no CAS de liberação. Instância #%I64u já não possuía a titularidade do lock. Nenhuma metadata alterada.",
                  g_instance_id);
   }

   g_is_owner = false;
   // INVARIANTE CRÍTICO: NÃO apagar a chave HEARTBEAT.
   // Deixar o último heartbeat persistido elimina a corrida onde o antigo dono apaga o heartbeat do novo dono.
   // Como OWNER == 0, o heartbeat é semanticamente irrelevante e o próximo adquirente o sobrescreverá.
}

//+------------------------------------------------------------------+
//| Cálculos Financeiros Normativos (W03 / ADR 0002 / ADR 0003)      |
//+------------------------------------------------------------------+
double CalculateRealizedResultToday(datetime t_start_day, datetime t_now)
{
   if(t_now <= 0) t_now = GetServerTimeSafe();
   if(t_start_day <= 0) t_start_day = GetDayStart(t_now);

   if(!HistorySelect(t_start_day, t_now))
   {
      PrintFormat("[EddyTrader][WARN] HistorySelect(%s, %s) falhou. Erro: %d",
                  TimeToString(t_start_day, TIME_DATE|TIME_SECONDS),
                  TimeToString(t_now, TIME_DATE|TIME_SECONDS),
                  GetLastError());
      return 0.0;
   }

   double realized = 0.0;
   int total_deals = HistoryDealsTotal();
   for(int i = 0; i < total_deals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);

      // Exclusão estrita de movimentações de capital (depósitos, saques, créditos)
      if(deal_type == DEAL_TYPE_BALANCE || deal_type == DEAL_TYPE_CREDIT)
         continue;

      // Inclusão exclusiva de operações econômicas de negociação
      if(deal_type == DEAL_TYPE_BUY || deal_type == DEAL_TYPE_SELL)
      {
         double profit     = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         double swap       = HistoryDealGetDouble(ticket, DEAL_SWAP);
         double fee        = HistoryDealGetDouble(ticket, DEAL_FEE);

         realized += (profit + commission + swap + fee);
      }
   }
   return realized;
}

double CalculateFloatingResult()
{
   return AccountInfoDouble(ACCOUNT_PROFIT);
}

double CalculateConsolidatedResult(datetime t_start_day, datetime t_now)
{
   return CalculateRealizedResultToday(t_start_day, t_now) + CalculateFloatingResult();
}

double CalculateWindowResult(double D, double baseline)
{
   return D - baseline;
}

//+------------------------------------------------------------------+
//| Avaliação de Condições de Segurança (safe_to_reopen)             |
//+------------------------------------------------------------------+
bool CheckSafetyConditions()
{
   if(PositionsTotal() > 0)
      return false;
   if(OrdersTotal() > 0)
      return false;
   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
      return false;
   return true;
}

//+------------------------------------------------------------------+
//| Operações de Liquidação Compulsória Global (ADR 0005)            |
//+------------------------------------------------------------------+
int CancelPendingOrders(bool rate_limit_logs = false)
{
   int fail_count = 0;
   int total_orders = OrdersTotal();
   if(total_orders <= 0) return 0;

   ulong order_tickets[];
   string order_symbols[];
   ArrayResize(order_tickets, total_orders);
   ArrayResize(order_symbols, total_orders);
   for(int i = 0; i < total_orders; i++)
   {
      order_tickets[i] = OrderGetTicket(i);
      order_symbols[i] = OrderGetString(ORDER_SYMBOL);
   }

   static datetime s_last_cancel_log = 0;
   datetime now = TimeCurrent();
   bool should_log = (!rate_limit_logs || (now - s_last_cancel_log >= 5));

   for(int i = 0; i < total_orders; i++)
   {
      ulong ticket = order_tickets[i];
      string sym   = order_symbols[i];
      if(ticket > 0)
      {
         if(!g_trade.OrderDelete(ticket))
         {
            fail_count++;
            if(should_log)
            {
               PrintFormat("[EddyTrader][ERROR] FALHA ao cancelar ordem pendente #%I64u (%s): Retcode %u (%s)",
                           ticket, sym, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
            }
         }
         else
         {
            PrintFormat("[EddyTrader][INFO] Ordem pendente #%I64u (%s) cancelada com sucesso. Retcode %u (%s)",
                        ticket, sym, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
         }
      }
   }
   if(should_log && fail_count > 0)
      s_last_cancel_log = now;

   return fail_count;
}

int ExecuteGlobalLiquidation(bool rate_limit_logs = false)
{
   int fail_count = 0;

   // 1. Coleta prévia e estável de todos os tickets e símbolos de posições abertas
   int total_pos = PositionsTotal();
   if(total_pos > 0)
   {
      ulong pos_tickets[];
      string pos_symbols[];
      ArrayResize(pos_tickets, total_pos);
      ArrayResize(pos_symbols, total_pos);
      for(int i = 0; i < total_pos; i++)
      {
         pos_tickets[i] = PositionGetTicket(i);
         pos_symbols[i] = PositionGetString(POSITION_SYMBOL);
      }

      static datetime s_last_pos_log = 0;
      datetime now = TimeCurrent();
      bool should_log = (!rate_limit_logs || (now - s_last_pos_log >= 5));

      // 2. Fechamento compulsório desacoplado por ticket individual (universal Netting/Hedging)
      for(int i = 0; i < total_pos; i++)
      {
         ulong ticket = pos_tickets[i];
         string sym   = pos_symbols[i];
         if(ticket > 0)
         {
            if(!g_trade.PositionClose(ticket, InpDeviationPoints))
            {
               fail_count++;
               if(should_log)
               {
                  PrintFormat("[EddyTrader][ERROR] FALHA ao liquidar posição #%I64u (%s): Retcode %u (%s)",
                              ticket, sym, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
               }
            }
            else
            {
               PrintFormat("[EddyTrader][INFO] Posição #%I64u (%s) liquidada com sucesso. Retcode %u (%s)",
                           ticket, sym, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
            }
         }
      }
      if(should_log && fail_count > 0)
         s_last_pos_log = now;
   }

   // 3. Cancelamento integral de ordens pendentes
   fail_count += CancelPendingOrders(rate_limit_logs);

   return fail_count;
}

//+------------------------------------------------------------------+
//| Controle de Virada de Dia Contábil (T05 / T12)                   |
//+------------------------------------------------------------------+
void CheckMidnightRollover()
{
   datetime t_now = GetServerTimeSafe();
   datetime t_day_current = GetDayStart(t_now);

   if(t_day_current > g_day_start)
   {
      datetime old_day = g_day_start;
      g_day_start = t_day_current;

      if(g_current_state == EDDY_STATE_MONITORING)
      {
         // T05: Novo dia operacional em vigilância nominal -> Reinicia J0 com B0 = 0.0
         PrintFormat("[EddyTrader][INFO] T05: Virada de dia contábil detectada (%s -> %s). Reiniciando J0 com Baseline B0 = 0.0",
                     TimeToString(old_day, TIME_DATE), TimeToString(t_day_current, TIME_DATE));
         g_window_id = 0;
         g_baseline  = 0.0;
         PersistState();
      }
      else
      {
         // T12: Novo dia durante estado de contenção/bloqueio -> Preserva bloqueio de 4h inalterado
         PrintFormat("[EddyTrader][INFO] T12: Virada de dia contábil durante bloqueio ativo (%s). Bloqueio preservado até %s.",
                     EnumToString(g_current_state), TimeToString(g_t_unlock, TIME_DATE|TIME_SECONDS));
         PersistState();
      }
   }
}

//+------------------------------------------------------------------+
//| Funções Auxiliares de Tradução e Formatação para o Trader        |
//+------------------------------------------------------------------+
string GetHumanStateName(ENUM_EDDY_STATE state)
{
   switch(state)
   {
      case EDDY_STATE_INIT:                 return "INICIALIZANDO";
      case EDDY_STATE_MONITORING:           return "MONITORANDO";
      case EDDY_STATE_PROTECTION_TRIGGERED: return "PROTECAO ACIONADA";
      case EDDY_STATE_LIQUIDATING:          return "FECHANDO POSICOES";
      case EDDY_STATE_BLOCKED:              return "BLOQUEIO ATIVO";
      case EDDY_STATE_REOPENING:            return "REABRINDO";
   }
   return "DESCONHECIDO";
}

bool ParseMoneyInput(string input_str, double &out_val)
{
   out_val = 0.0;
   StringTrimLeft(input_str);
   StringTrimRight(input_str);
   if(StringLen(input_str) == 0)
      return false;

   string s = input_str;
   StringToUpper(s);
   StringReplace(s, "R$", "");
   StringReplace(s, "$", "");
   StringReplace(s, "BRL", "");
   StringReplace(s, "USD", "");
   StringReplace(s, "EUR", "");
   StringReplace(s, " ", "");
   StringReplace(s, ",", ".");

   StringTrimLeft(s);
   StringTrimRight(s);
   if(StringLen(s) == 0)
      return false;

   int dot_count = 0;
   int digit_count = 0;
   for(int i = 0; i < StringLen(s); i++)
   {
      ushort ch = StringGetCharacter(s, i);
      if(ch >= '0' && ch <= '9')
      {
         digit_count++;
      }
      else if(ch == '.')
      {
         dot_count++;
         if(dot_count > 1)
            return false;
      }
      else
      {
         return false;
      }
   }

   if(digit_count == 0)
      return false;

   double val = StringToDouble(s);
   if(val <= 0.0)
      return false;

   out_val = NormalizeDouble(val, 2);
   return true;
}

bool SetMaxLossConfig(double new_limit, string &err_msg)
{
   // 1. Validar novo valor e condições operacionais
   if(new_limit <= 0.0)
   {
      err_msg = "Limite deve ser maior que zero (> 0.0).";
      return false;
   }

   // Regra inegociável de segurança: só permite alteração em MONITORING com safe_to_operate == true
   if(g_current_state != EDDY_STATE_MONITORING || !g_safe_to_operate)
   {
      err_msg = "Alteracao proibida: EA nao esta em MONITORING seguro.";
      PrintFormat("[EddyTrader][WARN] Tentativa de alterar limite de perda rejeitada! Estado=%s, safe_to_operate=%d",
                  EnumToString(g_current_state), (int)g_safe_to_operate);
      return false;
   }

   // 2. Gravar Global Variable
   string key = GVConfigKey("MAX_LOSS");
   ResetLastError();
   datetime set_res = GlobalVariableSet(key, new_limit);
   int set_err = GetLastError();
   if(set_res == 0 && set_err != 0)
   {
      err_msg = "Falha ao gravar configuracao no terminal MT5.";
      PrintFormat("[EddyTrader][CRITICAL] Falha ao persistir limite %s nas Global Variables! Erro: %d",
                  key, set_err);
      return false;
   }

   // 3. Executar GlobalVariablesFlush()
   GlobalVariablesFlush();

   // 4. Confirmar sucesso da persistência (leitura atômica de volta)
   ResetLastError();
   if(!GlobalVariableCheck(key))
   {
      err_msg = "Falha na verificacao da chave persistida nas Global Variables.";
      PrintFormat("[EddyTrader][CRITICAL] Chave %s nao encontrada apos tentativa de persistencia!", key);
      return false;
   }

   double read_back = GlobalVariableGet(key);
   if(read_back != new_limit)
   {
      err_msg = "Inconsistencia no valor gravado nas Global Variables.";
      PrintFormat("[EddyTrader][CRITICAL] Valor lido de %s (%.2f) diverge do solicitado (%.2f)!",
                  key, read_back, new_limit);
      return false;
   }

   // 5. Somente então atualizar g_max_loss
   PrintFormat("[EddyTrader][INFO] Limite de perda confirmado e persistido: %.2f -> %.2f (chave=%s)",
               g_max_loss, new_limit, key);
   g_max_loss = new_limit;
   err_msg = "";

   // 6. Executar a avaliação normal da FSM
   ProcessFSM();
   return true;
}

//+------------------------------------------------------------------+
//| Primitivas de Manipulação de Objetos Gráficos Nativos            |
//+------------------------------------------------------------------+
//--- Margem de Segurança para Painel One Click Trading do MT5 (BUY/SELL no topo esquerdo)
#define ONE_CLICK_SAFE_MARGIN_Y 80

int GetHudOriginX()
{
   return InpHudOffsetX;
}

int GetHudOriginY()
{
   if(InpHudCorner == CORNER_LEFT_UPPER)
      return ONE_CLICK_SAFE_MARGIN_Y + InpHudOffsetY;
   return InpHudOffsetY;
}

void UI_SetRect(const string name, int x, int y, int w, int h, color bg_clr, color border_clr = clrNONE)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, InpHudCorner);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, GetHudOriginX() + x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, GetHudOriginY() + y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg_clr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, border_clr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, (border_clr != clrNONE) ? BORDER_FLAT : BORDER_SUNKEN);
}

void UI_SetLabel(const string name, int x, int y, const string text, color clr, int font_size = 9, bool bold = false)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, InpHudCorner);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, GetHudOriginX() + x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, GetHudOriginY() + y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Bold" : "Segoe UI");
}

void UI_SetButton(const string name, int x, int y, int w, int h, const string text, color bg_clr, color text_clr, int font_size = 8, bool bold = false)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, InpHudCorner);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, GetHudOriginX() + x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, GetHudOriginY() + y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg_clr);
   ObjectSetInteger(0, name, OBJPROP_COLOR, text_clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Bold" : "Segoe UI");
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
}

void UI_SetEdit(const string name, int x, int y, int w, int h, const string text, color bg_clr, color text_clr, int font_size = 10)
{
   bool is_new = (ObjectFind(0, name) < 0);
   if(is_new)
   {
      ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, InpHudCorner);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false); // NUNCA selectable para permitir foco direto de digitação
      ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_READONLY, false);
      ObjectSetInteger(0, name, OBJPROP_ALIGN, ALIGN_CENTER);
      ObjectSetString(0, name, OBJPROP_TEXT, text); // Seta texto inicial APENAS na criação
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, GetHudOriginX() + x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, GetHudOriginY() + y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg_clr);
   ObjectSetInteger(0, name, OBJPROP_COLOR, text_clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI");
}

void UI_DeleteAll()
{
   ObjectsDeleteAll(0, EDDY_UI_PREFIX);
   ChartRedraw(0);
}

void UI_DeleteDialog()
{
   ObjectsDeleteAll(0, EDDY_UI_PREFIX + "Dlg_");
   ChartRedraw(0);
}

void UI_DeleteHUD()
{
   ObjectsDeleteAll(0, EDDY_UI_PREFIX + "Hud_");
   ChartRedraw(0);
}

void UI_DeleteDetailed()
{
   ObjectsDeleteAll(0, EDDY_UI_PREFIX + "Det_");
   ChartRedraw(0);
}

void UI_DeleteCollapsed()
{
   ObjectsDeleteAll(0, EDDY_UI_PREFIX + "Min_");
   ChartRedraw(0);
}

void SetPanelState(ENUM_DISCIPLINADOR_PANEL_STATE new_state)
{
   g_panel_state = new_state;
   string key = GVConfigKey("PANEL_COLLAPSED");
   ResetLastError();
   GlobalVariableSet(key, (new_state == PANEL_COLLAPSED) ? 1.0 : 0.0);
   GlobalVariablesFlush();
   // Nota: falha na gravação desta preferência visual NÃO coloca o motor em fail-closed.
}

//+------------------------------------------------------------------+
//| Janela Separada de Configuração de Limite de Perda               |
//+------------------------------------------------------------------+
void GetDialogPosition(int &dlg_x, int &dlg_y)
{
   // Dimensões do HUD Compacto: W = 260, H = 192
   // Dimensões do Diálogo: W = 280, H = 205
   long chart_h = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   int needed_h = GetHudOriginY() + 192 + 215 + 20;

   // Se houver espaço vertical suficiente, posiciona abaixo do HUD
   if(chart_h <= 0 || chart_h >= needed_h)
   {
      dlg_x = 0;           // Relativo a GetHudOriginX()
      dlg_y = 202;         // Relativo a GetHudOriginY() (logo abaixo do HUD)
   }
   else
   {
      // Em janelas verticalmente compactas, posiciona ao lado do HUD
      dlg_x = 270;         // Relativo a GetHudOriginX() (à direita do HUD)
      dlg_y = 0;           // Relativo a GetHudOriginY()
   }
}

void UI_OpenConfigDialog()
{
   if(g_current_state != EDDY_STATE_MONITORING || !g_safe_to_operate || !g_is_owner)
   {
      Print("[EddyTrader][WARN] Configuração indisponível fora de MONITORING seguro.");
      return;
   }

   UI_DeleteDialog(); // Limpeza preventiva de qualquer resíduo
   g_config_ui_state  = UI_STATE_EDITING;
   g_config_error_msg = "";
   g_pending_max_loss = 0.0;

   int dx = 0, dy = 0;
   GetDialogPosition(dx, dy);
   string curr = AccountInfoString(ACCOUNT_CURRENCY);

   // Painel de Configuração (W=280, H=205)
   UI_SetRect(EDDY_UI_PREFIX + "Dlg_Bg", dx, dy, 280, 205, C'18,22,30', C'0,150,214');
   UI_SetLabel(EDDY_UI_PREFIX + "Dlg_Title", dx + 14, dy + 12, "CONFIGURAR LIMITE DE PERDA", C'0,180,216', 9, true);
   UI_SetLabel(EDDY_UI_PREFIX + "Dlg_CurLimit", dx + 14, dy + 36, StringFormat("Limite Atual: %.2f %s", g_max_loss, curr), C'170,180,195', 8);
   UI_SetLabel(EDDY_UI_PREFIX + "Dlg_Input_Lbl", dx + 14, dy + 58, StringFormat("Novo Limite (%s):", curr), clrWhite, 8, true);

   // Campo de Edição: Largo, alto, confortável, texto inicial g_max_loss
   string init_txt = DoubleToString(g_max_loss, 2);
   UI_SetEdit(EDDY_UI_PREFIX + "Dlg_Input", dx + 14, dy + 78, 252, 26, init_txt, C'28,34,48', clrWhite, 10);

   // Mensagem de Orientação / Erro
   UI_SetLabel(EDDY_UI_PREFIX + "Dlg_Err", dx + 14, dy + 112, "Digite o valor (ex: 750,00 ou 1000)", C'130,140,155', 8);

   // Botões: CANCELAR e AVANÇAR
   UI_SetButton(EDDY_UI_PREFIX + "Dlg_Btn_Cancel", dx + 14, dy + 150, 120, 28, "CANCELAR", C'50,56,68', clrWhite, 8);
   UI_SetButton(EDDY_UI_PREFIX + "Dlg_Btn_Next", dx + 146, dy + 150, 120, 28, "AVANCAR", C'0,122,204', clrWhite, 8, true);

   ChartRedraw(0);
}

void UI_ShowConfirmDialog()
{
   int dx = 0, dy = 0;
   GetDialogPosition(dx, dy);
   string curr = AccountInfoString(ACCOUNT_CURRENCY);

   datetime t_now = GetServerTimeSafe();
   double R_day   = CalculateRealizedResultToday(g_day_start, t_now);
   double F       = CalculateFloatingResult();
   double D       = R_day + F;

   g_config_ui_state = UI_STATE_CONFIRMING;

   // Remove elementos de edição
   ObjectDelete(0, EDDY_UI_PREFIX + "Dlg_Input_Lbl");
   ObjectDelete(0, EDDY_UI_PREFIX + "Dlg_Input");
   ObjectDelete(0, EDDY_UI_PREFIX + "Dlg_Btn_Next");

   // Atualiza Painel para Confirmação
   UI_SetRect(EDDY_UI_PREFIX + "Dlg_Bg", dx, dy, 280, 205, C'18,22,30', C'243,156,18');
   UI_SetLabel(EDDY_UI_PREFIX + "Dlg_Title", dx + 14, dy + 12, "CONFIRMAR NOVO LIMITE", clrGold, 9, true);
   UI_SetLabel(EDDY_UI_PREFIX + "Dlg_CurLimit", dx + 14, dy + 36, StringFormat("Limite Atual: %.2f %s", g_max_loss, curr), C'170,180,195', 8);
   UI_SetLabel(EDDY_UI_PREFIX + "Dlg_NewLimit", dx + 14, dy + 58, StringFormat("NOVO LIMITE: %.2f %s", g_pending_max_loss, curr), clrWhite, 9, true);

   color res_clr = (D >= 0) ? C'46,204,113' : C'231,76,60';
   UI_SetLabel(EDDY_UI_PREFIX + "Dlg_CurResult", dx + 14, dy + 80, StringFormat("Resultado Atual: %+.2f %s", D, curr), res_clr, 8);
   UI_SetLabel(EDDY_UI_PREFIX + "Dlg_Err", dx + 14, dy + 108, "Aviso: Novo limite tem aplicacao imediata!", C'243,156,18', 8);

   // Botões: VOLTAR e CONFIRMAR
   UI_SetButton(EDDY_UI_PREFIX + "Dlg_Btn_Back", dx + 14, dy + 150, 120, 28, "VOLTAR", C'50,56,68', clrWhite, 8);
   UI_SetButton(EDDY_UI_PREFIX + "Dlg_Btn_Confirm", dx + 146, dy + 150, 120, 28, "CONFIRMAR", C'39,174,96', clrWhite, 8, true);

   ChartRedraw(0);
}

void UI_BackToEditing()
{
   int dx = 0, dy = 0;
   GetDialogPosition(dx, dy);
   string curr = AccountInfoString(ACCOUNT_CURRENCY);

   g_config_ui_state = UI_STATE_EDITING;

   // Remove elementos de confirmação
   ObjectDelete(0, EDDY_UI_PREFIX + "Dlg_NewLimit");
   ObjectDelete(0, EDDY_UI_PREFIX + "Dlg_CurResult");
   ObjectDelete(0, EDDY_UI_PREFIX + "Dlg_Btn_Back");
   ObjectDelete(0, EDDY_UI_PREFIX + "Dlg_Btn_Confirm");

   // Restaura tela de edição
   UI_SetRect(EDDY_UI_PREFIX + "Dlg_Bg", dx, dy, 280, 205, C'18,22,30', C'0,150,214');
   UI_SetLabel(EDDY_UI_PREFIX + "Dlg_Title", dx + 14, dy + 12, "CONFIGURAR LIMITE DE PERDA", C'0,180,216', 9, true);
   UI_SetLabel(EDDY_UI_PREFIX + "Dlg_CurLimit", dx + 14, dy + 36, StringFormat("Limite Atual: %.2f %s", g_max_loss, curr), C'170,180,195', 8);
   UI_SetLabel(EDDY_UI_PREFIX + "Dlg_Input_Lbl", dx + 14, dy + 58, StringFormat("Novo Limite (%s):", curr), clrWhite, 8, true);

   string txt = (g_pending_max_loss > 0) ? DoubleToString(g_pending_max_loss, 2) : DoubleToString(g_max_loss, 2);
   UI_SetEdit(EDDY_UI_PREFIX + "Dlg_Input", dx + 14, dy + 78, 252, 26, txt, C'28,34,48', clrWhite, 10);
   ObjectSetString(0, EDDY_UI_PREFIX + "Dlg_Input", OBJPROP_TEXT, txt);

   string err_txt = (g_config_error_msg != "") ? g_config_error_msg : "Digite o valor (ex: 750,00 ou 1000)";
   color err_clr  = (g_config_error_msg != "") ? C'240,80,80' : C'130,140,155';
   UI_SetLabel(EDDY_UI_PREFIX + "Dlg_Err", dx + 14, dy + 112, err_txt, err_clr, 8);

   UI_SetButton(EDDY_UI_PREFIX + "Dlg_Btn_Cancel", dx + 14, dy + 150, 120, 28, "CANCELAR", C'50,56,68', clrWhite, 8);
   UI_SetButton(EDDY_UI_PREFIX + "Dlg_Btn_Next", dx + 146, dy + 150, 120, 28, "AVANCAR", C'0,122,204', clrWhite, 8, true);

   ChartRedraw(0);
}

void UI_CloseConfigDialog()
{
   g_config_ui_state  = UI_STATE_IDLE;
   g_pending_max_loss = 0.0;
   g_config_error_msg = "";
   UI_DeleteDialog();
}

//+------------------------------------------------------------------+
//| Renderizadores dos Modos Visuais de Interface                    |
//+------------------------------------------------------------------+
void RenderCollapsedHUD()
{
   Comment("");
   UI_CloseConfigDialog();
   if(ObjectFind(0, EDDY_UI_PREFIX + "Hud_CardBg") >= 0) UI_DeleteHUD();
   if(ObjectFind(0, EDDY_UI_PREFIX + "Det_Bg") >= 0)     UI_DeleteDetailed();

   datetime t_now = GetServerTimeSafe();
   double R_day   = CalculateRealizedResultToday(g_day_start, t_now);
   double F       = CalculateFloatingResult();
   double D       = R_day + F;
   string curr    = AccountInfoString(ACCOUNT_CURRENCY);

   color bg_clr     = C'20,24,33';
   color border_clr = C'40,48,65';
   string status_txt = "● ATIVO";
   color  status_clr = C'46,204,113';

   switch(g_current_state)
   {
      case EDDY_STATE_MONITORING:
         status_txt = "● ATIVO";
         status_clr = C'46,204,113';
         border_clr = C'40,48,65';
         break;

      case EDDY_STATE_PROTECTION_TRIGGERED:
      case EDDY_STATE_LIQUIDATING:
         status_txt = "🔒 LIQUIDANDO";
         status_clr = C'231,76,60';
         border_clr = C'231,76,60';
         break;

      case EDDY_STATE_BLOCKED:
      {
         long rem_sec = (long)(g_t_unlock - t_now);
         if(rem_sec < 0) rem_sec = 0;
         int h = (int)(rem_sec / 3600);
         int m = (int)((rem_sec % 3600) / 60);
         int s = (int)(rem_sec % 60);
         status_txt = StringFormat("🔒 BLOQUEADO %02d:%02d:%02d", h, m, s);
         status_clr = C'243,156,18';
         border_clr = C'243,156,18';
         break;
      }

      case EDDY_STATE_REOPENING:
         status_txt = "● REABRINDO";
         status_clr = clrGold;
         border_clr = clrGold;
         break;

      default:
         status_txt = "● INICIANDO";
         status_clr = clrGold;
         border_clr = C'40,48,65';
         break;
   }

   if(!g_is_owner || !g_safe_to_operate)
   {
      status_txt = "⚠️ FAIL-CLOSED";
      status_clr = clrRed;
      border_clr = clrRed;
   }

   // 1. Cartão Pílula Minimizada (W=370, H=26)
   UI_SetRect(EDDY_UI_PREFIX + "Min_Bg", 0, 0, 370, 26, bg_clr, border_clr);

   // 2. Identidade & Status
   UI_SetLabel(EDDY_UI_PREFIX + "Min_Title", 8, 5, "DISCIPLINADOR", C'0,180,216', 8, true);
   UI_SetLabel(EDDY_UI_PREFIX + "Min_Status", 95, 5, status_txt, status_clr, 8, true);

   // 3. Resultado & Limite
   color res_clr = (D >= 0) ? C'46,204,113' : C'231,76,60';
   string finance_txt = StringFormat("%+.2f / -%.2f %s", D, g_max_loss, curr);
   UI_SetLabel(EDDY_UI_PREFIX + "Min_Finance", 220, 5, finance_txt, res_clr, 8);

   // 4. Botão Maximizar [ + ]
   UI_SetButton(EDDY_UI_PREFIX + "Min_Btn_Expand", 336, 2, 28, 22, "[ + ]", C'0,122,204', clrWhite, 8, true);

   ChartRedraw(0);
}

void RenderCompactHUD()
{
   Comment(""); // Mantém área de comentário limpa no modo compacto

   // Se o estado mudou para não-MONITORING enquanto o diálogo estava aberto, fecha o diálogo por segurança
   if(g_config_ui_state != UI_STATE_IDLE)
   {
      if(g_current_state != EDDY_STATE_MONITORING || !g_safe_to_operate || !g_is_owner)
      {
         UI_CloseConfigDialog();
      }
   }

   // Limpa resíduo de outros modos se estiver transitando para compacto
   if(ObjectFind(0, EDDY_UI_PREFIX + "Det_Bg") >= 0)
   {
      UI_DeleteDetailed();
   }
   if(ObjectFind(0, EDDY_UI_PREFIX + "Min_Bg") >= 0)
   {
      UI_DeleteCollapsed();
   }

   datetime t_now = GetServerTimeSafe();
   double R_day   = CalculateRealizedResultToday(g_day_start, t_now);
   double F       = CalculateFloatingResult();
   double D       = R_day + F;
   string curr    = AccountInfoString(ACCOUNT_CURRENCY);
   string mode_str = (AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL) ? "REAL" : "DEMO";

   // 1. Cartão Base do HUD (W=260, H=192)
   UI_SetRect(EDDY_UI_PREFIX + "Hud_CardBg", 0, 0, 260, 192, C'20,24,33', C'40,48,65');
   UI_SetLabel(EDDY_UI_PREFIX + "Hud_Title", 12, 10, "DISCIPLINADOR TRADER", C'0,180,216', 9, true);
   UI_SetLabel(EDDY_UI_PREFIX + "Hud_Ver", 168, 11, StringFormat("v%s [%s]", EDDY_VERSION, mode_str), C'130,140,155', 7);

   // 2. Status Humano
   string status_str = GetHumanStateName(g_current_state);
   color  status_clr = clrWhite;
   switch(g_current_state)
   {
      case EDDY_STATE_MONITORING:           status_str = "MONITORANDO";        status_clr = C'46,204,113'; break;
      case EDDY_STATE_PROTECTION_TRIGGERED: status_str = "PROTECAO ACIONADA";  status_clr = C'231,76,60';  break;
      case EDDY_STATE_LIQUIDATING:          status_str = "FECHANDO OPERACOES"; status_clr = C'231,76,60';  break;
      case EDDY_STATE_BLOCKED:              status_str = "PROTECAO ATIVA";     status_clr = C'243,156,18'; break;
      case EDDY_STATE_REOPENING:            status_str = "REABRINDO";          status_clr = clrGold;       break;
      default:                              status_str = "INICIANDO";          status_clr = clrGold;       break;
   }
   if(!g_is_owner || !g_safe_to_operate)
   {
      status_str = "FAIL-CLOSED";
      status_clr = clrRed;
   }
   UI_SetLabel(EDDY_UI_PREFIX + "Hud_Status_Lbl", 12, 32, "Status:", C'150,160,175', 8);
   UI_SetLabel(EDDY_UI_PREFIX + "Hud_Status_Val", 80, 31, status_str, status_clr, 9, true);

   // 3. Resultado Atual
   UI_SetLabel(EDDY_UI_PREFIX + "Hud_Res_Lbl", 12, 52, "Resultado:", C'150,160,175', 8);
   color res_clr = (D >= 0) ? C'46,204,113' : C'231,76,60';
   UI_SetLabel(EDDY_UI_PREFIX + "Hud_Res_Val", 80, 52, StringFormat("%+.2f %s", D, curr), res_clr, 8, true);

   // 4. Limite Atual
   UI_SetLabel(EDDY_UI_PREFIX + "Hud_Limit_Lbl", 12, 72, "Limite Atual:", C'150,160,175', 8);
   UI_SetLabel(EDDY_UI_PREFIX + "Hud_Limit_Val", 80, 72, StringFormat("-%.2f %s", g_max_loss, curr), clrWhite, 8, true);

   // 5. Proteção / Bloqueio
   string prot_str = "Vigilante";
   color  prot_clr = C'46,204,113';
   if(g_current_state == EDDY_STATE_BLOCKED || g_current_state == EDDY_STATE_LIQUIDATING || g_current_state == EDDY_STATE_PROTECTION_TRIGGERED)
   {
      long rem_sec = (long)(g_t_unlock - t_now);
      if(rem_sec < 0) rem_sec = 0;
      int h = (int)(rem_sec / 3600);
      int m = (int)((rem_sec % 3600) / 60);
      int s = (int)(rem_sec % 60);
      prot_str = StringFormat("Bloqueio: %02d:%02d:%02d", h, m, s);
      prot_clr = C'243,156,18';
   }
   else if(g_config_feedback_msg != "" && t_now <= g_config_feedback_expiry)
   {
      prot_str = g_config_feedback_msg;
      prot_clr = C'46,204,113';
   }
   UI_SetLabel(EDDY_UI_PREFIX + "Hud_Prot_Lbl", 12, 92, "Protecao:", C'150,160,175', 8);
   UI_SetLabel(EDDY_UI_PREFIX + "Hud_Prot_Val", 80, 92, prot_str, prot_clr, 8, true);

   // 6. Posições e Ordens
   UI_SetLabel(EDDY_UI_PREFIX + "Hud_Ops_Lbl", 12, 112, "Operacoes:", C'150,160,175', 8);
   string ops_str = StringFormat("%d pos / %d ord", PositionsTotal(), OrdersTotal());
   UI_SetLabel(EDDY_UI_PREFIX + "Hud_Ops_Val", 80, 112, ops_str, C'180,190,205', 8);

   // 7. Botões
   bool can_configure = (g_current_state == EDDY_STATE_MONITORING && g_safe_to_operate && g_is_owner);
   if(can_configure)
   {
      string cfg_btn_txt = (g_config_ui_state != UI_STATE_IDLE) ? "CONFIGURANDO..." : "CONFIGURAR";
      color  cfg_btn_bg  = (g_config_ui_state != UI_STATE_IDLE) ? C'0,90,160' : C'0,122,204';
      UI_SetButton(EDDY_UI_PREFIX + "Hud_Btn_Config", 12, 134, 140, 22, cfg_btn_txt, cfg_btn_bg, clrWhite, 8);
   }
   else
   {
      UI_SetButton(EDDY_UI_PREFIX + "Hud_Btn_Config", 12, 134, 140, 22, "BLOQUEADO", C'40,45,55', C'110,115,125', 8);
   }
   UI_SetButton(EDDY_UI_PREFIX + "Hud_Btn_Details", 158, 134, 90, 22, "DETALHES", C'45,52,65', clrWhite, 8);

   // 8. Botão Minimizar
   UI_SetButton(EDDY_UI_PREFIX + "Hud_Btn_Min", 12, 162, 236, 22, "[ — MINIMIZAR ]", C'35,42,54', C'170,180,195', 8);

   // Se o diálogo de confirmação estiver aberto, atualizamos apenas o resultado atual nele
   if(g_config_ui_state == UI_STATE_CONFIRMING)
   {
      int dx = 0, dy = 0;
      GetDialogPosition(dx, dy);
      UI_SetLabel(EDDY_UI_PREFIX + "Dlg_CurResult", dx + 14, dy + 80, StringFormat("Resultado Atual: %+.2f %s", D, curr), res_clr, 8);
   }

   // NOTA: Enquanto em UI_STATE_EDITING, NÃO tocamos em Dlg_Input nem chamamos ChartRedraw(0) repetidamente a cada timer!
   if(g_config_ui_state == UI_STATE_IDLE)
   {
      ChartRedraw(0);
   }
}

void RenderDetailedHUD()
{
   // Fecha diálogo e limpa resíduos se estiver transitando para detalhado
   UI_CloseConfigDialog();
   if(ObjectFind(0, EDDY_UI_PREFIX + "Hud_CardBg") >= 0)
   {
      UI_DeleteHUD();
   }
   if(ObjectFind(0, EDDY_UI_PREFIX + "Min_Bg") >= 0)
   {
      UI_DeleteCollapsed();
   }

   // Garante que o Comment() cru antigo nunca seja exibido na UI técnica
   Comment("");

   datetime t_now = GetServerTimeSafe();
   double R_day   = CalculateRealizedResultToday(g_day_start, t_now);
   double F       = CalculateFloatingResult();
   double D       = R_day + F;
   double W       = CalculateWindowResult(D, g_baseline);
   string curr    = AccountInfoString(ACCOUNT_CURRENCY);
   string mode_str = (AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL) ? "REAL" : "DEMO";

   // Informações de Bloqueio e Status
   string lock_str = "Nenhum (Vigilante)";
   color  prot_clr = C'46,204,113';
   if(g_current_state == EDDY_STATE_BLOCKED || g_current_state == EDDY_STATE_LIQUIDATING || g_current_state == EDDY_STATE_PROTECTION_TRIGGERED)
   {
      long rem_sec = (long)(g_t_unlock - t_now);
      if(rem_sec < 0) rem_sec = 0;
      int h = (int)(rem_sec / 3600);
      int m = (int)((rem_sec % 3600) / 60);
      int s = (int)(rem_sec % 60);
      lock_str = StringFormat("%02d:%02d:%02d (Ate %s)", h, m, s, TimeToString(g_t_unlock, TIME_MINUTES|TIME_SECONDS));
      prot_clr = C'243,156,18';
   }
   else if(g_config_feedback_msg != "" && t_now <= g_config_feedback_expiry)
   {
      lock_str = g_config_feedback_msg;
      prot_clr = C'46,204,113';
   }

   string status_str = GetHumanStateName(g_current_state);
   color  status_clr = clrWhite;
   switch(g_current_state)
   {
      case EDDY_STATE_MONITORING:           status_clr = C'46,204,113'; break;
      case EDDY_STATE_PROTECTION_TRIGGERED: status_clr = C'231,76,60';  break;
      case EDDY_STATE_LIQUIDATING:          status_clr = C'231,76,60';  break;
      case EDDY_STATE_BLOCKED:              status_clr = C'243,156,18'; break;
      case EDDY_STATE_REOPENING:            status_clr = clrGold;       break;
      default:                              status_clr = clrGold;       break;
   }
   if(!g_is_owner || !g_safe_to_operate)
   {
      status_str = "FAIL-CLOSED";
      status_clr = clrRed;
   }

   color res_clr = (D >= 0) ? C'46,204,113' : C'231,76,60';

   // Cartão Detalhado Nativo (W=370, H=340)
   // A largura extra mantém o título e a versão em áreas independentes.
   UI_SetRect(EDDY_UI_PREFIX + "Det_Bg", 0, 0, 370, 340, C'20,24,33', C'0,150,214');
   UI_SetLabel(EDDY_UI_PREFIX + "Det_Title", 12, 10, "DISCIPLINADOR TRADER - DETALHES", C'0,180,216', 9, true);
   UI_SetLabel(EDDY_UI_PREFIX + "Det_Ver", 268, 11, StringFormat("v%s [%s]", EDDY_VERSION, mode_str), C'130,140,155', 7);

   UI_SetLabel(EDDY_UI_PREFIX + "Det_State_Lbl", 12, 32, "Estado FSM:", C'150,160,175', 8);
   UI_SetLabel(EDDY_UI_PREFIX + "Det_State_Val", 100, 32, StringFormat("%s (%s)", EnumToString(g_current_state), status_str), status_clr, 8, true);

   UI_SetLabel(EDDY_UI_PREFIX + "Det_Win_Lbl", 12, 52, "Janela / Base:", C'150,160,175', 8);
   UI_SetLabel(EDDY_UI_PREFIX + "Det_Win_Val", 100, 52, StringFormat("J%d | Bn: %.2f %s", g_window_id, g_baseline, curr), clrWhite, 8);

   UI_SetLabel(EDDY_UI_PREFIX + "Det_Limit_Lbl", 12, 72, "Limite Perda:", C'150,160,175', 8);
   UI_SetLabel(EDDY_UI_PREFIX + "Det_Limit_Val", 100, 72, StringFormat("-%.2f %s", g_max_loss, curr), clrWhite, 8, true);

   UI_SetLabel(EDDY_UI_PREFIX + "Det_Rday_Lbl", 12, 94, "Realizado Hoje:", C'150,160,175', 8);
   UI_SetLabel(EDDY_UI_PREFIX + "Det_Rday_Val", 100, 94, StringFormat("%+.2f %s", R_day, curr), (R_day >= 0 ? C'46,204,113' : C'231,76,60'), 8);

   UI_SetLabel(EDDY_UI_PREFIX + "Det_Float_Lbl", 12, 114, "Flutuante F(t):", C'150,160,175', 8);
   UI_SetLabel(EDDY_UI_PREFIX + "Det_Float_Val", 100, 114, StringFormat("%+.2f %s", F, curr), (F >= 0 ? C'46,204,113' : C'231,76,60'), 8);

   UI_SetLabel(EDDY_UI_PREFIX + "Det_Cons_Lbl", 12, 134, "Consolidado D(t):", C'150,160,175', 8);
   UI_SetLabel(EDDY_UI_PREFIX + "Det_Cons_Val", 100, 134, StringFormat("%+.2f %s", D, curr), res_clr, 8, true);

   UI_SetLabel(EDDY_UI_PREFIX + "Det_WinRes_Lbl", 12, 154, "Res. Janela Wn:", C'150,160,175', 8);
   UI_SetLabel(EDDY_UI_PREFIX + "Det_WinRes_Val", 100, 154, StringFormat("%+.2f %s", W, curr), (W >= 0 ? C'46,204,113' : C'231,76,60'), 8, true);

   UI_SetLabel(EDDY_UI_PREFIX + "Det_Prot_Lbl", 12, 176, "Protecao / ID:", C'150,160,175', 8);
   UI_SetLabel(EDDY_UI_PREFIX + "Det_Prot_Val", 100, 176, (g_protection_event_id > 0 ? StringFormat("Evt #%I64u", g_protection_event_id) : "Nenhuma (Nominal)"), prot_clr, 8);

   UI_SetLabel(EDDY_UI_PREFIX + "Det_Lock_Lbl", 12, 196, "Bloqueio:", C'150,160,175', 8);
   UI_SetLabel(EDDY_UI_PREFIX + "Det_Lock_Val", 100, 196, lock_str, prot_clr, 8);

   UI_SetLabel(EDDY_UI_PREFIX + "Det_Ops_Lbl", 12, 216, "Exposicao:", C'150,160,175', 8);
   UI_SetLabel(EDDY_UI_PREFIX + "Det_Ops_Val", 100, 216, StringFormat("%d pos / %d ord", PositionsTotal(), OrdersTotal()), C'180,190,205', 8);

   UI_SetLabel(EDDY_UI_PREFIX + "Det_Inst_Lbl", 12, 236, "Instancia:", C'150,160,175', 8);
   UI_SetLabel(EDDY_UI_PREFIX + "Det_Inst_Val", 100, 236, StringFormat("#%I64u (Owner: %s)", g_instance_id, (g_is_owner ? "SIM" : "NAO")), (g_is_owner ? clrWhite : clrRed), 8);

   if(!g_is_owner || !g_safe_to_operate)
   {
      UI_SetLabel(EDDY_UI_PREFIX + "Det_Warn", 12, 256, "FAIL-CLOSED: NEGOCIACAO BLOQUEADA", clrRed, 8, true);
   }
   else
   {
      UI_SetLabel(EDDY_UI_PREFIX + "Det_Warn", 12, 256, StringFormat("Conta: %I64u | Servidor: %s", g_account_login, AccountInfoString(ACCOUNT_SERVER)), C'130,140,155', 7);
   }

   // Botões: Retorno ao Resumo e Minimizar
   UI_SetButton(EDDY_UI_PREFIX + "Det_Btn_Back", 12, 276, 346, 24, "[ <- VOLTAR AO RESUMO ]", C'0,122,204', clrWhite, 8, true);
   UI_SetButton(EDDY_UI_PREFIX + "Det_Btn_Min",  12, 306, 346, 22, "[ — MINIMIZAR ]", C'35,42,54', C'170,180,195', 8);

   ChartRedraw(0);
}

void RenderOffHUD()
{
   UI_CloseConfigDialog();
   UI_DeleteAll();

   // OFF + fail-closed / erro operacional crítico -> aviso textual mínimo de segurança
   if(!g_is_owner || !g_safe_to_operate)
   {
      string critical_msg = StringFormat(
         ">>> ATENCAO: DISCIPLINADOR TRADER EM FAIL-CLOSED / OPERACAO BLOQUEADA <<<\n"
         " Motivo: %s | Estado: %s | Conta: %I64u",
         (!g_is_owner ? "OWNERSHIP PERDIDA" : "SEGURANCA OPERACIONAL COMPROMETIDA"),
         EnumToString(g_current_state),
         g_account_login
      );
      Comment(critical_msg);
   }
   else
   {
      // OFF + operação normal -> gráfico limpo
      Comment("");
   }
}

void UpdateHUD()
{
   if(g_hud_mode == EDDY_HUD_OFF)
   {
      RenderOffHUD();
      return;
   }

   if(g_panel_state == PANEL_COLLAPSED)
   {
      RenderCollapsedHUD();
      return;
   }

   switch(g_hud_mode)
   {
      case EDDY_HUD_DETAILED: RenderDetailedHUD(); break;
      case EDDY_HUD_COMPACT:
      default:                RenderCompactHUD();  break;
   }
}

//+------------------------------------------------------------------+
//| Transições Controladas da Máquina de Estados (FSM)               |
//+------------------------------------------------------------------+
void TransitionTo(ENUM_EDDY_STATE target_state)
{
   datetime t_now = GetServerTimeSafe();
   PrintFormat("[EddyTrader][INFO] Transição FSM: %s -> %s (t=%s)",
               EnumToString(g_current_state), EnumToString(target_state),
               TimeToString(t_now, TIME_DATE|TIME_SECONDS));

   g_current_state = target_state;

   switch(g_current_state)
   {
      case EDDY_STATE_PROTECTION_TRIGGERED:
      {
         // T04: Congelamento do gatilho e cálculo do bloqueio de 4 horas
         g_t_trigger = t_now;
         g_t_unlock  = g_t_trigger + (datetime)(InpBlockDurationHours * 3600);
         g_protection_event_id = GenerateProtectionEventId(g_t_trigger);
         PersistState();
         PrintFormat("[EddyTrader][WARN] T04: Bloqueio formalizado! EventID=%I64u, Trigger=%s, Unlock=%s",
                     g_protection_event_id,
                     TimeToString(g_t_trigger, TIME_DATE|TIME_SECONDS),
                     TimeToString(g_t_unlock, TIME_DATE|TIME_SECONDS));

         // T07: Transição imediata atômica para liquidação
         TransitionTo(EDDY_STATE_LIQUIDATING);
         break;
      }

      case EDDY_STATE_LIQUIDATING:
      {
         PersistState();
         ExecuteGlobalLiquidation(false);

         // T08 / T09: Avalia se neutralização foi 100% concluída
         if(PositionsTotal() == 0 && OrdersTotal() == 0)
         {
            PrintFormat("[EddyTrader][INFO] T08: Neutralização integral concluída (resíduo zero). Avançando para BLOCKED.");
            TransitionTo(EDDY_STATE_BLOCKED);
         }
         else
         {
            PrintFormat("[EddyTrader][WARN] T09: Exposição residual ativa (%d posições, %d ordens). Retendo em LIQUIDATING.",
                        PositionsTotal(), OrdersTotal());
         }
         break;
      }

      case EDDY_STATE_BLOCKED:
      {
         PersistState();
         PrintFormat("[EddyTrader][INFO] BLOCKED ativo. Desbloqueio programado para %s",
                     TimeToString(g_t_unlock, TIME_DATE|TIME_SECONDS));
         break;
      }

      case EDDY_STATE_REOPENING:
      {
         datetime t_reopen = t_now;
         g_window_id++;
         double D_reopen = CalculateConsolidatedResult(g_day_start, t_reopen);
         g_baseline = D_reopen;

         // Invariante de reabertura: W_(n+1)(t_reopen) == 0
         double W_new = CalculateWindowResult(D_reopen, g_baseline);
         PrintFormat("[EddyTrader][INFO] T14/T15: Reabertura formal! Nova janela J%d, Baseline Bn=%.2f, W_new=%.2f",
                     g_window_id, g_baseline, W_new);

         // Arquiva evento de proteção
         g_t_trigger           = 0;
         g_t_unlock            = 0;
         g_protection_event_id = 0;

         // Persistência mandatória da baseline e estado antes de avançar para MONITORING
         if(PersistState())
         {
            g_safe_to_operate = true;
            TransitionTo(EDDY_STATE_MONITORING);
         }
         else
         {
            // Falha crítica na persistência da baseline: bloqueia retorno a MONITORING
            PrintFormat("[EddyTrader][CRITICAL] Falha ao persistir baseline da janela J%d nas Global Variables! Retendo em INIT (fail-closed).",
                        g_window_id);
            g_current_state   = EDDY_STATE_INIT;
            g_safe_to_operate = false;
         }
         break;
      }

      case EDDY_STATE_MONITORING:
      {
         g_safe_to_operate = true;
         PersistState();
         PrintFormat("[EddyTrader][INFO] MONITORING ativo. Janela J%d | Baseline Bn=%.2f | Operação liberada.",
                     g_window_id, g_baseline);
         break;
      }

      case EDDY_STATE_INIT:
      {
         g_safe_to_operate = false;
         PersistState();
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| Processador Central da FSM                                       |
//+------------------------------------------------------------------+
void ProcessFSM()
{
   // Guarda inegociável de ownership: se a instância perdeu ownership, recusa qualquer ação
   if(!g_is_owner)
   {
      g_safe_to_operate = false;
      g_current_state   = EDDY_STATE_INIT;
      UpdateHUD();
      return;
   }

   datetime t_now = GetServerTimeSafe();

   // 1. Verificação contínua da virada de dia
   CheckMidnightRollover();

   // 2. Avaliação de acordo com o estado corrente
   switch(g_current_state)
   {
      case EDDY_STATE_INIT:
      {
         // Postura Fail-Closed: permanece em INIT até resolução de inconsistências
         g_safe_to_operate = false;
         break;
      }

      case EDDY_STATE_MONITORING:
      {
         double D = CalculateConsolidatedResult(g_day_start, t_now);
         double W = CalculateWindowResult(D, g_baseline);

         // T04: Avalia violação do limite financeiro da janela
         if(W <= -g_max_loss)
         {
            PrintFormat("[EddyTrader][WARN] T04: Limite violado! W=%.2f <= -L=-%.2f (D=%.2f, Bn=%.2f)",
                        W, g_max_loss, D, g_baseline);
            TransitionTo(EDDY_STATE_PROTECTION_TRIGGERED);
         }
         break;
      }

      case EDDY_STATE_PROTECTION_TRIGGERED:
      {
         TransitionTo(EDDY_STATE_LIQUIDATING);
         break;
      }

      case EDDY_STATE_LIQUIDATING:
      {
         // Retentativa contínua de liquidação com supressão de log flood
         if(PositionsTotal() > 0 || OrdersTotal() > 0)
         {
            ExecuteGlobalLiquidation(true);
         }

         // T08: Se resíduo zerou, avança para BLOCKED
         if(PositionsTotal() == 0 && OrdersTotal() == 0)
         {
            PrintFormat("[EddyTrader][INFO] T08: Resíduo zerado. Avançando para BLOCKED.");
            TransitionTo(EDDY_STATE_BLOCKED);
         }
         break;
      }

      case EDDY_STATE_BLOCKED:
      {
         // Neutralização de intervenções residuais durante o bloqueio
         if(PositionsTotal() > 0 || OrdersTotal() > 0)
         {
            PrintFormat("[EddyTrader][WARN] ALERTA: Exposição detectada durante BLOCKED! Executando neutralização.");
            ExecuteGlobalLiquidation(true);
         }

         // T13 / T14: Avalia alcance do tempo mínimo de 4 horas
         if(t_now >= g_t_unlock)
         {
            if(CheckSafetyConditions())
            {
               PrintFormat("[EddyTrader][INFO] T14: Tempo de bloqueio cumprido (%s >= %s) e condições seguras. Iniciando REOPENING.",
                           TimeToString(t_now, TIME_DATE|TIME_SECONDS),
                           TimeToString(g_t_unlock, TIME_DATE|TIME_SECONDS));
               TransitionTo(EDDY_STATE_REOPENING);
            }
            else
            {
               PrintFormat("[EddyTrader][WARN] T13: Tempo cumprido mas safe_to_reopen == false (pos=%d, ord=%d, conn=%d). Retendo em BLOCKED.",
                           PositionsTotal(), OrdersTotal(), (int)TerminalInfoInteger(TERMINAL_CONNECTED));
            }
         }
         break;
      }

      case EDDY_STATE_REOPENING:
      {
         if(CheckSafetyConditions())
         {
            TransitionTo(EDDY_STATE_REOPENING);
         }
         break;
      }
   }

   // 3. Atualização do HUD visual no gráfico
   UpdateHUD();
}

//+------------------------------------------------------------------+
//| Event Handlers Oficiais do MQL5                                  |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("[Disciplinador Trader][INFO] ==================================================");
   PrintFormat("[Disciplinador Trader][INFO] Inicializando %s v%s - Release Candidate 3", EDDY_PRODUCT_NAME, EDDY_VERSION);
   PrintFormat("[Disciplinador Trader][INFO] %s", EDDY_PURPOSE);
   Print("[Disciplinador Trader][INFO] ==================================================");

   // 1. Validação estrita de parâmetros de entrada (Hardening Operacional)
   if(InpMaxLoss <= 0.0)
   {
      PrintFormat("[EddyTrader][ERROR] Parâmetro inválido: InpMaxLoss deve ser > 0.0 (configurado: %.2f)", InpMaxLoss);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpBlockDurationHours < 1 || InpBlockDurationHours > 168)
   {
      PrintFormat("[EddyTrader][ERROR] Parâmetro inválido: InpBlockDurationHours fora da faixa (1 a 168h, configurado: %d)", InpBlockDurationHours);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpTimerIntervalMs < 50 || InpTimerIntervalMs > 5000)
   {
      PrintFormat("[EddyTrader][ERROR] Parâmetro inválido: InpTimerIntervalMs fora da faixa permitida (50 a 5000 ms, configurado: %d ms)", InpTimerIntervalMs);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpDeviationPoints > 500)
   {
      PrintFormat("[EddyTrader][ERROR] Parâmetro inválido: InpDeviationPoints excessivo (máx 500 pontos, configurado: %I64u)", InpDeviationPoints);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpHudOffsetX < 0 || InpHudOffsetY < 0)
   {
      PrintFormat("[EddyTrader][ERROR] Parâmetro inválido: Offsets de HUD não podem ser negativos (X=%d, Y=%d)", InpHudOffsetX, InpHudOffsetY);
      return INIT_PARAMETERS_INCORRECT;
   }

   // 2. Identificação da conta e configuração comercial
   g_account_login = (ulong)AccountInfoInteger(ACCOUNT_LOGIN);
   g_trade.SetDeviationInPoints(InpDeviationPoints);

   ENUM_ACCOUNT_TRADE_MODE trade_mode = (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(trade_mode == ACCOUNT_TRADE_MODE_REAL)
   {
      Print("[Disciplinador Trader][WARN] ATENÇÃO: Conta REAL detectada! O Disciplinador Trader atuará em modo de proteção absoluta de capital.");
   }
   else
   {
      Print("[Disciplinador Trader][INFO] Modo de conta DEMO / TESTE detectado.");
   }

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      Print("[Disciplinador Trader][WARN] AVISO: 'Algo Trading' está DESATIVADO nas opções do terminal MT5.");
   }
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
   {
      Print("[Disciplinador Trader][WARN] AVISO: Negociação desativada para a conta atual.");
   }

   // 3. Guarda de Instância Única por Conta (OWNER + HEARTBEAT Atômico via CAS)
   if(!AcquireInstanceGuard())
   {
      return INIT_FAILED;
   }

   // 4. Resolução do Limite Efetivo de Perda e Configuração de Interface
   g_hud_mode = InpHudMode;
   g_last_expanded_hud_mode = (InpHudMode == EDDY_HUD_DETAILED) ? EDDY_HUD_DETAILED : EDDY_HUD_COMPACT;

   // Resolução da preferência visual de minimização (EDDY_<LOGIN>_CONFIG_PANEL_COLLAPSED)
   string key_panel = GVConfigKey("PANEL_COLLAPSED");
   if(GlobalVariableCheck(key_panel))
   {
      if(GlobalVariableGet(key_panel) == 1.0)
         g_panel_state = PANEL_COLLAPSED;
      else
         g_panel_state = PANEL_EXPANDED;
   }
   else
   {
      g_panel_state = PANEL_EXPANDED;
   }
   string config_key = GVConfigKey("MAX_LOSS");
   if(GlobalVariableCheck(config_key))
   {
      double persisted_limit = GlobalVariableGet(config_key);
      if(persisted_limit > 0.0)
      {
         g_max_loss = persisted_limit;
         PrintFormat("[EddyTrader][INFO] Limite de perda carregado da configuração persistida: %.2f (Input=%.2f)",
                     g_max_loss, InpMaxLoss);
      }
      else
      {
         g_max_loss = InpMaxLoss;
         PrintFormat("[EddyTrader][WARN] Limite persistido inválido (%.2f). Usando InpMaxLoss=%.2f",
                     persisted_limit, InpMaxLoss);
      }
   }
   else
   {
      g_max_loss = InpMaxLoss;
      PrintFormat("[EddyTrader][INFO] Nenhuma configuração persistida prévia. Usando InpMaxLoss=%.2f",
                  g_max_loss);
   }

   // 5. Marcação temporal do dia operacional
   datetime t_now = GetServerTimeSafe();
   g_day_start = GetDayStart(t_now);

   // 6. Reconstituição Determinística de Estado (ADR 0004 / ADR 0005)
   EddyRecoveryState rec;
   if(LoadState(rec))
   {
      PrintFormat("[EddyTrader][INFO] Estado persistido encontrado: State=%s, J=%d, Bn=%.2f, EventID=%I64u, Unlock=%s",
                  EnumToString(rec.state), rec.window_id, rec.baseline, rec.protection_event_id,
                  TimeToString(rec.t_unlock, TIME_DATE|TIME_SECONDS));

      // Se havia proteção ativa antes do restart
      if(rec.state == EDDY_STATE_BLOCKED || rec.state == EDDY_STATE_LIQUIDATING || rec.state == EDDY_STATE_PROTECTION_TRIGGERED)
      {
         g_window_id           = rec.window_id;
         g_baseline            = rec.baseline;
         g_t_trigger           = rec.t_trigger;
         g_t_unlock            = rec.t_unlock;
         g_protection_event_id = rec.protection_event_id;
         g_safe_to_operate     = true; // Motor recuperado com integridade operacional e saudável

         // T03: Exposição residual aberta tem precedência absoluta
         if(PositionsTotal() > 0 || OrdersTotal() > 0)
         {
            PrintFormat("[Disciplinador Trader][WARN] T03: Exposição residual aberta detectada pós-restart durante proteção. Forçando LIQUIDATING.");
            g_current_state = EDDY_STATE_LIQUIDATING;
         }
         else
         {
            if(t_now < g_t_unlock)
            {
               // T02A: Bloqueio ativo mantido
               PrintFormat("[Disciplinador Trader][INFO] T02A: Bloqueio temporal mantido pós-restart (%d s restantes).",
                           (int)(g_t_unlock - t_now));
               g_current_state = EDDY_STATE_BLOCKED;
            }
            else
            {
               // t_now >= g_t_unlock
               if(CheckSafetyConditions())
               {
                  // T02C: Reabertura imediata pós-restart: INIT -> REOPENING -> MONITORING
                  PrintFormat("[Disciplinador Trader][INFO] T02C: Bloqueio vencido e condições seguras. Conduzindo formalmente INIT -> REOPENING -> MONITORING.");
                  TransitionTo(EDDY_STATE_REOPENING);
               }
               else
               {
                  // T02B: Bloqueio retido por falta de segurança
                  PrintFormat("[Disciplinador Trader][WARN] T02B: Bloqueio vencido mas ambiente inseguro (pos=%d, ord=%d). Retendo em BLOCKED.",
                              PositionsTotal(), OrdersTotal());
                  g_current_state = EDDY_STATE_BLOCKED;
               }
            }
         }
      }
      else if(rec.state == EDDY_STATE_REOPENING)
      {
         g_window_id           = rec.window_id;
         g_baseline            = rec.baseline;
         g_safe_to_operate     = true;
         g_current_state       = EDDY_STATE_REOPENING;
         if(CheckSafetyConditions())
         {
            TransitionTo(EDDY_STATE_REOPENING);
         }
         else
         {
            g_current_state = EDDY_STATE_BLOCKED;
         }
      }
      else if(rec.state == EDDY_STATE_MONITORING)
      {
         // Verifica se houve virada de dia durante o terminal desligado
         datetime persisted_day = rec.day_timestamp;
         if(persisted_day < g_day_start)
         {
            PrintFormat("[Disciplinador Trader][INFO] T05: Novo dia operacional detectado pós-restart (%s < %s). Iniciando J0 com B0=0.",
                        TimeToString(persisted_day, TIME_DATE), TimeToString(g_day_start, TIME_DATE));
            g_current_state   = EDDY_STATE_MONITORING;
            g_window_id       = 0;
            g_baseline        = 0.0;
            g_safe_to_operate = true;
         }
         else
         {
            // Mesmo dia operacional. Valida integridade de janela intradiária Jn (n >= 1)
            if(rec.window_id >= 1)
            {
               if(!GlobalVariableCheck(GVKey("BASELINE")))
               {
                  // Postura Fail-Closed (W06-15)
                  PrintFormat("[Disciplinador Trader][CRITICAL] (FAIL-CLOSED): Janela J%d ativa mas Baseline Bn ausente nas Global Variables! Operações retidas em INIT.",
                              rec.window_id);
                  g_current_state   = EDDY_STATE_INIT;
                  g_safe_to_operate = false;
                  PersistState();
                  EventSetMillisecondTimer(InpTimerIntervalMs);
                  UpdateHUD();
                  return INIT_SUCCEEDED;
               }
            }

            g_window_id       = rec.window_id;
            g_baseline        = rec.baseline;
            g_current_state   = EDDY_STATE_MONITORING;
            g_safe_to_operate = true;
            PrintFormat("[Disciplinador Trader][INFO] MONITORING reconstituído com sucesso: Janela J%d | Baseline Bn=%.2f",
                        g_window_id, g_baseline);
         }
      }
      else if(rec.state == EDDY_STATE_INIT)
      {
         g_current_state   = EDDY_STATE_INIT;
         g_safe_to_operate = false;
         PrintFormat("[Disciplinador Trader][WARN] (FAIL-CLOSED): Estado persistido prévio era INIT. Mantendo postura fail-closed.");
      }
      else
      {
         g_current_state   = rec.state;
         g_safe_to_operate = false;
      }
   }
   else
   {
      // Inicialização limpa (primeira vez na conta)
      PrintFormat("[Disciplinador Trader][INFO] Inicialização limpa na conta %I64u. Iniciando J0 com B0=0.0", g_account_login);
      g_current_state   = EDDY_STATE_MONITORING;
      g_window_id       = 0;
      g_baseline        = 0.0;
      g_safe_to_operate = true;
   }

   if(!PersistState())
   {
      PrintFormat("[Disciplinador Trader][CRITICAL] (FAIL-CLOSED): Falha ao persistir estado pós-inicialização! Retendo em INIT.");
      g_current_state   = EDDY_STATE_INIT;
      g_safe_to_operate = false;
   }

   PrintFormat("[Disciplinador Trader][INFO] Reconstituição Concluída: Estado=%s | Health=%s | Owner=#%I64u (is_owner=%s) | EventID=%I64u | Unlock=%s | Janela=J%d | Baseline=%.2f",
               EnumToString(g_current_state),
               (g_safe_to_operate ? "HEALTHY" : "FAIL-CLOSED"),
               g_instance_id,
               (g_is_owner ? "SIM" : "NAO"),
               g_protection_event_id,
               (g_t_unlock > 0 ? TimeToString(g_t_unlock, TIME_DATE|TIME_SECONDS) : "NENHUM"),
               g_window_id,
               g_baseline);

   // 6. Ativação do MillisecondTimer de alta frequência com fallback e contenção segura
   if(!EventSetMillisecondTimer(InpTimerIntervalMs))
   {
      PrintFormat("[EddyTrader][WARN] EventSetMillisecondTimer(%d ms) falhou. Tentando fallback para EventSetTimer(1 s)...", InpTimerIntervalMs);
      if(!EventSetTimer(1))
      {
         Print("[EddyTrader][CRITICAL] Falha fatal ao inicializar timer no terminal MT5. Abortando carga.");
         ReleaseInstanceGuard();
         return INIT_FAILED;
      }
   }

   // 8. Avaliação inicial da FSM
   ProcessFSM();

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ReleaseInstanceGuard();
   UI_DeleteAll();
   Comment(""); // Limpa o HUD gráfico
   PrintFormat("[EddyTrader][INFO] EA descarregado da conta %I64u. Razão: %d", g_account_login, reason);
}

void OnTick()
{
   ProcessFSM();
}

void OnTimer()
{
   UpdateHeartbeat();
   ProcessFSM();
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   // Neutralização reativa imediata de intervenções manuais durante contenção ou bloqueio
   if(g_current_state == EDDY_STATE_BLOCKED || g_current_state == EDDY_STATE_LIQUIDATING || g_current_state == EDDY_STATE_PROTECTION_TRIGGERED)
   {
      if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
      {
         if(trans.deal_type == DEAL_TYPE_BUY || trans.deal_type == DEAL_TYPE_SELL)
         {
            PrintFormat("[EddyTrader][WARN] INTERVENÇÃO MANUAL DETECTADA em %s: Negócio #%I64u executado! Neutralizando imediatamente.",
                        EnumToString(g_current_state), trans.deal);
            ExecuteGlobalLiquidation(false);
         }
      }
      else if(trans.type == TRADE_TRANSACTION_ORDER_ADD)
      {
         PrintFormat("[EddyTrader][WARN] INTERVENÇÃO MANUAL DETECTADA em %s: Ordem pendente #%I64u adicionada! Cancelando imediatamente.",
                     EnumToString(g_current_state), trans.order);
         CancelPendingOrders(false);
      }
   }

   ProcessFSM();
}

void OnTrade()
{
   // Reconciliação secundária de integridade de inventário
   if(g_current_state == EDDY_STATE_BLOCKED || g_current_state == EDDY_STATE_LIQUIDATING)
   {
      if(PositionsTotal() > 0 || OrdersTotal() > 0)
      {
         ExecuteGlobalLiquidation(false);
      }
   }

   ProcessFSM();
}

//+------------------------------------------------------------------+
//| Evento de Gráfico: Interação do Trader com o HUD no Gráfico      |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   // 1. Suporte a pressionamento de ENTER no campo de edição (CHARTEVENT_OBJECT_ENDEDIT)
   if(id == CHARTEVENT_OBJECT_ENDEDIT && sparam == EDDY_UI_PREFIX + "Dlg_Input")
   {
      if(g_config_ui_state == UI_STATE_EDITING)
      {
         string txt = ObjectGetString(0, sparam, OBJPROP_TEXT);
         double val = 0.0;
         if(!ParseMoneyInput(txt, val) || val <= 0.0)
         {
            g_config_error_msg = "Valor invalido! Digite valor > 0.";
            int dx = 0, dy = 0;
            GetDialogPosition(dx, dy);
            UI_SetLabel(EDDY_UI_PREFIX + "Dlg_Err", dx + 14, dy + 112, g_config_error_msg, C'240,80,80', 8);
            ChartRedraw(0);
         }
         else
         {
            g_pending_max_loss = val;
            g_config_error_msg = "";
            UI_ShowConfirmDialog();
         }
      }
      return;
   }

   // 2. Cliques em botões interativos
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      // Botão CONFIGURAR no HUD
      if(sparam == EDDY_UI_PREFIX + "Hud_Btn_Config" || sparam == EDDY_UI_PREFIX + "Btn_Config")
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         if(g_current_state == EDDY_STATE_MONITORING && g_safe_to_operate && g_is_owner)
         {
            if(g_config_ui_state == UI_STATE_IDLE)
               UI_OpenConfigDialog();
            else
               UI_CloseConfigDialog();
         }
         else
         {
            Print("[EddyTrader][WARN] Configuração de limite indisponível fora de MONITORING seguro.");
         }
         return;
      }

      // Botão DETALHES no HUD ou retorno no Detalhado
      if(sparam == EDDY_UI_PREFIX + "Hud_Btn_Details" || sparam == EDDY_UI_PREFIX + "Det_Btn_Back" || sparam == EDDY_UI_PREFIX + "Btn_Mode")
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         if(g_hud_mode == EDDY_HUD_COMPACT)
         {
            UI_CloseConfigDialog();
            UI_DeleteHUD();
            g_hud_mode = EDDY_HUD_DETAILED;
            g_last_expanded_hud_mode = EDDY_HUD_DETAILED;
            Comment("");
         }
         else
         {
            UI_DeleteDetailed();
            g_hud_mode = EDDY_HUD_COMPACT;
            g_last_expanded_hud_mode = EDDY_HUD_COMPACT;
            Comment("");
         }
         UpdateHUD();
         return;
      }

      // Botão MINIMIZAR no Compacto
      if(sparam == EDDY_UI_PREFIX + "Hud_Btn_Min")
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         g_last_expanded_hud_mode = EDDY_HUD_COMPACT;
         UI_CloseConfigDialog();
         UI_DeleteHUD();
         SetPanelState(PANEL_COLLAPSED);
         UpdateHUD();
         return;
      }

      // Botão MINIMIZAR no Detalhado
      if(sparam == EDDY_UI_PREFIX + "Det_Btn_Min")
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         g_last_expanded_hud_mode = EDDY_HUD_DETAILED;
         UI_DeleteDetailed();
         SetPanelState(PANEL_COLLAPSED);
         UpdateHUD();
         return;
      }

      // Botão MAXIMIZAR na faixa minimizada
      if(sparam == EDDY_UI_PREFIX + "Min_Btn_Expand")
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         UI_DeleteCollapsed();
         SetPanelState(PANEL_EXPANDED);
         g_hud_mode = g_last_expanded_hud_mode;
         UpdateHUD();
         return;
      }

      // Botão AVANÇAR na janela de edição
      if(sparam == EDDY_UI_PREFIX + "Dlg_Btn_Next" || sparam == EDDY_UI_PREFIX + "Modal_Btn_Save")
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         string input_obj = EDDY_UI_PREFIX + "Dlg_Input";
         string txt = ObjectGetString(0, input_obj, OBJPROP_TEXT);
         double val = 0.0;
         if(!ParseMoneyInput(txt, val) || val <= 0.0)
         {
            g_config_error_msg = "Valor invalido! Digite valor > 0.";
            int dx = 0, dy = 0;
            GetDialogPosition(dx, dy);
            UI_SetLabel(EDDY_UI_PREFIX + "Dlg_Err", dx + 14, dy + 112, g_config_error_msg, C'240,80,80', 8);
            ChartRedraw(0);
         }
         else
         {
            g_pending_max_loss = val;
            g_config_error_msg = "";
            UI_ShowConfirmDialog();
         }
         return;
      }

      // Botão CANCELAR na janela de edição
      if(sparam == EDDY_UI_PREFIX + "Dlg_Btn_Cancel" || sparam == EDDY_UI_PREFIX + "Modal_Btn_Cancel")
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         UI_CloseConfigDialog();
         UpdateHUD();
         return;
      }

      // Botão VOLTAR na janela de confirmação
      if(sparam == EDDY_UI_PREFIX + "Dlg_Btn_Back")
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         UI_BackToEditing();
         return;
      }

      // Botão CONFIRMAR na janela de confirmação
      if(sparam == EDDY_UI_PREFIX + "Dlg_Btn_Confirm" || sparam == EDDY_UI_PREFIX + "Modal_Btn_Confirm")
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         string err = "";
         if(SetMaxLossConfig(g_pending_max_loss, err))
         {
            UI_CloseConfigDialog();
            g_config_feedback_msg = StringFormat("Limite atualizado para %.2f!", g_max_loss);
            g_config_feedback_expiry = GetServerTimeSafe() + 5;
            UpdateHUD();
         }
         else
         {
            UI_BackToEditing();
            g_config_error_msg = err;
            int dx = 0, dy = 0;
            GetDialogPosition(dx, dy);
            UI_SetLabel(EDDY_UI_PREFIX + "Dlg_Err", dx + 14, dy + 112, g_config_error_msg, C'240,80,80', 8);
            ChartRedraw(0);
         }
         return;
      }
   }
}
//+------------------------------------------------------------------+
