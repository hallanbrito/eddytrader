//+------------------------------------------------------------------+
//|                                                   EddyTrader.mq5 |
//|                                  Copyright 2026, EddyTrader Team |
//|                                             https://eddytrader.io |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026, EddyTrader Team"
#property link        "https://eddytrader.io"
#property version     "1.00"
#property description "EddyTrader 1.0.0-rc2 - Núcleo Autônomo de Proteção de Capital e Gerenciador de Perda Diária"
#property strict

//--- Definições Formais do Produto e Versão
#define EDDY_PRODUCT_NAME "EddyTrader"
#define EDDY_VERSION      "1.0.0-rc2"
#define EDDY_PURPOSE      "Gerenciador de Risco Operacional e Limite de Perda Diária (MQL5 Nativo)"

//--- Definições de Interface Gráfica (HUD)
#define EDDY_UI_PREFIX "EddyHUD_"

enum ENUM_EDDY_HUD_MODE
{
   EDDY_HUD_COMPACT   = 0, // Painel Compacto Trader (Interativo, no Gráfico)
   EDDY_HUD_DETAILED  = 1, // Painel Técnico Detalhado (Auditoria / Engenharia)
   EDDY_HUD_OFF       = 2  // HUD Desativado (Sem elementos no gráfico)
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
input int                InpHudOffsetY = 30;                     // Distância Vertical (Y) em Pixels

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
double               g_max_loss               = 500.0;
ENUM_EDDY_HUD_MODE   g_hud_mode               = EDDY_HUD_COMPACT;
ENUM_CONFIG_UI_STATE g_config_ui_state        = UI_STATE_IDLE;
double               g_pending_max_loss       = 0.0;
string               g_config_feedback_msg    = "";
datetime             g_config_feedback_expiry = 0;
string               g_config_error_msg       = "";

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
void UI_SetRect(const string name, int x, int y, int w, int h, color bg_clr, color border_clr = clrNONE)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, InpHudCorner);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, InpHudOffsetX + x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, InpHudOffsetY + y);
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
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, InpHudOffsetX + x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, InpHudOffsetY + y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Bold" : "Segoe UI");
}

void UI_SetButton(const string name, int x, int y, int w, int h, const string text, color bg_clr, color text_clr, int font_size = 8)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, InpHudCorner);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, InpHudOffsetX + x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, InpHudOffsetY + y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg_clr);
   ObjectSetInteger(0, name, OBJPROP_COLOR, text_clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI");
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
}

void UI_SetEdit(const string name, int x, int y, int w, int h, const string text, color bg_clr, color text_clr, int font_size = 9)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, InpHudCorner);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_READONLY, false);
      ObjectSetInteger(0, name, OBJPROP_ALIGN, ALIGN_CENTER);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, InpHudOffsetX + x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, InpHudOffsetY + y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
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

void UI_DeleteModal()
{
   ObjectDelete(0, EDDY_UI_PREFIX + "Modal_Bg");
   ObjectDelete(0, EDDY_UI_PREFIX + "Modal_Title");
   ObjectDelete(0, EDDY_UI_PREFIX + "Modal_Cur");
   ObjectDelete(0, EDDY_UI_PREFIX + "Modal_Lbl");
   ObjectDelete(0, EDDY_UI_PREFIX + "Modal_Input");
   ObjectDelete(0, EDDY_UI_PREFIX + "Modal_Err");
   ObjectDelete(0, EDDY_UI_PREFIX + "Modal_Btn_Save");
   ObjectDelete(0, EDDY_UI_PREFIX + "Modal_Btn_Cancel");
   ObjectDelete(0, EDDY_UI_PREFIX + "Modal_Btn_Confirm");
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Renderizadores dos Modos Visuais de Interface                    |
//+------------------------------------------------------------------+
void RenderConfigDialog()
{
   string curr = AccountInfoString(ACCOUNT_CURRENCY);

   if(g_config_ui_state == UI_STATE_EDITING)
   {
      UI_SetRect(EDDY_UI_PREFIX + "Modal_Bg", 0, 0, 260, 180, C'20,24,35', C'0,150,214');
      UI_SetLabel(EDDY_UI_PREFIX + "Modal_Title", 14, 12, "ALTERAR LIMITE DE PERDA", clrWhite, 9, true);
      UI_SetLabel(EDDY_UI_PREFIX + "Modal_Cur", 14, 36, StringFormat("Limite Atual: %.2f %s", g_max_loss, curr), C'180,190,200', 8);
      UI_SetLabel(EDDY_UI_PREFIX + "Modal_Lbl", 14, 58, "Novo Limite (ex: 750.00):", clrWhite, 8);

      string input_obj = EDDY_UI_PREFIX + "Modal_Input";
      if(ObjectFind(0, input_obj) < 0)
      {
         UI_SetEdit(input_obj, 14, 78, 232, 24, DoubleToString(g_max_loss, 2), C'30,35,48', clrWhite, 9);
      }

      string err_txt = (g_config_error_msg != "") ? g_config_error_msg : "Digite o novo valor desejado";
      color err_clr  = (g_config_error_msg != "") ? C'240,80,80' : C'140,150,165';
      UI_SetLabel(EDDY_UI_PREFIX + "Modal_Err", 14, 108, err_txt, err_clr, 8);

      UI_SetButton(EDDY_UI_PREFIX + "Modal_Btn_Save", 14, 138, 110, 26, "AVANCAR", C'0,122,204', clrWhite, 8);
      UI_SetButton(EDDY_UI_PREFIX + "Modal_Btn_Cancel", 136, 138, 110, 26, "CANCELAR", C'60,65,75', clrWhite, 8);
      ObjectDelete(0, EDDY_UI_PREFIX + "Modal_Btn_Confirm");
   }
   else if(g_config_ui_state == UI_STATE_CONFIRMING)
   {
      UI_SetRect(EDDY_UI_PREFIX + "Modal_Bg", 0, 0, 260, 180, C'20,24,35', C'243,156,18');
      UI_SetLabel(EDDY_UI_PREFIX + "Modal_Title", 14, 12, "CONFIRMAR ALTERACAO", clrGold, 9, true);
      UI_SetLabel(EDDY_UI_PREFIX + "Modal_Cur", 14, 38, StringFormat("Limite Atual: %.2f %s", g_max_loss, curr), C'180,190,200', 8);
      UI_SetLabel(EDDY_UI_PREFIX + "Modal_Lbl", 14, 62, StringFormat("NOVO LIMITE: %.2f %s", g_pending_max_loss, curr), clrWhite, 9, true);
      UI_SetLabel(EDDY_UI_PREFIX + "Modal_Err", 14, 95, "Deseja aplicar o novo limite?", C'220,220,220', 8);

      ObjectDelete(0, EDDY_UI_PREFIX + "Modal_Input");
      ObjectDelete(0, EDDY_UI_PREFIX + "Modal_Btn_Save");
      UI_SetButton(EDDY_UI_PREFIX + "Modal_Btn_Confirm", 14, 138, 110, 26, "SIM, APLICAR", C'39,174,96', clrWhite, 8);
      UI_SetButton(EDDY_UI_PREFIX + "Modal_Btn_Cancel", 136, 138, 110, 26, "CANCELAR", C'60,65,75', clrWhite, 8);
   }
   ChartRedraw(0);
}

void RenderCompactHUD()
{
   Comment(""); // Mantém área de comentário limpa no modo compacto

   if(g_config_ui_state != UI_STATE_IDLE)
   {
      RenderConfigDialog();
      return;
   }

   // Limpa qualquer modal residual
   UI_DeleteModal();

   datetime t_now = GetServerTimeSafe();
   double R_day   = CalculateRealizedResultToday(g_day_start, t_now);
   double F       = CalculateFloatingResult();
   double D       = R_day + F;
   double W       = CalculateWindowResult(D, g_baseline);
   string curr    = AccountInfoString(ACCOUNT_CURRENCY);
   string mode_str = (AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL) ? "REAL" : "DEMO";

   // Cartão base
   UI_SetRect(EDDY_UI_PREFIX + "CardBg", 0, 0, 260, 180, C'24,28,37', C'45,55,72');
   UI_SetLabel(EDDY_UI_PREFIX + "Title", 14, 12, "EDDYTRADER", C'0,180,216', 9, true);
   UI_SetLabel(EDDY_UI_PREFIX + "Mode", 175, 13, StringFormat("v%s [%s]", EDDY_VERSION, mode_str), C'140,150,165', 7);

   // Linha de Status
   UI_SetLabel(EDDY_UI_PREFIX + "Status_Lbl", 14, 36, "Status:", C'160,170,185', 8);
   string status_str = GetHumanStateName(g_current_state);
   color status_clr  = clrWhite;
   switch(g_current_state)
   {
      case EDDY_STATE_MONITORING:           status_clr = C'46,204,113'; break; // Verde esmeralda
      case EDDY_STATE_PROTECTION_TRIGGERED:
      case EDDY_STATE_LIQUIDATING:          status_clr = C'231,76,60';  break; // Vermelho
      case EDDY_STATE_BLOCKED:              status_clr = C'243,156,18'; break; // Laranja âmbar
      default:                              status_clr = clrGold;       break;
   }
   if(!g_is_owner || !g_safe_to_operate)
   {
      status_str = "FAIL-CLOSED";
      status_clr = clrRed;
   }
   UI_SetLabel(EDDY_UI_PREFIX + "Status_Val", 85, 35, status_str, status_clr, 9, true);

   // Linha de Limite de Perda
   UI_SetLabel(EDDY_UI_PREFIX + "Limit_Lbl", 14, 58, "Limite Perda:", C'160,170,185', 8);
   UI_SetLabel(EDDY_UI_PREFIX + "Limit_Val", 100, 58, StringFormat("-%.2f %s", g_max_loss, curr), clrWhite, 8, true);

   // Linha de Resultado da Janela (W)
   UI_SetLabel(EDDY_UI_PREFIX + "Win_Lbl", 14, 78, "Perda Janela:", C'160,170,185', 8);
   color w_clr = (W >= 0) ? C'46,204,113' : ((W <= -g_max_loss * 0.7) ? C'231,76,60' : C'243,156,18');
   UI_SetLabel(EDDY_UI_PREFIX + "Win_Val", 100, 78, StringFormat("%+.2f %s", W, curr), w_clr, 8, true);

   // Linha de Resultado Consolidado do Dia (D)
   UI_SetLabel(EDDY_UI_PREFIX + "Day_Lbl", 14, 98, "Total do Dia:", C'160,170,185', 8);
   color d_clr = (D >= 0) ? C'46,204,113' : C'231,76,60';
   UI_SetLabel(EDDY_UI_PREFIX + "Day_Val", 100, 98, StringFormat("%+.2f %s", D, curr), d_clr, 8, true);

   // Linha de Mensagem / Bloqueio / Feedback
   string sub_msg = "";
   color  sub_clr = C'120,130,145';
   if(g_current_state == EDDY_STATE_BLOCKED || g_current_state == EDDY_STATE_LIQUIDATING || g_current_state == EDDY_STATE_PROTECTION_TRIGGERED)
   {
      long rem_sec = (long)(g_t_unlock - t_now);
      if(rem_sec < 0) rem_sec = 0;
      int h = (int)(rem_sec / 3600);
      int m = (int)((rem_sec % 3600) / 60);
      int s = (int)(rem_sec % 60);
      sub_msg = StringFormat("Bloqueio restante: %02d:%02d:%02d", h, m, s);
      sub_clr = C'243,156,18';
   }
   else if(g_config_feedback_msg != "" && t_now <= g_config_feedback_expiry)
   {
      sub_msg = g_config_feedback_msg;
      sub_clr = C'46,204,113';
   }
   else
   {
      sub_msg = StringFormat("Janela J%d | Baseline: %.2f", g_window_id, g_baseline);
      sub_clr = C'120,130,145';
   }
   UI_SetLabel(EDDY_UI_PREFIX + "Msg", 14, 118, sub_msg, sub_clr, 8);

   // Botões Interativos
   bool can_configure = (g_current_state == EDDY_STATE_MONITORING && g_safe_to_operate && g_is_owner);
   if(can_configure)
   {
      UI_SetButton(EDDY_UI_PREFIX + "Btn_Config", 14, 142, 140, 24, "CONFIGURAR LIMITE", C'0,122,204', clrWhite, 8);
   }
   else
   {
      UI_SetButton(EDDY_UI_PREFIX + "Btn_Config", 14, 142, 140, 24, "LIMITE BLOQUEADO", C'50,55,65', C'120,125,135', 8);
   }
   UI_SetButton(EDDY_UI_PREFIX + "Btn_Mode", 160, 142, 86, 24, "DETALHES", C'45,55,72', clrWhite, 8);

   ChartRedraw(0);
}

void RenderDetailedHUD()
{
   // Limpa objetos do painel compacto e modais
   UI_DeleteModal();
   ObjectDelete(0, EDDY_UI_PREFIX + "CardBg");
   ObjectDelete(0, EDDY_UI_PREFIX + "Title");
   ObjectDelete(0, EDDY_UI_PREFIX + "Mode");
   ObjectDelete(0, EDDY_UI_PREFIX + "Status_Lbl");
   ObjectDelete(0, EDDY_UI_PREFIX + "Status_Val");
   ObjectDelete(0, EDDY_UI_PREFIX + "Limit_Lbl");
   ObjectDelete(0, EDDY_UI_PREFIX + "Limit_Val");
   ObjectDelete(0, EDDY_UI_PREFIX + "Win_Lbl");
   ObjectDelete(0, EDDY_UI_PREFIX + "Win_Val");
   ObjectDelete(0, EDDY_UI_PREFIX + "Day_Lbl");
   ObjectDelete(0, EDDY_UI_PREFIX + "Day_Val");
   ObjectDelete(0, EDDY_UI_PREFIX + "Msg");
   ObjectDelete(0, EDDY_UI_PREFIX + "Btn_Config");

   // Botão para retornar ao compacto
   UI_SetButton(EDDY_UI_PREFIX + "Btn_Mode", 10, 10, 160, 24, "[ PAINEL COMPACTO ]", C'0,122,204', clrWhite, 8);
   ChartRedraw(0);

   datetime t_now = GetServerTimeSafe();
   double R_day = CalculateRealizedResultToday(g_day_start, t_now);
   double F = CalculateFloatingResult();
   double D = R_day + F;
   double W = CalculateWindowResult(D, g_baseline);

   string lock_info = "Nenhum bloqueio ativo";
   if(g_current_state == EDDY_STATE_BLOCKED || g_current_state == EDDY_STATE_LIQUIDATING || g_current_state == EDDY_STATE_PROTECTION_TRIGGERED)
   {
      long remaining_sec = (long)(g_t_unlock - t_now);
      if(remaining_sec < 0) remaining_sec = 0;
      int hours = (int)(remaining_sec / 3600);
      int mins  = (int)((remaining_sec % 3600) / 60);
      int secs  = (int)(remaining_sec % 60);
      lock_info = StringFormat("Desbloqueio: %s (Restante: %02d:%02d:%02d)",
                               TimeToString(g_t_unlock, TIME_DATE|TIME_SECONDS),
                               hours, mins, secs);
   }

   string fail_closed_banner = "";
   if(!g_is_owner || (!g_safe_to_operate && g_current_state != EDDY_STATE_MONITORING))
   {
      fail_closed_banner = ">>> ATENCAO: OPERACAO BLOQUEADA / FAIL-CLOSED <<<\n";
   }

   string auth_str = (!g_is_owner) ? "NAO (OWNERSHIP PERDIDA / FAIL-CLOSED)" :
                     ((g_current_state == EDDY_STATE_MONITORING && g_safe_to_operate) ? "SIM (NOMINAL)" : "NAO (BLOQUEADO/FAIL-CLOSED)");
   string mode_str = (AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL) ? "REAL" : "DEMO";

   string hud = StringFormat(
      "====================================================\n"
      " %s v%s - Release Candidate 2\n"
      " %s\n"
      "====================================================\n"
      "%s"
      " Conta: %I64u | Modo: %s | Servidor: %s\n"
      " Instancia: #%I64u (Owner: %s)\n"
      " Horario Servidor: %s\n"
      "----------------------------------------------------\n"
      " Estado FSM: %s (%s)\n"
      " Janela Ativa: J%d | Baseline (Bn): %.2f\n"
      " Perda Maxima Efetiva (L): -%.2f\n"
      "----------------------------------------------------\n"
      " R_day (Realizado Hoje):    %.2f %s\n"
      " F(t)  (Flutuante Liquido): %.2f %s\n"
      " D(t)  (Consolidado Hoje):  %.2f %s\n"
      " W_n(t)(Resultado Janela):  %.2f %s\n"
      "----------------------------------------------------\n"
      " Status de Protecao: %s\n"
      " ID do Evento: %I64u\n"
      " Informacao de Bloqueio: %s\n"
      " Posicoes Abertas: %d | Ordens Pendentes: %d\n"
      " Negociacao Autorizada: %s\n"
      "====================================================",
      EDDY_PRODUCT_NAME, EDDY_VERSION,
      EDDY_PURPOSE,
      fail_closed_banner,
      g_account_login,
      mode_str,
      AccountInfoString(ACCOUNT_SERVER),
      g_instance_id,
      (g_is_owner ? "SIM" : "NAO"),
      TimeToString(t_now, TIME_DATE|TIME_SECONDS),
      EnumToString(g_current_state), GetHumanStateName(g_current_state),
      g_window_id, g_baseline,
      g_max_loss,
      R_day, AccountInfoString(ACCOUNT_CURRENCY),
      F, AccountInfoString(ACCOUNT_CURRENCY),
      D, AccountInfoString(ACCOUNT_CURRENCY),
      W, AccountInfoString(ACCOUNT_CURRENCY),
      (g_current_state == EDDY_STATE_MONITORING ? "NOMINAL / VIGILANTE" : "PROTECAO ATIVADA"),
      g_protection_event_id,
      lock_info,
      PositionsTotal(), OrdersTotal(),
      auth_str
   );

   Comment(hud);
}

void RenderOffHUD()
{
   UI_DeleteAll();

   // OFF + fail-closed / erro operacional crítico -> aviso textual mínimo de segurança
   if(!g_is_owner || !g_safe_to_operate)
   {
      string critical_msg = StringFormat(
         ">>> ATENCAO: EDDYTRADER EM FAIL-CLOSED / OPERACAO BLOQUEADA <<<\n"
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
   switch(g_hud_mode)
   {
      case EDDY_HUD_OFF:      RenderOffHUD();      break;
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
   Print("[EddyTrader][INFO] ==================================================");
   PrintFormat("[EddyTrader][INFO] Inicializando %s v%s - Release Candidate 2", EDDY_PRODUCT_NAME, EDDY_VERSION);
   PrintFormat("[EddyTrader][INFO] %s", EDDY_PURPOSE);
   Print("[EddyTrader][INFO] ==================================================");

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
      Print("[EddyTrader][WARN] ATENÇÃO: Conta REAL detectada! O EddyTrader atuará em modo de proteção absoluta de capital.");
   }
   else
   {
      Print("[EddyTrader][INFO] Modo de conta DEMO / TESTE detectado.");
   }

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      Print("[EddyTrader][WARN] AVISO: 'Algo Trading' está DESATIVADO nas opções do terminal MT5.");
   }
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
   {
      Print("[EddyTrader][WARN] AVISO: Negociação desativada para a conta atual.");
   }

   // 3. Guarda de Instância Única por Conta (OWNER + HEARTBEAT Atômico via CAS)
   if(!AcquireInstanceGuard())
   {
      return INIT_FAILED;
   }

   // 4. Resolução do Limite Efetivo de Perda e Configuração de Interface
   g_hud_mode = InpHudMode;
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

         // T03: Exposição residual aberta tem precedência absoluta
         if(PositionsTotal() > 0 || OrdersTotal() > 0)
         {
            PrintFormat("[EddyTrader][WARN] T03: Exposição residual aberta detectada pós-restart durante proteção. Forçando LIQUIDATING.");
            g_current_state = EDDY_STATE_LIQUIDATING;
         }
         else
         {
            if(t_now < g_t_unlock)
            {
               // T02A: Bloqueio ativo mantido
               PrintFormat("[EddyTrader][INFO] T02A: Bloqueio temporal mantido pós-restart (%d s restantes).",
                           (int)(g_t_unlock - t_now));
               g_current_state = EDDY_STATE_BLOCKED;
            }
            else
            {
               // t_now >= g_t_unlock
               if(CheckSafetyConditions())
               {
                  // T02C: Reabertura imediata pós-restart: INIT -> REOPENING -> MONITORING
                  PrintFormat("[EddyTrader][INFO] T02C: Bloqueio vencido e condições seguras. Conduzindo formalmente INIT -> REOPENING -> MONITORING.");
                  TransitionTo(EDDY_STATE_REOPENING);
               }
               else
               {
                  // T02B: Bloqueio retido por falta de segurança
                  PrintFormat("[EddyTrader][WARN] T02B: Bloqueio vencido mas ambiente inseguro (pos=%d, ord=%d). Retendo em BLOCKED.",
                              PositionsTotal(), OrdersTotal());
                  g_current_state = EDDY_STATE_BLOCKED;
               }
            }
         }
      }
      else if(rec.state == EDDY_STATE_MONITORING)
      {
         // Verifica se houve virada de dia durante o terminal desligado
         datetime persisted_day = rec.day_timestamp;
         if(persisted_day < g_day_start)
         {
            PrintFormat("[EddyTrader][INFO] T05: Novo dia operacional detectado pós-restart (%s < %s). Iniciando J0 com B0=0.",
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
                  PrintFormat("[EddyTrader][CRITICAL] (FAIL-CLOSED): Janela J%d ativa mas Baseline Bn ausente nas Global Variables! Operações retidas em INIT.",
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
            PrintFormat("[EddyTrader][INFO] MONITORING reconstituído com sucesso: Janela J%d | Baseline Bn=%.2f",
                        g_window_id, g_baseline);
         }
      }
      else
      {
         g_current_state = rec.state;
      }
   }
   else
   {
      // Inicialização limpa (primeira vez na conta)
      PrintFormat("[EddyTrader][INFO] Inicialização limpa na conta %I64u. Iniciando J0 com B0=0.0", g_account_login);
      g_current_state   = EDDY_STATE_MONITORING;
      g_window_id       = 0;
      g_baseline        = 0.0;
      g_safe_to_operate = true;
   }

   PersistState();

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
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == EDDY_UI_PREFIX + "Btn_Config")
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         if(g_current_state == EDDY_STATE_MONITORING && g_safe_to_operate && g_is_owner)
         {
            g_config_ui_state = UI_STATE_EDITING;
            g_config_error_msg = "";
            UpdateHUD();
         }
         else
         {
            Print("[EddyTrader][WARN] Configuração de limite indisponível fora de MONITORING.");
         }
      }
      else if(sparam == EDDY_UI_PREFIX + "Btn_Mode")
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         if(g_hud_mode == EDDY_HUD_COMPACT)
         {
            g_hud_mode = EDDY_HUD_DETAILED;
         }
         else
         {
            g_hud_mode = EDDY_HUD_COMPACT;
            Comment("");
         }
         UI_DeleteAll();
         UpdateHUD();
      }
      else if(sparam == EDDY_UI_PREFIX + "Modal_Btn_Save")
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         string input_obj = EDDY_UI_PREFIX + "Modal_Input";
         string txt = ObjectGetString(0, input_obj, OBJPROP_TEXT);
         double val = 0.0;
         if(!ParseMoneyInput(txt, val) || val <= 0.0)
         {
            g_config_error_msg = "Valor inválido! Digite valor > 0.";
            UpdateHUD();
         }
         else
         {
            g_pending_max_loss = val;
            g_config_ui_state  = UI_STATE_CONFIRMING;
            g_config_error_msg = "";
            UpdateHUD();
         }
      }
      else if(sparam == EDDY_UI_PREFIX + "Modal_Btn_Confirm")
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         string err = "";
         if(SetMaxLossConfig(g_pending_max_loss, err))
         {
            g_config_ui_state = UI_STATE_IDLE;
            g_config_feedback_msg = StringFormat("Limite atualizado para %.2f!", g_max_loss);
            g_config_feedback_expiry = GetServerTimeSafe() + 5;
            g_pending_max_loss = 0.0;
            g_config_error_msg = "";
            UI_DeleteModal();
            UpdateHUD();
         }
         else
         {
            g_config_ui_state = UI_STATE_EDITING;
            g_config_error_msg = err;
            UpdateHUD();
         }
      }
      else if(sparam == EDDY_UI_PREFIX + "Modal_Btn_Cancel")
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         g_config_ui_state = UI_STATE_IDLE;
         g_pending_max_loss = 0.0;
         g_config_error_msg = "";
         UI_DeleteModal();
         UpdateHUD();
      }
   }
}
//+------------------------------------------------------------------+
