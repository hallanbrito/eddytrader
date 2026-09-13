//+------------------------------------------------------------------+
//|                                                   EddyTrader.mq5 |
//|                                  Copyright 2026, EddyTrader Team |
//|                                             https://eddytrader.io |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026, EddyTrader Team"
#property link        "https://eddytrader.io"
#property version     "1.00"
#property description "EddyTrader - Núcleo Autônomo de Proteção de Capital e Gerenciamento de Perda Diária"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Parâmetros de Entrada (Inputs Mínimos Normativos)                |
//+------------------------------------------------------------------+
input group "=== Configurações de Risco ==="
input double InpMaxLoss            = 500.0; // Perda Máxima Permitida por Janela (Moeda da Conta, > 0)
input int    InpBlockDurationHours = 4;     // Duração Contínua do Bloqueio (Horas, min 1)

input group "=== Configurações Operacionais ==="
input int    InpTimerIntervalMs    = 500;   // Intervalo de Varredura do Timer (Milissegundos)
input ulong  InpDeviationPoints    = 10;    // Desvio Máximo / Slippage Tolerado (Pontos)

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
//| Variáveis Globais de Estado Operacional                          |
//+------------------------------------------------------------------+
ENUM_EDDY_STATE g_current_state         = EDDY_STATE_INIT;
int             g_window_id             = 0;
double          g_baseline              = 0.0;
datetime        g_t_trigger             = 0;
datetime        g_t_unlock              = 0;
ulong           g_protection_event_id   = 0;
datetime        g_day_start             = 0;
bool            g_safe_to_operate       = false;

ulong           g_account_login         = 0;
ulong           g_instance_id           = 0;
bool            g_is_owner              = false;
CTrade          g_trade;

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

void PersistState()
{
   GlobalVariableSet(GVKey("STATE"), (double)g_current_state);
   GlobalVariableSet(GVKey("WINDOW_ID"), (double)g_window_id);
   GlobalVariableSet(GVKey("BASELINE"), g_baseline);
   GlobalVariableSet(GVKey("T_TRIGGER"), (double)g_t_trigger);
   GlobalVariableSet(GVKey("T_UNLOCK"), (double)g_t_unlock);
   GlobalVariableSet(GVKey("EVENT_ID"), (double)g_protection_event_id);
   GlobalVariableSet(GVKey("DAY"), (double)g_day_start);
   GlobalVariablesFlush();
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

   // 1. Se a chave de owner não existe, tenta posse inicial
   if(!GlobalVariableCheck(owner_key))
   {
      GlobalVariableSet(owner_key, (double)g_instance_id);
      GlobalVariableSet(hb_key, (double)now);
      GlobalVariablesFlush();

      if(GlobalVariableCheck(owner_key) && (ulong)GlobalVariableGet(owner_key) == g_instance_id)
      {
         g_is_owner = true;
         PrintFormat("[EddyTrader] Guarda adquirida com sucesso (Posse Inicial): InstanceID=#%I64u na conta %I64u",
                     g_instance_id, g_account_login);
         return true;
      }
   }

   // 2. Se a chave de owner existe, verifica o proprietário
   ulong current_owner = (ulong)GlobalVariableGet(owner_key);

   // Mesma instância readquirindo (ex: recarga / troca de timeframe)
   if(current_owner == g_instance_id)
   {
      GlobalVariableSet(hb_key, (double)now);
      GlobalVariablesFlush();
      g_is_owner = true;
      return true;
   }

   // 3. Outro proprietário registrado: inspeciona validade do heartbeat
   if(GlobalVariableCheck(hb_key))
   {
      datetime last_hb = (datetime)GlobalVariableGet(hb_key);
      if(now >= last_hb && (now - last_hb) < 5)
      {
         // Lease ativa de outro proprietário legítimo: rejeição obrigatória
         PrintFormat("[EddyTrader] ERRO FATAL: Instância concorrente ativa detectada na conta %I64u (Owner=#%I64u, heartbeat há %d s). Abortando carga.",
                     g_account_login, current_owner, (int)(now - last_hb));
         g_is_owner = false;
         return false;
      }
   }

   // 4. Heartbeat expirado (> 5s): tentativa de takeover atômico via Compare-And-Swap (CAS)
   PrintFormat("[EddyTrader] AVISO: Lease da instância anterior (#%I64u) expirada. Tentando takeover atômico...",
               current_owner);

   if(GlobalVariableSetOnCondition(owner_key, (double)g_instance_id, (double)current_owner))
   {
      // Takeover atômico bem-sucedido
      GlobalVariableSet(hb_key, (double)now);
      GlobalVariablesFlush();
      g_is_owner = true;
      PrintFormat("[EddyTrader] Takeover de guarda concluído! Novo Owner=#%I64u na conta %I64u",
                  g_instance_id, g_account_login);
      return true;
   }
   else
   {
      // Outra instância assumiu durante a tentativa
      PrintFormat("[EddyTrader] ERRO FATAL: Conflito no takeover da guarda. Outra instância assumiu ownership. Abortando carga.");
      g_is_owner = false;
      return false;
   }
}

void UpdateHeartbeat()
{
   if(!g_is_owner)
      return;

   string owner_key = GVKey("INSTANCE_OWNER");
   if(!GlobalVariableCheck(owner_key) || (ulong)GlobalVariableGet(owner_key) != g_instance_id)
   {
      // PERDA DE OWNERSHIP DETECTADA (Takeover ocorreu) -> FAIL-CLOSED
      PrintFormat("[EddyTrader] ERRO CRÍTICO: Perda de ownership detectada na instância #%I64u! Outra instância assumiu o controle. Entrando em FAIL-CLOSED.",
                  g_instance_id);
      g_is_owner        = false;
      g_safe_to_operate = false;
      g_current_state   = EDDY_STATE_INIT;
      // Invariante de contenção: não encerra posições, não altera FSM da conta e não altera o lock de terceiros
      return;
   }

   GlobalVariableSet(GVKey("HEARTBEAT"), (double)TimeCurrent());
}

void ReleaseInstanceGuard()
{
   // REGRA DE SEGURANÇA: Somente o proprietário legítimo pode liberar a guarda
   if(!g_is_owner)
   {
      PrintFormat("[EddyTrader] OnDeinit: Instância #%I64u NÃO é proprietária do lock. Guarda preservada intacta.",
                  g_instance_id);
      return;
   }

   string owner_key = GVKey("INSTANCE_OWNER");
   if(GlobalVariableCheck(owner_key) && (ulong)GlobalVariableGet(owner_key) == g_instance_id)
   {
      GlobalVariableDel(owner_key);
      GlobalVariableDel(GVKey("HEARTBEAT"));
      GlobalVariablesFlush();
      PrintFormat("[EddyTrader] Guarda liberada com sucesso pela instância proprietária #%I64u.",
                  g_instance_id);
   }
   g_is_owner = false;
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
      PrintFormat("[EddyTrader] AVISO: HistorySelect(%s, %s) falhou. Erro: %d",
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
int CancelPendingOrders()
{
   int fail_count = 0;
   int total_orders = OrdersTotal();
   if(total_orders <= 0) return 0;

   ulong order_tickets[];
   ArrayResize(order_tickets, total_orders);
   for(int i = 0; i < total_orders; i++)
   {
      order_tickets[i] = OrderGetTicket(i);
   }

   for(int i = 0; i < total_orders; i++)
   {
      ulong ticket = order_tickets[i];
      if(ticket > 0)
      {
         if(!g_trade.OrderDelete(ticket))
         {
            fail_count++;
            PrintFormat("[EddyTrader] FALHA ao cancelar ordem pendente #%I64u: Retcode %u (%s)",
                        ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
         }
         else
         {
            PrintFormat("[EddyTrader] Ordem pendente #%I64u cancelada com sucesso.", ticket);
         }
      }
   }
   return fail_count;
}

int ExecuteGlobalLiquidation()
{
   int fail_count = 0;

   // 1. Coleta prévia e estável de todos os tickets de posições abertas
   int total_pos = PositionsTotal();
   if(total_pos > 0)
   {
      ulong pos_tickets[];
      ArrayResize(pos_tickets, total_pos);
      for(int i = 0; i < total_pos; i++)
      {
         pos_tickets[i] = PositionGetTicket(i);
      }

      // 2. Fechamento compulsório desacoplado por ticket individual
      for(int i = 0; i < total_pos; i++)
      {
         ulong ticket = pos_tickets[i];
         if(ticket > 0)
         {
            if(!g_trade.PositionClose(ticket, InpDeviationPoints))
            {
               fail_count++;
               PrintFormat("[EddyTrader] FALHA ao liquidar posição #%I64u: Retcode %u (%s)",
                           ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
            }
            else
            {
               PrintFormat("[EddyTrader] Posição #%I64u liquidada com sucesso. Retcode %u",
                           ticket, g_trade.ResultRetcode());
            }
         }
      }
   }

   // 3. Cancelamento integral de ordens pendentes
   fail_count += CancelPendingOrders();

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
         PrintFormat("[EddyTrader] T05: Virada de dia contábil detectada (%s -> %s). Reiniciando J0 com Baseline B0 = 0.0",
                     TimeToString(old_day, TIME_DATE), TimeToString(t_day_current, TIME_DATE));
         g_window_id = 0;
         g_baseline  = 0.0;
         PersistState();
      }
      else
      {
         // T12: Novo dia durante estado de contenção/bloqueio -> Preserva bloqueio de 4h inalterado
         PrintFormat("[EddyTrader] T12: Virada de dia contábil durante bloqueio ativo (%s). Bloqueio preservado até %s.",
                     EnumToString(g_current_state), TimeToString(g_t_unlock, TIME_DATE|TIME_SECONDS));
         PersistState();
      }
   }
}

//+------------------------------------------------------------------+
//| Atualização Visual no Gráfico (HUD Limpo e Informativo)          |
//+------------------------------------------------------------------+
void UpdateHUD()
{
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

   string auth_str = (!g_is_owner) ? "NÃO (OWNERSHIP PERDIDA / FAIL-CLOSED)" :
                     ((g_current_state == EDDY_STATE_MONITORING && g_safe_to_operate) ? "SIM (NOMINAL)" : "NÃO (BLOQUEADO/FAIL-CLOSED)");
   string mode_str = (AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL) ? "REAL" : "DEMO";

   string hud = StringFormat(
      "====================================================\n"
      " EddyTrader - Núcleo de Proteção e Gerenciamento de Risco\n"
      "====================================================\n"
      " Conta: %I64u | Modo: %s | Servidor: %s\n"
      " Instância: #%I64u (Owner: %s)\n"
      " Horário Servidor: %s\n"
      "----------------------------------------------------\n"
      " Estado FSM: %s\n"
      " Janela Ativa: J%d | Baseline (Bn): %.2f\n"
      " Perda Máxima Permitida (L): -%.2f\n"
      "----------------------------------------------------\n"
      " R_day (Realizado Hoje):    %.2f %s\n"
      " F(t)  (Flutuante Líquido): %.2f %s\n"
      " D(t)  (Consolidado Hoje):  %.2f %s\n"
      " W_n(t)(Resultado Janela):  %.2f %s\n"
      "----------------------------------------------------\n"
      " Status de Proteção: %s\n"
      " ID do Evento: %I64u\n"
      " Informação de Bloqueio: %s\n"
      " Posições Abertas: %d | Ordens Pendentes: %d\n"
      " Negociação Autorizada: %s\n"
      "====================================================",
      g_account_login,
      mode_str,
      AccountInfoString(ACCOUNT_SERVER),
      g_instance_id,
      (g_is_owner ? "SIM" : "NÃO"),
      TimeToString(t_now, TIME_DATE|TIME_SECONDS),
      EnumToString(g_current_state),
      g_window_id, g_baseline,
      InpMaxLoss,
      R_day, AccountInfoString(ACCOUNT_CURRENCY),
      F, AccountInfoString(ACCOUNT_CURRENCY),
      D, AccountInfoString(ACCOUNT_CURRENCY),
      W, AccountInfoString(ACCOUNT_CURRENCY),
      (g_current_state == EDDY_STATE_MONITORING ? "NOMINAL / VIGILANTE" : "PROTEÇÃO ATIVADA"),
      g_protection_event_id,
      lock_info,
      PositionsTotal(), OrdersTotal(),
      auth_str
   );

   Comment(hud);
}

//+------------------------------------------------------------------+
//| Transições Controladas da Máquina de Estados (FSM)               |
//+------------------------------------------------------------------+
void TransitionTo(ENUM_EDDY_STATE target_state)
{
   datetime t_now = GetServerTimeSafe();
   PrintFormat("[EddyTrader] Transição FSM: %s -> %s (t=%s)",
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
         PrintFormat("[EddyTrader] T04: Bloqueio formalizado! EventID=%I64u, Trigger=%s, Unlock=%s",
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
         ExecuteGlobalLiquidation();

         // T08 / T09: Avalia se neutralização foi 100% concluída
         if(PositionsTotal() == 0 && OrdersTotal() == 0)
         {
            PrintFormat("[EddyTrader] T08: Neutralização integral concluída (resíduo zero). Avançando para BLOCKED.");
            TransitionTo(EDDY_STATE_BLOCKED);
         }
         else
         {
            PrintFormat("[EddyTrader] T09: Exposição residual ativa (%d posições, %d ordens). Retendo em LIQUIDATING.",
                        PositionsTotal(), OrdersTotal());
         }
         break;
      }

      case EDDY_STATE_BLOCKED:
      {
         PersistState();
         PrintFormat("[EddyTrader] BLOCKED ativo. Desbloqueio programado para %s",
                     TimeToString(g_t_unlock, TIME_DATE|TIME_SECONDS));
         break;
      }

      case EDDY_STATE_REOPENING:
      {
         PersistState();
         datetime t_reopen = t_now;
         g_window_id++;
         double D_reopen = CalculateConsolidatedResult(g_day_start, t_reopen);
         g_baseline = D_reopen;

         // Invariante de reabertura: W_(n+1)(t_reopen) == 0
         double W_new = CalculateWindowResult(D_reopen, g_baseline);
         PrintFormat("[EddyTrader] T14/T15: Reabertura formal! Nova janela J%d, Baseline Bn=%.2f, W_new=%.2f",
                     g_window_id, g_baseline, W_new);

         // Conclusão da reabertura: arquiva evento de proteção e retorna ao monitoramento
         g_t_trigger           = 0;
         g_t_unlock            = 0;
         g_protection_event_id = 0;
         g_safe_to_operate     = true;
         TransitionTo(EDDY_STATE_MONITORING);
         break;
      }

      case EDDY_STATE_MONITORING:
      {
         g_safe_to_operate = true;
         PersistState();
         PrintFormat("[EddyTrader] MONITORING ativo. Janela J%d | Baseline Bn=%.2f | Operação liberada.",
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
         if(W <= -InpMaxLoss)
         {
            PrintFormat("[EddyTrader] T04: Limite violado! W=%.2f <= -L=-%.2f (D=%.2f, Bn=%.2f)",
                        W, InpMaxLoss, D, g_baseline);
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
         // Retentativa contínua de liquidação
         if(PositionsTotal() > 0 || OrdersTotal() > 0)
         {
            ExecuteGlobalLiquidation();
         }

         // T08: Se resíduo zerou, avança para BLOCKED
         if(PositionsTotal() == 0 && OrdersTotal() == 0)
         {
            PrintFormat("[EddyTrader] T08: Resíduo zerado. Avançando para BLOCKED.");
            TransitionTo(EDDY_STATE_BLOCKED);
         }
         break;
      }

      case EDDY_STATE_BLOCKED:
      {
         // Neutralização de intervenções residuais durante o bloqueio
         if(PositionsTotal() > 0 || OrdersTotal() > 0)
         {
            PrintFormat("[EddyTrader] ALERTA: Exposição detectada durante BLOCKED! Executando neutralização.");
            ExecuteGlobalLiquidation();
         }

         // T13 / T14: Avalia alcance do tempo mínimo de 4 horas
         if(t_now >= g_t_unlock)
         {
            if(CheckSafetyConditions())
            {
               PrintFormat("[EddyTrader] T14: Tempo de bloqueio cumprido (%s >= %s) e condições seguras. Iniciando REOPENING.",
                           TimeToString(t_now, TIME_DATE|TIME_SECONDS),
                           TimeToString(g_t_unlock, TIME_DATE|TIME_SECONDS));
               TransitionTo(EDDY_STATE_REOPENING);
            }
            else
            {
               PrintFormat("[EddyTrader] T13: Tempo cumprido mas safe_to_reopen == false (pos=%d, ord=%d, conn=%d). Retendo em BLOCKED.",
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
   Print("[EddyTrader] ==================================================");
   Print("[EddyTrader] Inicializando EddyTrader v1.00 (W06 MVP Operacional)");
   Print("[EddyTrader] ==================================================");

   // 1. Validação estrita de parâmetros de entrada
   if(InpMaxLoss <= 0.0)
   {
      PrintFormat("[EddyTrader] ERRO FATAL: InpMaxLoss deve ser > 0 (configurado: %.2f)", InpMaxLoss);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpBlockDurationHours < 1)
   {
      PrintFormat("[EddyTrader] ERRO FATAL: InpBlockDurationHours deve ser >= 1 (configurado: %d)", InpBlockDurationHours);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpTimerIntervalMs < 50)
   {
      PrintFormat("[EddyTrader] ERRO FATAL: InpTimerIntervalMs muito baixo (configurado: %d ms)", InpTimerIntervalMs);
      return INIT_PARAMETERS_INCORRECT;
   }

   // 2. Identificação da conta e configuração comercial
   g_account_login = (ulong)AccountInfoInteger(ACCOUNT_LOGIN);
   g_trade.SetDeviationInPoints(InpDeviationPoints);

   ENUM_ACCOUNT_TRADE_MODE trade_mode = (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(trade_mode == ACCOUNT_TRADE_MODE_REAL)
   {
      Print("[EddyTrader] ATENÇÃO: Conta REAL detectada! O EddyTrader atuará em modo de proteção absoluta de capital.");
   }
   else
   {
      Print("[EddyTrader] Modo de conta DEMO / TESTE detectado.");
   }

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      Print("[EddyTrader] AVISO: 'Algo Trading' está DESATIVADO nas opções do terminal MT5.");
   }
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
   {
      Print("[EddyTrader] AVISO: Negociação desativada para a conta atual.");
   }

   // 3. Guarda de Instância Única por Conta (OWNER + HEARTBEAT)
   if(!AcquireInstanceGuard())
   {
      return INIT_FAILED;
   }

   // 4. Marcação temporal do dia operacional
   datetime t_now = GetServerTimeSafe();
   g_day_start = GetDayStart(t_now);

   // 5. Reconstituição Determinística de Estado (ADR 0004 / ADR 0005)
   EddyRecoveryState rec;
   if(LoadState(rec))
   {
      PrintFormat("[EddyTrader] Estado persistido encontrado: State=%s, J=%d, Bn=%.2f, EventID=%I64u, Unlock=%s",
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
            PrintFormat("[EddyTrader] T03: Exposição residual aberta detectada pós-restart durante proteção. Forçando LIQUIDATING.");
            g_current_state = EDDY_STATE_LIQUIDATING;
         }
         else
         {
            if(t_now < g_t_unlock)
            {
               // T02A: Bloqueio ativo mantido
               PrintFormat("[EddyTrader] T02A: Bloqueio temporal mantido pós-restart (%d s restantes).",
                           (int)(g_t_unlock - t_now));
               g_current_state = EDDY_STATE_BLOCKED;
            }
            else
            {
               // t_now >= g_t_unlock
               if(CheckSafetyConditions())
               {
                  // T02C: Reabertura imediata pós-restart
                  PrintFormat("[EddyTrader] T02C: Bloqueio vencido e condições seguras. Conduzindo a REOPENING.");
                  g_current_state = EDDY_STATE_BLOCKED; // transitará no ProcessFSM
               }
               else
               {
                  // T02B: Bloqueio retido por falta de segurança
                  PrintFormat("[EddyTrader] T02B: Bloqueio vencido mas ambiente inseguro (pos=%d, ord=%d). Retendo em BLOCKED.",
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
            PrintFormat("[EddyTrader] T05: Novo dia operacional detectado pós-restart (%s < %s). Iniciando J0 com B0=0.",
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
                  PrintFormat("[EddyTrader] ERRO CRÍTICO (FAIL-CLOSED): Janela J%d ativa mas Baseline Bn ausente nas Global Variables! Operações retidas em INIT.",
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
            PrintFormat("[EddyTrader] MONITORING reconstituído com sucesso: Janela J%d | Baseline Bn=%.2f",
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
      PrintFormat("[EddyTrader] Inicialização limpa na conta %I64u. Iniciando J0 com B0=0.0", g_account_login);
      g_current_state   = EDDY_STATE_MONITORING;
      g_window_id       = 0;
      g_baseline        = 0.0;
      g_safe_to_operate = true;
   }

   PersistState();

   // 6. Ativação do MillisecondTimer de alta frequência
   if(!EventSetMillisecondTimer(InpTimerIntervalMs))
   {
      PrintFormat("[EddyTrader] AVISO: EventSetMillisecondTimer(%d ms) falhou. Recorrendo a EventSetTimer(1 s).", InpTimerIntervalMs);
      EventSetTimer(1);
   }

   // 7. Avaliação inicial da FSM
   ProcessFSM();

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ReleaseInstanceGuard();
   Comment(""); // Limpa o HUD gráfico
   PrintFormat("[EddyTrader] EA descarregado da conta %I64u. Razão: %d", g_account_login, reason);
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
            PrintFormat("[EddyTrader] INTERVENÇÃO MANUAL DETECTADA em %s: Negócio #%I64u executado! Neutralizando imediatamente.",
                        EnumToString(g_current_state), trans.deal);
            ExecuteGlobalLiquidation();
         }
      }
      else if(trans.type == TRADE_TRANSACTION_ORDER_ADD)
      {
         PrintFormat("[EddyTrader] INTERVENÇÃO MANUAL DETECTADA em %s: Ordem pendente #%I64u adicionada! Cancelando imediatamente.",
                     EnumToString(g_current_state), trans.order);
         CancelPendingOrders();
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
         ExecuteGlobalLiquidation();
      }
   }

   ProcessFSM();
}
//+------------------------------------------------------------------+
