//+------------------------------------------------------------------+
//|                              probe_pending_order_gate_w11.mq5   |
//|                                  Copyright 2026, EddyTrader Team |
//+------------------------------------------------------------------+
// RESEARCH ONLY -- W11 Gate: Ordens Pendentes com SL/TP Anexados.
// Versao: 1.02 -- Revisao pos-auditoria do Arquiteto (2026-09-16).
//
// SEPARACAO DE RESPONSABILIDADES:
//   probe_sl_lock_w11.mq5            OBSERVACIONAL -- nunca chama OrderSend.
//   probe_pending_order_gate_w11.mq5 EXPERIMENTAL  -- envia ordens pendentes
//     controladas; nunca implementa SL Lock, restauracao, OCO ou trailing.
//
// ARQUITETURA v1.02 -- SEQUENCIAL (um caso por vez):
//   Correcoes aplicadas conforme auditoria:
//   [1]  Execucao sequencial: BL, SL, BS, SS um a um; so avanca apos
//        ativacao+evidencia+limpeza ou timeout do caso atual.
//   [2]  Expiracao segura: exige ORDER_TIME_SPECIFIED; BLOCKED se o
//        simbolo/servidor nao oferecer expiracao automatica.
//   [3]  Limpeza abrange ordens E posicoes experimentais por ticket.
//        Fechar posicao de higiene != SL Lock; nunca fecha posicao externa.
//   [4]  Pre-check: exige inventario vazio no simbolo antes de cada caso.
//        Em Netting nao confia apenas no magic da posicao agregada.
//   [5]  Volume normalizado: SYMBOL_VOLUME_MIN/MAX/STEP; nao presume 0.01.
//   [6]  Filling: RETURN para pendentes; fechamento usa modo permitido
//        por SYMBOL_FILLING_MODE, sem FOK hardcoded.
//   [7]  Distancias validadas contra stops_level, freeze_level, tick_size.
//   [8]  Correlacao robusta: order->deal->position via DEAL_ORDER +
//        DEAL_POSITION_ID; nao assume position_ticket == order_ticket.
//   [9]  PASS somente com: ordem aceita, ativacao observada, inventario
//        obtido, SL/TP dentro da tolerancia, sl_class correto.
//        Compilacao nunca gera PASS.
//   [10] docs/23: diferenciacao de probes e sequencia de eventos corrigidas.
//   [11] Expiracao/limpeza documentadas neste cabecalho e no CHANGELOG.
//   [12] Build 4/4 0/0; diff limpo; src/EddyTrader.mq5 intacto.
//
// RESTRICOES ABSOLUTAS:
//   - Exige ACCOUNT_TRADE_MODE_DEMO.
//   - Exige InpConfirmDemoLab = true (input explicito do operador).
//   - Exige InpRunProbe = true para enviar qualquer ordem.
//   - Nunca altera src/EddyTrader.mq5 nem qualquer codigo de producao.
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, EddyTrader Team"
#property version   "1.02"
#property description "[RESEARCH ONLY] Pending Order Gate v1.02 - W11/GAP-007"
#property strict

//--- Safety inputs
input group "=== LAB SAFETY ==="
input bool   InpConfirmDemoLab = false; // TRUE = confirmo conta Demo de pesquisa
input bool   InpRunProbe       = false; // TRUE = enviar ordens experimentais

//--- Probe parameters
input group "=== PROBE PARAMETERS ==="
input string InpSymbol        = "GBPUSD"; // Simbolo experimental
input double InpVolumeLot     = 0.01;     // Volume base (normalizado com MIN/MAX/STEP)
input int    InpOffsetPoints  = 100;      // Offset do mercado para preco pendente (pontos)
input int    InpSlPoints      = 150;      // SL offset a partir do preco pendente (pontos)
input int    InpTpPoints      = 150;      // TP offset a partir do preco pendente (pontos)
input int    InpExpirySeconds = 300;      // Segundos de expiracao (ORDER_TIME_SPECIFIED)
input int    InpTimerMs       = 500;      // Intervalo do timer em ms
input int    InpMaxCaseCycles = 600;      // Ciclos maximos por caso (~5 min a 500ms)
input bool   InpVerboseScans  = false;    // Logar scans sem mudanca

//--- Magic number unico para este probe
//    Diferente do probe observacional (sem magic proprio) e de EAs externos.
#define PROBE_MAGIC       20261102
#define EVIDENCE_DELAY    4           // ciclos de timer apos DEAL_ADD antes de evidencia

//--- Estados do probe completo
enum EProbeState
{
   PROBE_IDLE,    // aguardando InpRunProbe
   PROBE_RUNNING, // processando casos sequencialmente
   PROBE_DONE     // relatorio emitido; idle
};

//--- Estados internos por caso
enum ECaseState
{
   CS_PRE_CHECK,  // validar condicoes e inventario do simbolo
   CS_PLACING,    // colocar a ordem pendente
   CS_MONITORING, // aguardar ativacao, expiracao ou timeout
   CS_EVIDENCE,   // coletar inventario e avaliar PASS/FAIL/BLOCKED
   CS_CLEANUP,    // cancelar ordens e fechar posicao experimental (higiene)
   CS_NEXT        // avanco para o proximo caso
};

//--- Definicao de um caso da matriz
struct SCaseDef
{
   string          label;
   ENUM_ORDER_TYPE order_type;
};

//--- Resultado de um caso
struct SCaseResult
{
   string  label;
   string  outcome;        // "PASS", "FAIL", "BLOCKED"
   string  outcome_detail;
   ulong   order_ticket;
   double  price_req;
   double  sl_req;
   double  tp_req;
   double  price_acc;      // aceito pelo servidor (OrderSelect)
   double  sl_acc;
   double  tp_acc;
   ulong   deal_ticket;
   ulong   position_id;    // DEAL_POSITION_ID do deal de ativacao
   double  pos_sl_first;   // SL da posicao no primeiro inventario real
   double  pos_tp_first;
   string  sl_class;       // BASELINE_SET ou WAIT_FIRST_SL
   int     events_seen;
};

//--- Metadados do simbolo (preenchidos no OnInit)
double                      g_tick_size    = 0.0;
long                        g_stops_level  = 0;
long                        g_freeze_level = 0;
int                         g_digits       = 5;
double                      g_vol_min      = 0.01;
double                      g_vol_max      = 100.0;
double                      g_vol_step     = 0.01;
double                      g_vol_used     = 0.01; // volume normalizado efetivo
ENUM_ORDER_TYPE_FILLING     g_pending_filling = ORDER_FILLING_RETURN;
ENUM_ORDER_TYPE_FILLING     g_market_filling  = ORDER_FILLING_RETURN;
ENUM_SYMBOL_TRADE_EXECUTION g_exec_mode    = SYMBOL_TRADE_EXECUTION_REQUEST;
string                      g_margin_mode  = "";
bool                        g_has_specified = false; // ORDER_TIME_SPECIFIED suportado
bool                        g_has_gtc       = false; // ORDER_TIME_GTC suportado

//--- Controle do probe
EProbeState g_probe_state = PROBE_IDLE;
ECaseState  g_case_state  = CS_PRE_CHECK;
int         g_case_index  = 0;
SCaseDef    g_case_defs[4];
SCaseResult g_results[4];

//--- Estado do caso corrente (resetado a cada caso)
int    g_case_cycles     = 0;
int    g_deal_delay      = 0; // ciclos aguardando apos DEAL_ADD
bool   g_order_placed    = false;
bool   g_server_acked    = false; // ORDER_ADD recebido
bool   g_order_deleted   = false; // ORDER_DELETE recebido
int    g_order_deleted_cycle = -1;
bool   g_deal_found      = false; // DEAL_ADD correlacionado ao nosso ticket
bool   g_pos_event_rcvd  = false; // TRADE_TRANSACTION_POSITION recebido
ulong  g_cur_ticket      = 0;
ulong  g_cur_deal        = 0;
ulong  g_cur_pos_id      = 0;    // DEAL_POSITION_ID
double g_cur_price_req   = 0.0;
double g_cur_sl_req      = 0.0;
double g_cur_tp_req      = 0.0;
double g_cur_price_acc   = 0.0;
double g_cur_sl_acc      = 0.0;
double g_cur_tp_acc      = 0.0;
int    g_cur_events      = 0;

//--- Log
int    g_file      = INVALID_HANDLE;
ulong  g_txn_count = 0;

//+------------------------------------------------------------------+
//| Logging                                                          |
//+------------------------------------------------------------------+
void PLog(const string level, const string msg)
{
   string line = StringFormat("[PROBE-PENDING-W11][%s] %s", level, msg);
   Print(line);
   if(g_file != INVALID_HANDLE)
   {
      FileWriteString(g_file,
         TimeToString(TimeTradeServer(), TIME_DATE|TIME_SECONDS) +
         " " + line + "\r\n");
      FileFlush(g_file);
   }
}

//+------------------------------------------------------------------+
//| Classificar primeiro SL da posicao (W11-DEC-02)                 |
//+------------------------------------------------------------------+
string ClassifyFirstSL(const double sl) { return (sl > 0.0 ? "BASELINE_SET" : "WAIT_FIRST_SL"); }

//+------------------------------------------------------------------+
//| Normalizar preco para digits do simbolo                         |
//+------------------------------------------------------------------+
double NormP(const double p) { return NormalizeDouble(p, g_digits); }

//+------------------------------------------------------------------+
//| Resetar estado do caso corrente                                 |
//+------------------------------------------------------------------+
void ResetCaseState()
{
   g_case_cycles   = 0;
   g_deal_delay    = 0;
   g_order_placed  = false;
   g_server_acked  = false;
   g_order_deleted = false;
   g_order_deleted_cycle = -1;
   g_deal_found    = false;
   g_pos_event_rcvd= false;
   g_cur_ticket    = 0;
   g_cur_deal      = 0;
   g_cur_pos_id    = 0;
   g_cur_price_req = 0.0;
   g_cur_sl_req    = 0.0;
   g_cur_tp_req    = 0.0;
   g_cur_price_acc = 0.0;
   g_cur_sl_acc    = 0.0;
   g_cur_tp_acc    = 0.0;
   g_cur_events    = 0;
}

//+------------------------------------------------------------------+
//| Pre-check: inventario vazio e condicoes seguras por caso        |
//| Restr. [4]: Em Netting exige inventario vazio no simbolo.       |
//+------------------------------------------------------------------+
bool CasePreCheck(const string sym, string &reason)
{
   // Verificar posicoes abertas no simbolo (qualquer magic)
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) == sym)
      {
         reason = StringFormat("Posicao externa em %s detectada (ticket=#%I64u magic=%I64d). "
                               "Em Netting nao e possivel isolar o experimento.",
                               sym,
                               PositionGetInteger(POSITION_TICKET),
                               PositionGetInteger(POSITION_MAGIC));
         return false;
      }
   }
   // Verificar ordens pendentes externas no simbolo
   for(int i = 0; i < OrdersTotal(); i++)
   {
      ulong t = OrderGetTicket(i);
      if(t == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) == sym &&
         OrderGetInteger(ORDER_MAGIC) != PROBE_MAGIC)
      {
         reason = StringFormat("Ordem pendente externa em %s detectada (ticket=#%I64u). "
                               "Inventario deve estar vazio.", sym, t);
         return false;
      }
   }
   // Verificar quotes validos
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
   {
      reason = "Ask/bid invalidos; simbolo sem cotacao.";
      return false;
   }
   // A entrada pendente precisa ficar fora das faixas de stops e freeze.
   long min_entry_level = (long)MathMax((double)g_stops_level,
                                        (double)g_freeze_level);
   if((long)InpOffsetPoints <= min_entry_level)
   {
      reason = StringFormat("InpOffsetPoints=%d <= max(stops=%d, freeze=%d). "
                            "Aumente o offset para posicionar com seguranca.",
                            InpOffsetPoints, (int)g_stops_level,
                            (int)g_freeze_level);
      return false;
   }
   reason = "";
   return true;
}

//+------------------------------------------------------------------+
//| Calcular e validar preco/SL/TP para o tipo de ordem dado        |
//| Restr. [7]: Validar distancias contra stops_level e freeze_level |
//+------------------------------------------------------------------+
bool ComputePrices(const ENUM_ORDER_TYPE type,
                   double &entry, double &sl, double &tp,
                   string &reason)
{
   double ask = SymbolInfoDouble(InpSymbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
   double offset  = InpOffsetPoints * g_tick_size;
   double sl_dist = InpSlPoints     * g_tick_size;
   double tp_dist = InpTpPoints     * g_tick_size;
   double min_dist = g_stops_level  * g_tick_size;

   switch(type)
   {
      case ORDER_TYPE_BUY_LIMIT:
         entry = NormP(ask - offset);
         sl    = NormP(entry - sl_dist);
         tp    = NormP(entry + tp_dist);
         break;
      case ORDER_TYPE_SELL_LIMIT:
         entry = NormP(bid + offset);
         sl    = NormP(entry + sl_dist);
         tp    = NormP(entry - tp_dist);
         break;
      case ORDER_TYPE_BUY_STOP:
         entry = NormP(ask + offset);
         sl    = NormP(entry - sl_dist);
         tp    = NormP(entry + tp_dist);
         break;
      case ORDER_TYPE_SELL_STOP:
         entry = NormP(bid - offset);
         sl    = NormP(entry + sl_dist);
         tp    = NormP(entry - tp_dist);
         break;
      default:
         reason = "Tipo de ordem desconhecido.";
         return false;
   }

   // Validar distancia SL vs stops_level
   if(min_dist > 0.0 && MathAbs(entry - sl) < min_dist - g_tick_size * 0.1)
   {
      reason = StringFormat("SL muito proximo ao preco de entrada: |%.5f-%.5f|=%.5f < min=%.5f",
                            entry, sl, MathAbs(entry - sl), min_dist);
      return false;
   }
   // Validar distancia TP vs stops_level
   if(min_dist > 0.0 && MathAbs(tp - entry) < min_dist - g_tick_size * 0.1)
   {
      reason = StringFormat("TP muito proximo ao preco de entrada: |%.5f-%.5f|=%.5f < min=%.5f",
                            tp, entry, MathAbs(tp - entry), min_dist);
      return false;
   }
   // Validar que sl e tp sao positivos
   if(sl <= 0.0 || tp <= 0.0)
   {
      reason = StringFormat("SL=%.5f ou TP=%.5f calculado como nao-positivo.", sl, tp);
      return false;
   }
   reason = "";
   return true;
}

//+------------------------------------------------------------------+
//| Determinar order_time e expiry_time (Restr. [2])               |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_TIME GetOrderTime(datetime &expiry)
{
   expiry = 0;
   if(g_has_specified)
   {
      expiry = TimeCurrent() + InpExpirySeconds;
      PLog("EXPIRY", StringFormat("ORDER_TIME_SPECIFIED: expiry=%s (+%d s)",
           TimeToString(expiry, TIME_DATE|TIME_SECONDS), InpExpirySeconds));
      return ORDER_TIME_SPECIFIED;
   }
   PLog("EXPIRY",
        "BLOCKED: ORDER_TIME_SPECIFIED nao suportado. GTC nao e aceito "
        "neste probe porque ficaria sem expiracao automatica no servidor.");
   return (ENUM_ORDER_TYPE_TIME)-1; // sinal de BLOCKED
}

//+------------------------------------------------------------------+
//| Colocar uma ordem pendente e registrar resultado (Restr. [5-8]) |
//+------------------------------------------------------------------+
bool PlaceOrder(const string label,
                const ENUM_ORDER_TYPE type,
                const double entry,
                const double sl,
                const double tp,
                string &fail_reason)
{
   datetime expiry;
   ENUM_ORDER_TYPE_TIME order_time = GetOrderTime(expiry);
   if((int)order_time < 0)
   {
      fail_reason = "Expiracao nao suportada; caso BLOCKED.";
      return false;
   }

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action       = TRADE_ACTION_PENDING;
   req.symbol       = InpSymbol;
   req.volume       = g_vol_used;
   req.price        = entry;
   req.sl           = sl;
   req.tp           = tp;
   req.type         = type;
   req.type_filling = g_pending_filling;
   req.type_time    = order_time;
   req.expiration   = expiry;
   req.magic        = PROBE_MAGIC;
   req.comment      = StringFormat("W11-GATE-%s", label);

   PLog("ORDER_REQ",
        StringFormat("label=%s type=%s price=%.5f sl=%.5f tp=%.5f "
                     "vol=%.2f filling=%s order_time=%s expiry=%s magic=%d",
                     label, EnumToString(type), req.price, req.sl, req.tp,
                     req.volume, EnumToString(req.type_filling),
                     EnumToString(req.type_time),
                     (expiry > 0 ? TimeToString(expiry) : "GTC"),
                     req.magic));

   bool ok = OrderSend(req, res);

   PLog("ORDER_RESULT",
        StringFormat("label=%s ok=%s retcode=%u order=#%I64u comment=%s",
                     label, (ok ? "true" : "false"),
                     res.retcode, res.order, res.comment));

   if(!ok || (res.retcode != TRADE_RETCODE_PLACED &&
              res.retcode != TRADE_RETCODE_DONE))
   {
      fail_reason = StringFormat("OrderSend falhou: retcode=%u comment=%s",
                                 res.retcode, res.comment);
      return false;
   }

   g_cur_ticket    = res.order;
   g_cur_price_req = entry;
   g_cur_sl_req    = sl;
   g_cur_tp_req    = tp;
   g_order_placed  = true;

   // Reconciliar valores aceitos via inventario real
   if(OrderSelect(g_cur_ticket))
   {
      g_cur_price_acc = OrderGetDouble(ORDER_PRICE_OPEN);
      g_cur_sl_acc    = OrderGetDouble(ORDER_SL);
      g_cur_tp_acc    = OrderGetDouble(ORDER_TP);
      PLog("ORDER_ACCEPTED",
           StringFormat("label=%s ticket=#%I64u "
                        "price_req=%.5f price_acc=%.5f "
                        "sl_req=%.5f sl_acc=%.5f "
                        "tp_req=%.5f tp_acc=%.5f",
                        label, g_cur_ticket,
                        g_cur_price_req, g_cur_price_acc,
                        g_cur_sl_req,    g_cur_sl_acc,
                        g_cur_tp_req,    g_cur_tp_acc));
   }
   else
   {
      PLog("WARN",
           StringFormat("label=%s ticket=#%I64u colocada mas OrderSelect falhou; "
                        "usando valores requisitados como fallback.",
                        label, g_cur_ticket));
      g_cur_price_acc = entry;
      g_cur_sl_acc    = sl;
      g_cur_tp_acc    = tp;
   }

   fail_reason = "";
   return true;
}

//+------------------------------------------------------------------+
//| Cancelar nossa ordem pendente corrente (se ainda existir)       |
//+------------------------------------------------------------------+
void CancelCurrentOrder()
{
   if(g_cur_ticket == 0) return;
   if(!OrderSelect(g_cur_ticket)) return; // ja removida

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action = TRADE_ACTION_REMOVE;
   req.order  = g_cur_ticket;

   bool ok = OrderSend(req, res);
   PLog("CANCEL_ORDER",
        StringFormat("ticket=#%I64u retcode=%u ok=%s",
                     g_cur_ticket, res.retcode, (ok ? "true" : "false")));
}

//+------------------------------------------------------------------+
//| Selecionar posicao pelo identificador persistente do deal       |
//+------------------------------------------------------------------+
bool SelectPositionByIdentifier(const ulong position_id, ulong &position_ticket)
{
   position_ticket = 0;
   if(position_id == 0) return false;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != InpSymbol) continue;
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER) != position_id) continue;
      position_ticket = ticket;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Fechar posicao experimental pelo identificador do deal          |
//| Restr. [3]: nunca fecha posicao externa; resolve ticket real.   |
//+------------------------------------------------------------------+
void CloseProbePosition(const ulong pos_id)
{
   if(pos_id == 0) return;
   ulong pos_ticket = 0;
   if(!SelectPositionByIdentifier(pos_id, pos_ticket))
   {
      PLog("CLEANUP", StringFormat("Posicao id=#%I64u nao existe (ja fechada).",
                                   pos_id));
      return;
   }

   // Verificacao extra: a posicao deve corresponder ao nosso ticket rastreado
   // para nunca fechar posicao externa
   if(pos_id != g_cur_pos_id)
   {
      PLog("CLEANUP_SKIP",
           StringFormat("Posicao #%I64u nao corresponde ao pos_id rastreado "
                        "#%I64u. Ignorado para nao fechar posicao externa.",
                        pos_id, g_cur_pos_id));
      return;
   }

   string sym   = PositionGetString(POSITION_SYMBOL);
   double vol   = PositionGetDouble(POSITION_VOLUME);
   ENUM_POSITION_TYPE pt =
      (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = sym;
   req.volume       = vol;
   req.type         = (pt == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
   req.position     = pos_ticket;
   req.price        = (pt == POSITION_TYPE_BUY ?
                       SymbolInfoDouble(sym, SYMBOL_BID) :
                       SymbolInfoDouble(sym, SYMBOL_ASK));
   req.type_filling = g_market_filling;
   req.deviation    = 100;         // slippage max: 10 pips em 5 digits
   req.magic        = PROBE_MAGIC;
   req.comment      = "W11-GATE-CLEANUP";

   bool ok = OrderSend(req, res);
   PLog("CLOSE_PROBE_POSITION",
        StringFormat("[HIGIENE DO EXPERIMENTO -- NAO E FECHAMENTO DE SL LOCK] "
                     "pos_id=#%I64u ticket=#%I64u sym=%s vol=%.2f retcode=%u ok=%s",
                     pos_id, pos_ticket, sym, vol, res.retcode,
                     (ok ? "true" : "false")));
}

//+------------------------------------------------------------------+
//| Coletar inventario e avaliar PASS/FAIL/BLOCKED (Restr. [9])     |
//+------------------------------------------------------------------+
void EvaluateCase(const int idx)
{
   double tol = g_tick_size * 0.6; // meio tick com margem

   // Caso nunca ativado (deal nao encontrado)
   if(!g_deal_found)
   {
      g_results[idx].outcome = "BLOCKED";
      g_results[idx].outcome_detail =
         "Ativacao nao observada: nenhum DEAL_ADD correlacionado ao ticket.";
      PLog("EVIDENCE",
           StringFormat("label=%s BLOCKED: %s",
                        g_results[idx].label, g_results[idx].outcome_detail));
      return;
   }

   // Tentar obter inventario real da posicao
   ulong pos_ticket = 0;
   if(g_cur_pos_id == 0 ||
      !SelectPositionByIdentifier(g_cur_pos_id, pos_ticket))
   {
      g_results[idx].outcome = "FAIL";
      g_results[idx].outcome_detail =
         StringFormat("Ativacao observada (deal=#%I64u) mas inventario da "
                      "posicao nao obtido (pos_id=#%I64u).",
                      g_cur_deal, g_cur_pos_id);
      g_results[idx].deal_ticket  = g_cur_deal;
      g_results[idx].position_id  = g_cur_pos_id;
      PLog("EVIDENCE",
           StringFormat("label=%s FAIL: %s",
                        g_results[idx].label, g_results[idx].outcome_detail));
      return;
   }

   double pos_sl = PositionGetDouble(POSITION_SL);
   double pos_tp = PositionGetDouble(POSITION_TP);
   string sl_class = ClassifyFirstSL(pos_sl);
   string expected_class = (g_cur_sl_acc > 0.0 ? "BASELINE_SET" : "WAIT_FIRST_SL");

   g_results[idx].deal_ticket  = g_cur_deal;
   g_results[idx].position_id  = g_cur_pos_id;
   g_results[idx].pos_sl_first = pos_sl;
   g_results[idx].pos_tp_first = pos_tp;
   g_results[idx].sl_class     = sl_class;

   PLog("EVIDENCE",
        StringFormat("label=%s deal=#%I64u pos=#%I64u "
                     "sl_acc=%.5f pos_sl=%.5f tp_acc=%.5f pos_tp=%.5f "
                     "sl_class=%s expected=%s",
                     g_results[idx].label,
                     g_cur_deal, g_cur_pos_id,
                     g_cur_sl_acc, pos_sl,
                     g_cur_tp_acc, pos_tp,
                     sl_class, expected_class));

   bool sl_ok  = (MathAbs(pos_sl - g_cur_sl_acc) < tol) ||
                 (pos_sl == 0.0 && g_cur_sl_acc == 0.0);
   bool tp_ok  = (MathAbs(pos_tp - g_cur_tp_acc) < tol) ||
                 (pos_tp == 0.0 && g_cur_tp_acc == 0.0);
   bool cls_ok = (sl_class == expected_class);

   if(sl_ok && tp_ok && cls_ok)
   {
      g_results[idx].outcome = "PASS";
      g_results[idx].outcome_detail =
         StringFormat("sl_ok=%s tp_ok=%s sl_class=%s",
                      (sl_ok ? "true" : "false"),
                      (tp_ok ? "true" : "false"),
                      sl_class);
   }
   else
   {
      g_results[idx].outcome = "FAIL";
      g_results[idx].outcome_detail =
         StringFormat("sl_ok=%s (%.5f vs %.5f tol=%.5f) "
                      "tp_ok=%s (%.5f vs %.5f) "
                      "sl_class=%s expected=%s",
                      (sl_ok ? "true" : "false"),
                      pos_sl, g_cur_sl_acc, tol,
                      (tp_ok ? "true" : "false"),
                      pos_tp, g_cur_tp_acc,
                      sl_class, expected_class);
   }

   PLog("EVIDENCE",
        StringFormat("label=%s => %s: %s",
                     g_results[idx].label,
                     g_results[idx].outcome,
                     g_results[idx].outcome_detail));
}

//+------------------------------------------------------------------+
//| Imprimir relatorio final da matriz                              |
//+------------------------------------------------------------------+
void PrintFinalReport()
{
   PLog("REPORT_START", "=== MATRIX REPORT - W11 PENDING ORDER GATE v1.02 ===");
   PLog("REPORT",
        StringFormat("sym=%s digits=%d tick=%.5f stops=%d freeze=%d "
                     "exec=%s margin=%s pending_filling=%s market_filling=%s "
                     "expiry_specified=%s expiry_gtc=%s "
                     "vol_used=%.2f (min=%.2f max=%.2f step=%.2f)",
                     InpSymbol, g_digits, g_tick_size,
                     (int)g_stops_level, (int)g_freeze_level,
                     EnumToString(g_exec_mode), g_margin_mode,
                     EnumToString(g_pending_filling),
                     EnumToString(g_market_filling),
                     (g_has_specified ? "SIM" : "NAO"),
                     (g_has_gtc       ? "SIM" : "NAO"),
                     g_vol_used, g_vol_min, g_vol_max, g_vol_step));

   for(int i = 0; i < 4; i++)
   {
      SCaseResult r = g_results[i];
      PLog("MATRIX_ROW",
           StringFormat("label=%s outcome=%s ticket=#%I64u "
                        "price_req=%.5f price_acc=%.5f "
                        "sl_req=%.5f sl_acc=%.5f "
                        "tp_req=%.5f tp_acc=%.5f "
                        "deal=#%I64u pos_id=#%I64u "
                        "pos_sl=%.5f pos_tp=%.5f "
                        "sl_class=%s events=%d | %s",
                        r.label, r.outcome, r.order_ticket,
                        r.price_req, r.price_acc,
                        r.sl_req,    r.sl_acc,
                        r.tp_req,    r.tp_acc,
                        r.deal_ticket, r.position_id,
                        r.pos_sl_first, r.pos_tp_first,
                        r.sl_class, r.events_seen,
                        r.outcome_detail));
   }

   PLog("REPORT",
        StringFormat("Total TXN capturados: %I64u | Casos: %d processados",
                     g_txn_count, g_case_index));
   PLog("REPORT_END", "=== END MATRIX REPORT ===");
}

//+------------------------------------------------------------------+
//| Inicializar metadados do simbolo (Restr. [5],[6],[7])           |
//+------------------------------------------------------------------+
bool InitSymbolMeta()
{
   g_tick_size    = SymbolInfoDouble(InpSymbol, SYMBOL_TRADE_TICK_SIZE);
   g_stops_level  = SymbolInfoInteger(InpSymbol, SYMBOL_TRADE_STOPS_LEVEL);
   g_freeze_level = SymbolInfoInteger(InpSymbol, SYMBOL_TRADE_FREEZE_LEVEL);
   g_digits       = (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS);
   g_vol_min      = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MIN);
   g_vol_max      = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MAX);
   g_vol_step     = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_STEP);
   g_exec_mode    = (ENUM_SYMBOL_TRADE_EXECUTION)
                    SymbolInfoInteger(InpSymbol, SYMBOL_TRADE_EXEMODE);
   g_margin_mode  = EnumToString(
      (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE));

   if(g_tick_size <= 0.0 || g_vol_step <= 0.0 || g_vol_min <= 0.0)
   {
      Print("[PROBE-PENDING-W11][ERROR] Metadados invalidos para ", InpSymbol,
            ": tick=", g_tick_size, " vol_step=", g_vol_step);
      return false;
   }

   // Normalizar volume (Restr. [5])
   double v = MathMax(InpVolumeLot, g_vol_min);
   v = MathMin(v, g_vol_max);
   v = MathRound(v / g_vol_step) * g_vol_step;
   g_vol_used = NormalizeDouble(v, 2);

   // Pendentes usam RETURN; o fechamento a mercado respeita os flags do simbolo.
   long fill_flags = SymbolInfoInteger(InpSymbol, SYMBOL_FILLING_MODE);
   g_pending_filling = ORDER_FILLING_RETURN;
   if((fill_flags & 2) != 0)       g_market_filling = ORDER_FILLING_IOC;
   else if((fill_flags & 1) != 0)  g_market_filling = ORDER_FILLING_FOK;
   else                             g_market_filling = ORDER_FILLING_RETURN;

   // Verificar suporte de expiracao (Restr. [2])
   // SYMBOL_EXPIRATION_MODE: bitmask com flags de expiracao suportadas.
   //   Bit 0 (valor 1): SYMBOL_EXPIRATION_GTC suportado
   //   Bit 2 (valor 4): SYMBOL_EXPIRATION_SPECIFIED suportado
   long exp_mode = SymbolInfoInteger(InpSymbol, SYMBOL_EXPIRATION_MODE);
   g_has_specified = ((exp_mode & 4) != 0);  // ORDER_TIME_SPECIFIED disponivel
   g_has_gtc       = ((exp_mode & 1) != 0);  // ORDER_TIME_GTC disponivel


   return true;
}

//+------------------------------------------------------------------+
//| OnInit                                                          |
//+------------------------------------------------------------------+
int OnInit()
{
   // Guard 1: Demo apenas
   ENUM_ACCOUNT_TRADE_MODE mode =
      (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(mode != ACCOUNT_TRADE_MODE_DEMO)
   {
      Print("[PROBE-PENDING-W11][CRITICAL] Conta NAO e Demo (",
            EnumToString(mode), "). Rejeitado. RESEARCH ONLY.");
      return INIT_FAILED;
   }
   // Guard 2: confirmacao do operador
   if(!InpConfirmDemoLab)
   {
      Print("[PROBE-PENDING-W11][ERROR] InpConfirmDemoLab=false. "
            "Configure como true para confirmar execucao em Demo de pesquisa.");
      return INIT_PARAMETERS_INCORRECT;
   }
   // Guard 3: negociacao permitida
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
   {
      Print("[PROBE-PENDING-W11][ERROR] Negociacao nao permitida nesta conta.");
      return INIT_FAILED;
   }

   if(!InitSymbolMeta()) return INIT_FAILED;

   // Definicoes dos 4 casos da matriz
   g_case_defs[0].label = "BUY_LIMIT";  g_case_defs[0].order_type = ORDER_TYPE_BUY_LIMIT;
   g_case_defs[1].label = "SELL_LIMIT"; g_case_defs[1].order_type = ORDER_TYPE_SELL_LIMIT;
   g_case_defs[2].label = "BUY_STOP";   g_case_defs[2].order_type = ORDER_TYPE_BUY_STOP;
   g_case_defs[3].label = "SELL_STOP";  g_case_defs[3].order_type = ORDER_TYPE_SELL_STOP;

   // Inicializar resultados como BLOCKED
   for(int i = 0; i < 4; i++)
   {
      ZeroMemory(g_results[i]);
      g_results[i].label          = g_case_defs[i].label;
      g_results[i].outcome        = "BLOCKED";
      g_results[i].outcome_detail = "Nao executado.";
      g_results[i].sl_class       = "N/A";
   }

   // Abrir log (append)
   g_file = FileOpen("probe_pending_order_gate_w11_log.txt",
                     FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   if(g_file != INVALID_HANDLE) FileSeek(g_file, 0, SEEK_END);

   PLog("INIT",
        StringFormat("RESEARCH ONLY v1.02 - W11 Pending Gate. "
                     "account=%I64u server=%s margin=%s "
                     "sym=%s digits=%d tick=%.5f stops=%d freeze=%d "
                     "exec=%s pending_filling=%s market_filling=%s vol_used=%.2f "
                     "expiry_specified=%s expiry_gtc=%s "
                     "run_probe=%s",
                     AccountInfoInteger(ACCOUNT_LOGIN),
                     AccountInfoString(ACCOUNT_SERVER),
                     g_margin_mode,
                     InpSymbol, g_digits, g_tick_size,
                     (int)g_stops_level, (int)g_freeze_level,
                     EnumToString(g_exec_mode), EnumToString(g_pending_filling),
                     EnumToString(g_market_filling),
                     g_vol_used,
                     (g_has_specified ? "SIM" : "NAO"),
                     (g_has_gtc       ? "SIM" : "NAO"),
                     (InpRunProbe     ? "SIM" : "NAO (standby)")));

   if(!InpRunProbe)
   {
      PLog("STANDBY", "InpRunProbe=false. Nenhuma ordem sera colocada. "
           "Recarregar com InpRunProbe=true para ativar.");
   }

   g_probe_state = (InpRunProbe ? PROBE_RUNNING : PROBE_IDLE);
   g_case_index  = 0;
   g_case_state  = CS_PRE_CHECK;
   ResetCaseState();

   EventSetMillisecondTimer(InpTimerMs);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();

   if(g_probe_state == PROBE_RUNNING)
   {
      PLog("DEINIT_CLEANUP",
           "EA descarregado durante execucao. Cancelando ordens e posicao experimental.");
      CancelCurrentOrder();
      if(g_cur_pos_id > 0) CloseProbePosition(g_cur_pos_id);
      PrintFinalReport();
   }

   PLog("DEINIT",
        StringFormat("reason=%d probe_state=%d case=%d txn=%I64u",
                     reason, (int)g_probe_state,
                     g_case_index, g_txn_count));

   if(g_file != INVALID_HANDLE) FileClose(g_file);
   g_file = INVALID_HANDLE;
}

//+------------------------------------------------------------------+
//| OnTimer -- maquina de estados sequencial                        |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(g_probe_state == PROBE_IDLE || g_probe_state == PROBE_DONE) return;

   // Todos os casos processados?
   if(g_case_index >= 4)
   {
      PrintFinalReport();
      g_probe_state = PROBE_DONE;
      return;
   }

   int idx = g_case_index;
   string lbl = g_case_defs[idx].label;

   switch(g_case_state)
   {
      //----------------------------------------------------------------
      case CS_PRE_CHECK:
      {
         PLog("CASE_START", StringFormat("=== Caso %d/4: %s ===", idx + 1, lbl));
         string reason;
         if(!CasePreCheck(InpSymbol, reason))
         {
            PLog("BLOCKED",
                 StringFormat("Caso %s BLOCKED no pre-check: %s", lbl, reason));
            g_results[idx].outcome        = "BLOCKED";
            g_results[idx].outcome_detail = "PRE_CHECK: " + reason;
            g_case_state = CS_NEXT;
            return;
         }
         PLog("PRE_CHECK_OK",
              StringFormat("Caso %s: inventario vazio; condicoes OK.", lbl));
         g_case_state = CS_PLACING;
         return;
      }

      //----------------------------------------------------------------
      case CS_PLACING:
      {
         double entry = 0.0, sl = 0.0, tp = 0.0;
         string reason;
         if(!ComputePrices(g_case_defs[idx].order_type, entry, sl, tp, reason))
         {
            PLog("BLOCKED",
                 StringFormat("Caso %s BLOCKED no calculo de precos: %s", lbl, reason));
            g_results[idx].outcome        = "BLOCKED";
            g_results[idx].outcome_detail = "COMPUTE_PRICES: " + reason;
            g_case_state = CS_NEXT;
            return;
         }

         g_results[idx].price_req = entry;
         g_results[idx].sl_req    = sl;
         g_results[idx].tp_req    = tp;
         g_results[idx].label     = lbl;

         if(!PlaceOrder(lbl, g_case_defs[idx].order_type, entry, sl, tp, reason))
         {
            PLog("BLOCKED",
                 StringFormat("Caso %s BLOCKED no PlaceOrder: %s", lbl, reason));
            g_results[idx].outcome        = "BLOCKED";
            g_results[idx].outcome_detail = "PLACE_ORDER: " + reason;
            g_case_state = CS_NEXT;
            return;
         }

         g_results[idx].order_ticket = g_cur_ticket;
         g_results[idx].price_acc    = g_cur_price_acc;
         g_results[idx].sl_acc       = g_cur_sl_acc;
         g_results[idx].tp_acc       = g_cur_tp_acc;

         g_case_cycles = 0;
         g_case_state  = CS_MONITORING;
         PLog("MONITORING_START",
              StringFormat("Caso %s: ticket=#%I64u em monitoramento. "
                           "Max %d ciclos (~%d s).",
                           lbl, g_cur_ticket, InpMaxCaseCycles,
                           InpMaxCaseCycles * InpTimerMs / 1000));
         return;
      }

      //----------------------------------------------------------------
      case CS_MONITORING:
      {
         g_case_cycles++;
         g_results[idx].events_seen = g_cur_events;

         // Verificar se a ordem ainda existe como pendente
         if(g_order_placed && !g_order_deleted && !OrderSelect(g_cur_ticket))
         {
            // Ordem saiu do livro pendente sem ORDER_DELETE visto ainda
            // (pode ter chegado o DELETE e DEAL_ADD juntos)
            g_order_deleted = true;
            PLog("MONITORING",
                 StringFormat("Caso %s: ticket=#%I64u nao mais no livro pendente.",
                              lbl, g_cur_ticket));
         }

         // Se deal foi encontrado, aguardar delay e ir para evidencia
         if(g_deal_found)
         {
            g_deal_delay++;
            if(InpVerboseScans)
               PLog("MONITORING",
                    StringFormat("Caso %s: deal encontrado; aguardando delay %d/%d.",
                                 lbl, g_deal_delay, EVIDENCE_DELAY));
            if(g_deal_delay >= EVIDENCE_DELAY)
               g_case_state = CS_EVIDENCE;
            return;
         }

         // Timeout
         if(g_case_cycles >= InpMaxCaseCycles)
         {
            PLog("TIMEOUT",
                 StringFormat("Caso %s: timeout apos %d ciclos sem ativacao.",
                              lbl, g_case_cycles));
            g_results[idx].outcome        = "BLOCKED";
            g_results[idx].outcome_detail =
               StringFormat("TIMEOUT: %d ciclos sem DEAL_ADD.", g_case_cycles);
            g_case_state = CS_CLEANUP;
            return;
         }

         // Ordem expirou/cancelada sem ativacao (ORDER_DELETE sem DEAL_ADD)
         if(g_order_deleted && !g_deal_found &&
            g_order_deleted_cycle >= 0 &&
            g_case_cycles - g_order_deleted_cycle >= 2)
         {
            PLog("EXPIRED_NOT_ACTIVATED",
                 StringFormat("Caso %s: ORDER_DELETE sem DEAL_ADD correspondente. "
                              "Ordem expirou ou foi cancelada.", lbl));
            g_results[idx].outcome        = "BLOCKED";
            g_results[idx].outcome_detail = "ORDER_DELETE sem ativacao observada.";
            g_case_state = CS_CLEANUP;
            return;
         }

         if(InpVerboseScans)
            PLog("MONITORING_CYCLE",
                 StringFormat("Caso %s: ciclo=%d/%d deal_found=%s pos_event=%s",
                              lbl, g_case_cycles, InpMaxCaseCycles,
                              (g_deal_found ? "SIM" : "NAO"),
                              (g_pos_event_rcvd ? "SIM" : "NAO")));
         return;
      }

      //----------------------------------------------------------------
      case CS_EVIDENCE:
      {
         EvaluateCase(idx);
         g_case_state = CS_CLEANUP;
         return;
      }

      //----------------------------------------------------------------
      case CS_CLEANUP:
      {
         PLog("CLEANUP_START",
              StringFormat("Caso %s: iniciando limpeza.", lbl));

         // Cancelar ordem pendente se ainda existir
         CancelCurrentOrder();

         // Fechar posicao experimental se existir (higiene)
         if(g_cur_pos_id > 0)
            CloseProbePosition(g_cur_pos_id);

         PLog("CLEANUP_DONE",
              StringFormat("Caso %s: limpeza concluida. Resultado: %s | %s",
                           lbl, g_results[idx].outcome,
                           g_results[idx].outcome_detail));
         g_case_state = CS_NEXT;
         return;
      }

      //----------------------------------------------------------------
      case CS_NEXT:
      {
         g_case_index++;
         ResetCaseState();
         g_case_state = CS_PRE_CHECK;
         if(g_case_index < 4)
         {
            PLog("NEXT_CASE",
                 StringFormat("Avancando para caso %d/4: %s",
                              g_case_index + 1,
                              g_case_defs[g_case_index].label));
         }
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| OnTradeTransaction -- coleta de eventos; sem acoes comerciais   |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   g_txn_count++;

   PLog("TXN",
        StringFormat("seq=%I64u type=%s order=#%I64u deal=#%I64u "
                     "position=#%I64u sym=%s "
                     "price=%.5f price_sl=%.5f price_tp=%.5f vol=%.2f "
                     "req_magic=%d req_id=%u retcode=%u",
                     g_txn_count, EnumToString(trans.type),
                     trans.order, trans.deal, trans.position,
                     trans.symbol,
                     trans.price, trans.price_sl, trans.price_tp,
                     trans.volume,
                     request.magic, result.request_id, result.retcode));

   if(g_probe_state != PROBE_RUNNING) return;
   if(g_case_state != CS_MONITORING && g_case_state != CS_PLACING) return;
   if(g_cur_ticket == 0) return;

   // Verificar se o evento e relevante para o nosso ticket
   bool our_order   = (trans.order == g_cur_ticket);
   bool our_pos_evt = (trans.position > 0 && trans.position == g_cur_pos_id);

   // ORDER_ADD: confirmacao do servidor
   if(trans.type == TRADE_TRANSACTION_ORDER_ADD && our_order)
   {
      g_server_acked = true;
      g_cur_events++;
      PLog("ORDER_SERVER_CONFIRM",
           StringFormat("label=%s ticket=#%I64u confirmado no servidor.",
                        g_case_defs[g_case_index].label, trans.order));
   }

   // ORDER_UPDATE
   if(trans.type == TRADE_TRANSACTION_ORDER_UPDATE && our_order)
   {
      g_cur_events++;
      PLog("ORDER_UPDATE",
           StringFormat("label=%s ticket=#%I64u atualizado.",
                        g_case_defs[g_case_index].label, trans.order));
   }

   // ORDER_DELETE: ordem saiu do livro pendente
   if(trans.type == TRADE_TRANSACTION_ORDER_DELETE && our_order)
   {
      g_order_deleted = true;
      g_order_deleted_cycle = g_case_cycles;
      g_cur_events++;
      PLog("ORDER_DELETE",
           StringFormat("label=%s ticket=#%I64u removido do livro pendente.",
                        g_case_defs[g_case_index].label, trans.order));
   }

   // DEAL_ADD: correlacao robusta order->deal->position (Restr. [8])
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal > 0)
   {
      // Tentar via historico: DEAL_ORDER deve corresponder ao nosso ticket
      bool match = false;
      ulong deal_pos_id = 0;

      if(HistoryDealSelect(trans.deal))
      {
         ulong deal_order = (ulong)HistoryDealGetInteger(trans.deal, DEAL_ORDER);
         if(deal_order == g_cur_ticket)
         {
            match = true;
            deal_pos_id = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
         }
      }

      // Fallback estrito: o proprio evento precisa carregar nosso order ticket.
      if(!match && trans.order == g_cur_ticket && trans.position > 0 &&
         trans.symbol == InpSymbol && !g_deal_found)
      {
         match       = true;
         deal_pos_id = trans.position;
         PLog("DEAL_FALLBACK",
              StringFormat("label=%s DEAL_ADD correlacionado via trans.position "
                           "(HistoryDealSelect falhou); deal=#%I64u pos=#%I64u.",
                           g_case_defs[g_case_index].label,
                           trans.deal, trans.position));
      }

      if(match && !g_deal_found)
      {
         g_deal_found     = true;
         g_cur_deal       = trans.deal;
         g_cur_pos_id     = (deal_pos_id > 0 ? deal_pos_id : trans.position);
         g_cur_events++;

         PLog("DEAL_ADD",
              StringFormat("label=%s deal=#%I64u pos_id=#%I64u "
                           "price=%.5f price_sl_trans=%.5f price_tp_trans=%.5f",
                           g_case_defs[g_case_index].label,
                           g_cur_deal, g_cur_pos_id,
                           trans.price, trans.price_sl, trans.price_tp));
      }
   }

   // POSITION: posicao atualizada no servidor (SL/TP propagados)
   if(trans.type == TRADE_TRANSACTION_POSITION)
   {
      if(our_pos_evt || (g_deal_found && trans.position == g_cur_pos_id))
      {
         g_pos_event_rcvd = true;
         g_cur_events++;
         PLog("POSITION_EVENT",
              StringFormat("label=%s pos=#%I64u "
                           "price_sl_trans=%.5f price_tp_trans=%.5f",
                           g_case_defs[g_case_index].label,
                           trans.position,
                           trans.price_sl, trans.price_tp));
      }
   }
}

//+------------------------------------------------------------------+
//| OnTick -- reconciliacao adicional apos ativacao                 |
//+------------------------------------------------------------------+
void OnTick()
{
   if(g_probe_state != PROBE_RUNNING) return;
   if(g_case_state != CS_MONITORING) return;

   // Se deal foi encontrado mas ainda sem evidencia de posicao, tenta agora
   if(g_deal_found && g_cur_pos_id > 0 && !g_pos_event_rcvd)
   {
      ulong pos_ticket = 0;
      if(SelectPositionByIdentifier(g_cur_pos_id, pos_ticket))
         g_pos_event_rcvd = true;
   }
}
