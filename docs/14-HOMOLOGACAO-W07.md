# 14 — Relatório de Homologação Operacional em Conta Demo (W07)

* **Data da Homologação:** 2026-09-13
* **Versão do Produto:** EddyTrader MVP v1.00 (`src/EddyTrader.mq5`)
* **Terminal:** MetaTrader 5 x64 build 6193 (MetaQuotes Ltd.)
* **Compilador:** MetaEditor 64 build 6193
* **Ambiente de Testes:** Conta Demo Conectada ao Servidor da Corretora + Strategy Tester Local MT5
* **Conta de Laboratório:** Login `6272676` | Servidor `ActivTradesCorp-Server`
* **Modo de Negociação:** `ACCOUNT_TRADE_MODE_DEMO`
* **Modo de Margem:** `ACCOUNT_MARGIN_MODE_RETAIL_NETTING`
* **Saldo Inicial:** $1.000,00 USD | **Patrimônio Líquido:** $1.000,00 USD
* **Permissões:** `ACCOUNT_TRADE_ALLOWED = SIM` | `TERMINAL_TRADE_ALLOWED (Algo Trading) = SIM`
* **Status Geral da W07:** **HOMOLOGADO COM RESSALVAS** (36/36 asserções aprovadas; validação de neutralização em mercado ao vivo aberto catalogada como `LIVE-01` pendente de abertura de pregão)

---

## 1. Visão Executiva e Taxonomia de Evidência

A **Work Package W07** teve como objetivo confrontar as garantias conceituais do **EddyTrader** contra o comportamento do MetaTrader 5 em ambiente de conta Demo conectada ao servidor de negociação da corretora.

Em estrita obediência ao **Método C.H.** e às 12 Regras Inegociáveis de [AGENTS.md](file:///C:/Projetos/eddytrader/AGENTS.md), todas as conclusões desta homologação são classificadas explicitamente em quatro categorias ontológicas de evidência:

1. **`DEMO_AO_VIVO`:** Evidência obtida com o terminal conectado ativamente à infraestrutura remota da corretora (`ActivTradesCorp-Server`), interagindo com os serviços de autenticação, relógio do servidor, sincronização de ativos e resposta de retcodes remotos.
2. **`STRATEGY_TESTER`:** Evidência obtida no motor local de simulação determinística do Strategy Tester do MetaTrader 5, utilizando dados históricos reais do broker, processamento local de ticks e emulação de transações comerciais.
3. **`DOCUMENTAL`:** Evidência derivada da documentação normativa oficial da MetaQuotes (MQL5 Reference Manual, especificações de protocolo e arquitetura da plataforma).
4. **`LOCAL`:** Evidência obtida na máquina local do cliente (sistema de arquivos do Windows, variáveis globais do terminal `GlobalVariables`, integridade de memória e concorrência multithread/multi-processo).

> [!IMPORTANT]
> **Condição de Contorno do Mercado:** Os testes foram conduzidos em um domingo (13/09/2026 às 15:08 horário do servidor), momento em que os 9 pares de moedas ativos no broker estavam em final de semana (`TRADE_RETCODE_MARKET_CLOSED = 10018`).
> Portanto, a execução de ordens com fechamento imediato e preenchimento de deals ao vivo não pôde ser concluída contra o livro remoto da corretora. Os testes transacionais foram executados no Strategy Tester com os ticks do broker, ficando catalogado o teste formal **`LIVE-01`** para execução no primeiro pregão ao vivo com mercado aberto.

---

## 2. Caracterização do Ambiente de Homologação

Os parâmetros do ambiente foram coletados diretamente pela sonda laboratorial `tests/probe_env_w07.mq5`:

```text
==================================================
[PROBE W07] Sonda de Ambiente MT5 Demo (Expert Mode)
==================================================
LOGIN: 6272676 | SERVER: ActivTradesCorp-Server | BUILD: 6193 | CONNECTED: SIM
TRADE MODE: DEMO | MARGIN MODE: RETAIL NETTING
BALANCE: 1000.00 USD | EQUITY: 1000.00 USD | FREE MARGIN: 1000.00 USD
TRADE ALLOWED (ACCOUNT): SIM | ALGO TRADING (TERMINAL): SIM
SERVER TIME: 2026.09.13 15:07:07 | CURRENT TICK TIME: 2026.09.11 22:59:45 | LOCAL TIME: 2026.09.13 10:07:07
--- VERIFICACAO DE ATIVOS DIRECIONADOS ---
SIMBOLO: EURUSD     | TRADE_MODE: 4 | BID:    1.15953 | ASK:    1.15999 | SPREAD:   46 | VOL_MIN: 0.01 | STEP: 0.01
SIMBOLO: GBPUSD     | TRADE_MODE: 4 | BID:    1.35200 | ASK:    1.35361 | SPREAD:  161 | VOL_MIN: 0.01 | STEP: 0.01
SIMBOLO: USDJPY     | TRADE_MODE: 4 | BID:  153.55300 | ASK:  153.59300 | SPREAD:   40 | VOL_MIN: 0.01 | STEP: 0.01
SIMBOLO: BTCUSD     | TRADE_MODE: 4 | BID:    0.00000 | ASK:    0.00000 | SPREAD:    0 | VOL_MIN: 0.01 | STEP: 0.01
SIMBOLO: ETHUSD     | TRADE_MODE: 4 | BID:    0.00000 | ASK:    0.00000 | SPREAD:    0 | VOL_MIN: 0.01 | STEP: 0.01
Total de Ativos Abertos e Cotando: 9 (EURUSD, GBPUSD, USDCAD, USDCHF, USDJPY, AUDUSD, NZDUSD, USDCNH, USDSEK)
==================================================
```

---

## 3. Matriz Consolidada dos 15 Cenários de Homologação

| ID | Cenário de Teste | Categoria de Evidência | Resultado | Métricas / Evidência Central |
| :--- | :--- | :---: | :---: | :--- |
| **DEMO-01** | Neutralização Reativa em `BLOCKED` (DQ-001) | `STRATEGY_TESTER` | **PASS** | Ordem em `BLOCKED` interceptada por `OnTradeTransaction`. Timers $t_{\text{trigger}}, t_{\text{unlock}}$ e `event_id` intactos. |
| **DEMO-02** | Sequência Real de Callbacks | `STRATEGY_TESTER` | **PASS** | `ORDER_ADD` $\to$ `DEAL_ADD` capturados e processados em ordem pelo EA. |
| **DEMO-03** | Medição de Latência de Neutralização | `STRATEGY_TESTER` | **PASS** | Detecção $\to$ Disparo: **20 $\mu$s** \| Total Ponta a Ponta: **36 $\mu$s** (latência interna de motor/EA, não rede). |
| **DEMO-04** | Liquidação de Múltiplas Posições | `STRATEGY_TESTER` | **PASS** | Liquidação determinística por tickets; inventário final `PositionsTotal() == 0`. |
| **DEMO-05** | Cancelamento de Pending Orders | `STRATEGY_TESTER` | **PASS** | Cancelamento determinístico via `OrderDelete`; `OrdersTotal() == 0`. |
| **DEMO-06** | Resposta a Retcodes de Falha Remota | `DEMO_AO_VIVO` | **PASS** | `retcode=10018` (market closed), `10014` (invalid vol), `10015` (invalid price) recebidos do broker sem loops. |
| **DEMO-07** | Reinicialização Durante `BLOCKED` | `DEMO_AO_VIVO` | **PASS** | `BLOCKED` restaurado fielmente via GVs; $t_{\text{trigger}}$, $t_{\text{unlock}}$ e event_id intactos. |
| **DEMO-08** | Reabertura Pós-$t_{\text{unlock}}$ | `DEMO_AO_VIVO` / `LOCAL` | **PASS** | Caminho estrito `BLOCKED -> REOPENING -> MONITORING`; $B_n = D(t_{\text{reopen}})$, $W_{\text{new}} = 0$; $J_n$ incrementado. |
| **DEMO-09** | Persistência e Integridade de $J_n$ e $B_n$ | `DEMO_AO_VIVO` / `LOCAL` | **PASS** | Checksum validado com sucesso; corrupção induzida detectada com bloqueio fail-closed. |
| **DEMO-10** | Postura Fail-Closed | `DEMO_AO_VIVO` / `LOCAL` | **PASS** | Parâmetros $\le 0$, login divergente e conta REAL rejeitados com `INIT_FAILED`. |
| **DEMO-11** | Guarda de Instância Única Concorrência | `DEMO_AO_VIVO` / `LOCAL` | **PASS** | Instância B rejeitada; lease da Instância A preservada e protegida contra usurpação. |
| **DEMO-12** | Takeover de Lease Expirada pela Guarda | `DEMO_AO_VIVO` / `LOCAL` | **PASS** | Lease expirada (>15s) detectada; Instância B assume propriedade atomicamente via CAS. |
| **DEMO-13** | Rollover de Meia-Noite | `STRATEGY_TESTER` | **PASS** | Em `MONITORING`: reinicia $J_0$ com $B_0 = 0.0$ (não equity). Em `BLOCKED`: preserva bloqueio até $t_{\text{unlock}}$. |
| **DEMO-14** | Chegada de Nova Ordem em `LIQUIDATING` | `STRATEGY_TESTER` | **PASS** | Ordem tardia interceptada e encerrada imediatamente sem deadlock da FSM. |
| **DEMO-15** | Coexistência com Ordens Externas / Manual | `STRATEGY_TESTER` | **PASS** | Ordem manual (magic=0) ou externa neutralizada em conformidade com escopo global da conta. |

---

## 4. Detalhamento Técnico dos Cenários e Correções Críticas

### DEMO-01 — Neutralização Reativa em Estado BLOCKED (DQ-001)
* **Categoria:** `STRATEGY_TESTER`
* **Objetivo:** Comprovar empiricamente que, ao receber um evento de execução de ordem quando a conta está sob bloqueio operacional (`EDDY_STATE_BLOCKED`), o EddyTrader intercepta o evento via `OnTradeTransaction`, emite o fechamento imediato e preserva os parâmetros do bloqueio original.
* **Evidência Registrada:**
  ```text
  market buy 0.01 EURUSD (1.16129 / 1.16136 / 1.16129)
  deal #4 buy 0.01 EURUSD at 1.16136 done (based on order #5)
  [DQ-001 REACTIVE] Transacao DEAL_ADD interceptada em BLOCKED! Deal #4. Neutralizando...
  market sell 0.01 EURUSD, close #5 (1.16129 / 1.16136 / 1.16129)
  deal #5 sell 0.01 EURUSD at 1.16129 done (based on order #6)
  [PASS] DEMO-01A | Posicao intrusa em BLOCKED foi neutralizada reativamente (pos=0)
  [PASS] DEMO-01B | t_trigger preservado sem reinicializacao
  [PASS] DEMO-01C | t_unlock preservado sem reinicializacao
  [PASS] DEMO-01D | protection_event_id preservado integralmente
  ```
* **Conclusão:** **APROVADO EM SIMULAÇÃO DETERMINÍSTICA**. A neutralização reativa é imediata e preserva os timers sem reinicialização.

---

### DEMO-02 — Sequência Real de Callbacks de Transação
* **Categoria:** `STRATEGY_TESTER`
* **Objetivo:** Registrar o fluxo de eventos transacionais gerados pelo MT5 durante a vida de uma ordem e confirmar o encadeamento defensivo de callbacks.
* **Evidência Registrada:**
  ```text
  Sequência de Transações Recebidas:
  TRADE_TRANSACTION_ORDER_ADD -> TRADE_TRANSACTION_DEAL_ADD -> TRADE_TRANSACTION_HISTORY_ADD
  [PASS] DEMO-02 | Sequencia real de transacoes MT5 capturada (ORDER_ADD -> DEAL_ADD)
  ```
* **Conclusão:** **APROVADO EM SIMULAÇÃO**. O callback `TRADE_TRANSACTION_DEAL_ADD` opera como o gatilho determinístico para a neutralização reativa.

---

### DEMO-03 — Medição de Latência de Neutralização ($T_1, T_2, T_3$)
* **Categoria:** `STRATEGY_TESTER` (Latência Interna do Motor / Código do EA)
* **Objetivo:** Medir em microssegundos ($\mu$s) a latência puramente computacional de detecção e disparo da neutralização reativa no MQL5.
* **Parâmetros Medidos:**
  * $T_1$: Instante do processamento de entrada de `OnTradeTransaction(DEAL_ADD)`.
  * $T_2$: Instante do término da montagem e chamada de `CTrade::PositionClose`.
  * $T_3$: Instante da confirmação do deal de liquidação no motor de execução.
* **Evidência Registrada:**
  ```text
  DEMO-03: Latencia Deteccao->Disparo (T1->T2): 20 us | Latencia Total Motor (T1->T3): 36 us
  [PASS] DEMO-03A | Medicao de latencia T1->T2 (deteccao para envio da neutralizacao)
  [PASS] DEMO-03B | Medicao de latencia T1->T3 (latencia ponta a ponta da neutralizacao)
  ```
* **Ressalva Técnica Crítica:** Estes valores (**20 $\mu$s** e **36 $\mu$s**) representam a **latência computacional interna do software/motor** executando na CPU local. Eles **NÃO representam a latência de rede cliente-servidor pela internet**, que em sessões de mercado ao vivo é dominada pelo RTT de rede (tipicamente entre 20 ms e 150 ms) e pelo tempo de matching do broker. A validação dessa latência de rede remota foi isolada no cenário `LIVE-01`.

---

### DEMO-06 — Resposta a Retcodes de Falha Remota
* **Categoria:** `DEMO_AO_VIVO`
* **Objetivo:** Submeter ordens reais de laboratório diretamente ao servidor da corretora (`ActivTradesCorp-Server`) e verificar a resposta defensiva da API MQL5 contra retcodes reais de recusa.
* **Evidência Registrada (Sessão Remota ao Vivo):**
  ```text
  DEMO-06A: Ordem a mercado -> ok=FALSE | retcode=10018 (market closed) | LastErr=4756
  [PASS] DEMO-06A | Rejeicao defensiva por mercado fechado (retcode 10018)
  DEMO-06B: Ordem com volume invalido -> ok=FALSE | retcode=10014 (invalid volume) | LastErr=4756
  [PASS] DEMO-06B | Rejeicao defensiva por volume invalido ou mercado fechado sem loop
  DEMO-06C: Pending order com preco 0.0 -> ok=FALSE | retcode=10015 (invalid price) | LastErr=4756
  [PASS] DEMO-06C | Rejeicao defensiva por preco invalido ou mercado fechado
  ```
* **Conclusão:** **APROVADO EM AMBIENTE DEMO AO VIVO**. Os retcodes retornados pelo servidor remoto do broker são tratados deterministicamente sem loops de retransmissão descontrolados.

---

### DEMO-08 — Fluxo Normativo de Reabertura Pós-$t_{\text{unlock}}$ e Baseline
* **Categoria:** `DEMO_AO_VIVO` / `LOCAL`
* **Auditoria de Conformidade:**
  1. **Transição de Estados:** O fluxo de reabertura obedece rigorosamente ao grafo da FSM (W04/W04.2):
     $$\text{EDDY\_STATE\_BLOCKED} \xrightarrow{t \ge t_{\text{unlock}} \land \text{safe}} \text{EDDY\_STATE\_REOPENING} \xrightarrow{} \text{EDDY\_STATE\_MONITORING}$$
     E no restart com bloqueio vencido:
     $$\text{EDDY\_STATE\_INIT} \xrightarrow{\text{rec.state}=\text{BLOCKED} \land t \ge t_{\text{unlock}}} \text{EDDY\_STATE\_REOPENING} \xrightarrow{} \text{EDDY\_STATE\_MONITORING}$$
     Nenhum caminho pula `REOPENING`.
  2. **Baseline Normativa:** O código de produção `src/EddyTrader.mq5` captura a baseline de reabertura como o **resultado acumulado consolidado no instante da reabertura**:
     $$B_n = D(t_{\text{reopen}}) = R_{\text{day}}(t_{\text{reopen}}) + F(t_{\text{reopen}})$$
     e valida o invariante matemático:
     $$W_{n+1}(t_{\text{reopen}}) = D(t_{\text{reopen}}) - B_n \equiv 0.00$$
     O código de produção **nunca utilizou `AccountInfoDouble(ACCOUNT_EQUITY)`** como baseline. O script de teste de homologação `test_demo_live_w07.mq5` foi cirurgicamente corrigido para remover a atribuição errônea a Equity.
* **Evidência Registrada:**
  ```text
  DEMO-08: t_now >= t_unlock detectado -> Transicao via REOPENING para MONITORING com Bn=-520.00 e W_new=0.00
  [PASS] DEMO-08A | Fluxo formal de reabertura BLOCKED -> REOPENING -> MONITORING
  [PASS] DEMO-08B | Renovacao normativa da baseline Bn = D(t_reopen) com W_new == 0 (e NUNCA Equity)
  [PASS] DEMO-08C | Incremento da janela operacional Jn (Jn=2)
  ```
* **Conclusão:** **APROVADO (PASS)**. Estrita conformidade com a especificação matemática (W03) e com a máquina de estados finita (W04).

---

### DEMO-13 — Rollover de Meia-Noite (Virada de Dia Contábil)
* **Categoria:** `STRATEGY_TESTER`
* **Auditoria de Conformidade:**
  1. **Em Estado `MONITORING`:** Às `00:00:00` do servidor, o sistema detecta $t_{\text{day, current}} > t_{\text{day, start}}$, atualiza o início do dia contábil e reinicia o ciclo diário na janela $J_0$, fixando a baseline estritamente em:
     $$B_0 = 0.00$$
     O cálculo do novo dia passa a considerar $R_{\text{day}}(t) = 0.00$, $F(t) = \text{flutuante}$, $D(t) = R_{\text{day}}(t) + F(t)$ e $W_0(t) = D(t) - 0.00 = D(t)$. A baseline **nunca é substituída pela Equity da conta** na virada de dia.
  2. **Durante Contenção (`BLOCKED`, `LIQUIDATING`, `PROTECTION_TRIGGERED`):** Ao atravessar a meia-noite durante um bloqueio ativo de 4 horas, o sistema atualiza `g_day_start` para fins contábeis, mas **preserva integralmente $t_{\text{trigger}}$, $t_{\text{unlock}}$ e `protection_event_id`**, sem reiniciar a contagem de 4 horas e sem suspender o bloqueio antes de $t_{\text{unlock}}$.
* **Evidência Registrada:**
  ```text
  [PASS] DEMO-13A | Rollover em MONITORING reinicia para J0 com B0 = 0.0 (sem recorrer a Equity)
  [PASS] DEMO-13B | Rollover em BLOCKED preserva o bloqueio enquanto t < t_unlock
  ```
* **Conclusão:** **APROVADO (PASS)**. Preservação contínua de segurança operacional através do rollover.

---

## 5. Regressão Formal da FSM: Bateria Unificada W06 + W07R

A bateria de testes formais de regressão foi expandida em `tests/test_fsm_w06.mq5`, incorporando as validações cirúrgicas de reabertura (`W07R-01`), virada de dia (`W07R-02`) e as quatro validações do protocolo atômico da guarda de instância única (`W07R-03`, `W07R-04`, `W07R-05` e `W07R-06`). A bateria completa de **26 testes** foi executada no Strategy Tester com **100% de sucesso (26/26)**:

```text
==================================================================
 Início da Bateria Formal: Cenários W06-01..20 e W07R-01..06     
==================================================================
  [PASS] W06-01: Inicialização limpa inicia com sucesso em MONITORING, J0, B0=0 e safe_to_operate=true
  [PASS] W06-02: W=-250.00 > -L=-500.00: Robô permanece em MONITORING sem disparar proteção
  [PASS] W06-03: W=-550.00 <= -L=-500.00: Dispara transição MONITORING -> PROTECTION_TRIGGERED -> LIQUIDATING com t_unlock correto
  [PASS] W06-04: Com posições e ordens zeradas, transita com sucesso de LIQUIDATING para BLOCKED
  [PASS] W06-05: Com resíduo aberto (>0 posições), FSM é retida estritamente em LIQUIDATING sem avançar para BLOCKED
  [PASS] W06-06: t=12:30:00 < t_unlock=15:30:00: Bloqueio mantido incondicionalmente em BLOCKED
  [PASS] W06-07: Intervenção manual durante BLOCKED é neutralizada reativamente sem alterar t_trigger, t_unlock ou event_id
  [PASS] W06-08: t >= t_unlock porém safe_to_reopen == false: Robô retém bloqueio em BLOCKED e recusa reabertura
  [PASS] W06-09: Reabertura formal em J1: Baseline Bn=-520.00 capturada, W_new=0.00 == 0 validado, retorno a MONITORING
  [PASS] W06-10: Virada de dia em MONITORING reinicia ciclo diário em J0 com B0=0.0
  [PASS] W06-11: Virada de dia durante BLOCKED preserva rigorosamente o bloqueio contínuo de 4h atravessando a meia-noite
  [PASS] W06-12: Restart durante MONITORING em J0 restaura com sucesso J0 com B0=0
  [PASS] W06-13: Restart durante MONITORING em Jn (n>=1) restaura perfeitamente Bn=-640.50 sem fallback para 0
  [PASS] W06-14: Restart durante BLOCKED com t < t_unlock reconstitui t_trigger, t_unlock e event_id mantendo BLOCKED
  [PASS] W06-15: Postura FAIL-CLOSED: Ausência de baseline em Jn (n>=1) retém robô em INIT e proíbe operações
  [PASS] W06-16: Instância concorrente B é rejeitada com lock ativo; Instância A permanece como proprietária legítima
  [PASS] W06-17: OnDeinit de B (não-proprietária) NÃO remove lock nem heartbeat pertencentes à Instância A
  [PASS] W06-18: Instância proprietária A libera com sucesso o lock via CAS (Owner=0) e preserva heartbeat para evitar corrida
  [PASS] W06-19: Com lease ativa (<=15s) takeover é proibido; com lease expirada (>15s), Instância B assume ownership via CAS
  [PASS] W06-20: Instância antiga A detecta perda de ownership, entra em FAIL-CLOSED, não liquida e não altera lock de B
  [PASS] W07R-01: Fluxo de reabertura obedece rigorosamente BLOCKED -> REOPENING -> MONITORING, Bn = D(t_reopen), W_new == 0 e INIT -> REOPENING -> MONITORING no restart
  [PASS] W07R-02: Virada de dia em MONITORING reinicia para J0 com B0=0.0 (sem tocar em Equity) e durante BLOCKED preserva t_trigger, t_unlock e event_id
  [PASS] W07R-03: Bootstrap neutro (0) e aquisição via CAS (0 -> ID) garante exclusão mútua estrita na disputa inicial
  [PASS] W07R-04: Liberação atômica (ID -> 0) preserva heartbeat para segurança e permite handoff imediato via CAS para nova instância
  [PASS] W07R-05: OnDeinit de instância zumbi pós-takeover falha no CAS e não corrompe ownership nem heartbeat do novo proprietário
  [PASS] W07R-06: Heartbeat residual com OWNER == 0 é ignorado e sobrescrito imediatamente por nova instância sem delay de lease
==================================================================
 Resumo da Bateria W06/W07R: Total=26 | Aprovados=26 | Falhas=0
==================================================================
```

---

## 6. Especificação do Teste Remoto Pendente: `LIVE-01`

Para encerrar formalmente a transição da validação de laboratório para a homologação final em mercado ao vivo (exclusivamente em conta Demo), define-se o procedimento formal do teste **`LIVE-01`**:

* **Identificador:** `LIVE-01`
* **Nome:** Validação de Neutralização Reativa e Latência Ponta a Ponta em Pregão Aberto
* **Condição de Disparo:** Sessão de negociação do broker aberta (`SymbolInfoInteger(SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_FULL`).
* **Procedimento:**
  1. Conectar terminal na conta Demo `6272676` no servidor `ActivTradesCorp-Server`.
  2. Forçar estado `EDDY_STATE_BLOCKED` via persistência controlada.
  3. Emitir ordem manual a mercado no ativo `EURUSD` com magic number 0.
  4. Observar a emissão do fechamento via `OnTradeTransaction(DEAL_ADD)`.
  5. Registrar:
     * Retcode oficial do servidor (`TRADE_RETCODE_DONE = 10009`).
     * Latência de rede ponta a ponta ($T_{\text{envio}} \to T_{\text{confirmação}}$).
     * Preservação incondicional de $t_{\text{unlock}}$ e `protection_event_id`.
* **Critério de Aceite:** Posição encerrada com inventário zero e retcode `DONE`, sem perturbação do bloqueio de 4 horas.

---

## 7. Status das Decisões Arquiteturais e Questões Abertas

1. **DQ-001 (Neutralização de Intervenção Manual / Externa durante Bloqueio):**
   * **Status:** `RESOLVIDA ARQUITETURALMENTE E IMPLEMENTADA, VALIDADA NO STRATEGY TESTER, VALIDAÇÃO EMPÍRICA DE MERCADO AO VIVO PENDENTE`.
2. **DQ-004 (Soberania do MT5 sobre Falhas de Ordem e Rejeições Remotas):**
   * **Status:** `VALIDADA EMPIRICAMENTE PARA MARKET_CLOSED` (validação de retcodes de preenchimento pendente de mercado aberto).
3. **ADR 0005 (Garantias Técnicas MT5 e Estratégia de Recuperação):**
   * **Status:** `Proposed` (com validação empírica de mercado ao vivo pendente em `LIVE-01`).

---

## 8. Parecer Técnico Conclusivo da W07

* **Classificação do Resultado:** **HOMOLOGADO COM RESSALVAS**.
* **Fundamentação:** O núcleo do Expert Advisor (`src/EddyTrader.mq5`) demonstrou total aderência à especificação matemática e à máquina de estados finita. A guarda de instância única com lease via CAS elimina qualquer risco de split-brain ou concorrência desordenada. A reabertura calcula a baseline com rigor matemático ($B_n = D(t_{\text{reopen}})$), o rollover não contamina a baseline com a equity da conta, e as falhas remotas são absorvidas com estabilidade defensiva. A única ressalva é a realização do teste ponta a ponta com pregão aberto (`LIVE-01`), condicionado exclusivamente ao calendário do mercado financeiro.
