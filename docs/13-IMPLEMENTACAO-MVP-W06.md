# 13 — Implementação do Expert Advisor Mínimo (MVP — W06)

Este documento formaliza a arquitetura, estrutura de dados, garantias operacionais e resultados dos testes de validação do primeiro Expert Advisor executável do **EddyTrader**, implementado na **Work Package 06 (W06)** em conformidade estrita com o Método C.H. e as definições prévias (W01 a W05).

---

## 1. Visão Geral e Princípio Operacional

O EddyTrader é concebido e implementado exclusivamente como um:
```text
NÚCLEO AUTÔNOMO DE PROTEÇÃO DE CAPITAL E GERENCIADOR DE PERDA DIÁRIA
```

Ele **não** implementa estratégias de negociação, não emite ordens de compra ou venda por análise de mercado, não calcula indicadores técnicos, não define Take Profit ou Stop Loss discricionários e não busca rentabilidade. Sua atuação é estritamente de contenção e defesa patrimonial:
1. **Vigilância Contínua:** Monitora em tempo real o resultado financeiro consolidado da conta ($D(t)$) e da janela operacional ativa ($W_n(t)$).
2. **Disparo Imediato:** Detecta compulsoriamente a violação do limite máximo parametrizado ($W_n(t) \le -L$).
3. **Liquidação Global:** Encerra a mercado todas as posições abertas e cancela 100% das ordens pendentes.
4. **Bloqueio Temporal Disciplinar:** Mantém a conta em regime de contenção por 4 horas contínuas ($14.400$ s).
5. **Neutralização Reativa:** Detecta e elimina imediatamente qualquer nova ordem ou operação manual executada pelo operador durante o bloqueio.
6. **Reconstituição de Estado Determinística:** Recupera com fidelidade a máquina de estados após reinicializações do terminal.
7. **Reabertura Controlada:** Estabelece a nova baseline ($B_{n+1} = D(t_{\text{reopen}})$) garantindo que $W_{n+1}(t_{\text{reopen}}) = 0$ e impedindo o rebloqueio instantâneo.

---

## 2. Arquitetura do Código-Fonte (`src/EddyTrader.mq5`)

O código-fonte foi desenvolvido em **MQL5 nativo puro**, compatível com a compilação de 64 bits do MetaEditor (build 6193), sem qualquer dependência externa de bibliotecas de terceiros, DLLs, chamadas de rede ou banco de dados externo.

### 2.1. Parâmetros de Entrada Normativos (KISS / YAGNI)

```mql5
input group "=== Configurações de Risco ==="
input double InpMaxLoss            = 500.0; // Perda Máxima Permitida por Janela (Moeda da Conta, > 0)
input int    InpBlockDurationHours = 4;     // Duração Contínua do Bloqueio (Horas, min 1)

input group "=== Configurações Operacionais ==="
input int    InpTimerIntervalMs    = 500;   // Intervalo de Varredura do Timer (Milissegundos)
input ulong  InpDeviationPoints    = 10;    // Desvio Máximo / Slippage Tolerado (Pontos)
```

### 2.2. Estados Operacionais da FSM

```mql5
enum ENUM_EDDY_STATE
{
   EDDY_STATE_INIT                 = 0, // Inicialização e Reconstituição de Estado
   EDDY_STATE_MONITORING           = 1, // Vigilância Ativa de Risco
   EDDY_STATE_PROTECTION_TRIGGERED = 2, // Congelamento e Formalização do Gatilho
   EDDY_STATE_LIQUIDATING          = 3, // Contenção e Liquidação Compulsória Global
   EDDY_STATE_BLOCKED              = 4, // Bloqueio Temporal e Manutenção da Proteção
   EDDY_STATE_REOPENING            = 5  // Reabertura Controlada e Nova Baseline
};
```

### 2.3. Estrutura de Estado Recuperável (`EddyRecoveryState`)

```mql5
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
```

---

## 3. Mecanismos Centrais de Engenharia

### 3.1. Esquema de Persistência em Terminal Global Variables (ADR 0005 / GAP-005)

Para garantir que o conjunto mínimo de recuperação $\mathbf{D}_{\text{min\_recovery}}$ sobreviva a falhas elétricas, encerramento do processo `terminal64.exe` ou mudanças de perfil/gráfico, o sistema adota chaves segregadas por conta:

| Sufixo da Chave | Tipo MQL5 | Significado Operacional |
| :--- | :--- | :--- |
| `EDDY_<LOGIN>_STATE` | `double` (cast `int`) | Estado corrente da FSM (`ENUM_EDDY_STATE`). |
| `EDDY_<LOGIN>_WINDOW_ID` | `double` (cast `int`) | Índice da janela intradiária ($J_n$). |
| `EDDY_<LOGIN>_BASELINE` | `double` | Baseline da janela ativa ($B_n$). |
| `EDDY_<LOGIN>_T_TRIGGER` | `double` (cast `datetime`) | Timestamp do servidor no momento do disparo. |
| `EDDY_<LOGIN>_T_UNLOCK` | `double` (cast `datetime`) | Timestamp do servidor para desbloqueio mínimo ($t_{\text{trigger}} + 14.400$ s). |
| `EDDY_<LOGIN>_EVENT_ID` | `double` (cast `ulong`) | Identificador único idempotente do evento de proteção. |
| `EDDY_<LOGIN>_DAY` | `double` (cast `datetime`) | Timestamp de início do dia contábil (`00:00:00`). |
| `EDDY_<LOGIN>_OWNER` | `double` (cast `ulong`) | Identificador numérico da instância proprietária do lock da conta. |
| `EDDY_<LOGIN>_HEARTBEAT` | `double` (cast `datetime`) | Carimbo de vida (timestamp) da instância proprietária para detecção de timeout/crash (> 5s). |

Toda alteração de estado executa `GlobalVariablesFlush()`, garantindo escrita imediata no disco (`gvars.dat`).

### 3.2. Guarda de Instância Única Robusta: Protocolo OWNER + HEARTBEAT (DQ-005)

A implementação inicial da guarda utilizava apenas um timestamp de heartbeat, o que abria o risco de uma segunda instância concorrente, ao falhar em `OnInit()`, invocar `OnDeinit()` e apagar inadvertidamente o heartbeat da instância legítima. Para eliminar definitivamente essa vulnerabilidade de concorrência, a W06 implementou o protocolo **OWNER + HEARTBEAT**:

1. **Identificador Único de Instância (`g_instance_id`):** Gerado dinamicamente em `GenerateInstanceId()` combinando timestamp de alta precisão, contador de ticks e o ID do gráfico (`ChartID()`). O identificador é restrito a valores $< 2^{53}$ ($\approx 9 \times 10^{15}$), garantindo representação exata sem perda de precisão no tipo `double` das Global Variables do MT5.
2. **Posse Atômica por Compare-And-Swap (CAS):** A posse inicial é adquirida via `GlobalVariableSetOnCondition(owner_key, g_instance_id, current_owner)`. Se não houver proprietário prévio ou se o lease estiver expirado (> 5 segundos sem renovação de heartbeat), a nova instância realiza a assunção limpa (*takeover*) atomicamente.
3. **Renovação Exclusiva pelo Proprietário:** O heartbeat é renovado a cada ciclo de `OnTimer()` exclusivamente se `g_is_owner == true` e a chave `EDDY_<LOGIN>_OWNER` contiver o ID da instância corrente.
4. **Liberação Estrita no `OnDeinit()`:** A função `ReleaseInstanceGuard()` verifica rigidamente `if(!g_is_owner) return;`. Uma instância secundária que receba `INIT_FAILED` **não tem permissão** para apagar ou alterar as chaves do proprietário legítimo.
5. **Assunção Pós-Crash (*Takeover* Limpo):** Se uma instância sofrer encerramento anômalo ou travamento do terminal, após 5 segundos o lease expira e uma nova instância pode assumir a conta via CAS atômico.
6. **Detecção de Zumbi e Postura *Fail-Closed*:** Se uma instância que perdeu a posse retornar à execução e detectar que `owner != g_instance_id`, ela entra imediatamente em postura `FAIL-CLOSED` (`g_is_owner = false`, `g_safe_to_operate = false`, estado `EDDY_STATE_INIT`), cessa o timer, **não executa nenhuma ação destrutiva**, não interfere na FSM e **não toca nas variáveis do novo proprietário**.

### 3.3. Cálculo Contábil Exato (W03 / ADR 0002 / ADR 0003)

O resultado financeiro é calculado sem poluição por depósitos ou saques:
* **Resultado Realizado do Dia ($R_{\text{day}}$):** Consulta `HistorySelect(t_day_start, t_now)` e soma `DEAL_PROFIT + DEAL_COMMISSION + DEAL_SWAP + DEAL_FEE` de todas as operações fechadas hoje, excluindo estritamente `DEAL_TYPE_BALANCE` e `DEAL_TYPE_CREDIT`.
* **Resultado Flutuante ($F(t)$):** Obtido via `AccountInfoDouble(ACCOUNT_PROFIT)`, representando o valor líquido instantâneo de todas as posições abertas na conta.
* **Resultado Consolidado ($D(t)$):** $D(t) = R_{\text{day}}(t) + F(t)$.
* **Resultado da Janela ($W_n(t)$):** $W_n(t) = D(t) - B_n$.

### 3.4. Algoritmo de Liquidação Compulsória Desacoplada

Para evitar falhas decorrentes do deslocamento de índices dinâmicos no MT5:
1. Todos os tickets de posições são copiados antecipadamente para o array `ulong pos_tickets[]`.
2. As posições são encerradas individualmente por ticket via `CTrade::PositionClose(ticket, InpDeviationPoints)`.
3. Todos os tickets de ordens pendentes são copiados para `ulong order_tickets[]` e cancelados via `CTrade::OrderDelete(ticket)`.
4. A transição para `BLOCKED` só ocorre se `PositionsTotal() == 0 && OrdersTotal() == 0`. Caso reste qualquer resíduo (ex: mercado fechado ou recusa de liquidez), o sistema permanece retido em `LIQUIDATING`, retentando no ciclo seguinte.

### 3.5. Neutralização Reativa em `BLOCKED` e Calibração de Evidências (DQ-001 / DQ-004)

Em MT5 nativo, ordens manuais disparadas via interface gráfica são enviadas diretamente ao servidor da corretora. O EddyTrader neutraliza intervenções através do hook `OnTradeTransaction`:
* Ao detectar `TRADE_TRANSACTION_DEAL_ADD` em estado de bloqueio, invoca imediatamente `ExecuteGlobalLiquidation()`.
* Ao detectar `TRADE_TRANSACTION_ORDER_ADD`, invoca imediatamente `CancelPendingOrders()`.
* **Invariante Fundamental:** O timestamp de desbloqueio ($t_{\text{unlock}}$) e o ID do evento **não são alterados** nem prorrogados, mantendo a disciplina temporal original.

> [!NOTE]
> **Calibração de Nível de Evidência Técnica (Método C.H.):**
> * **DQ-001 (Neutralização Reativa):** Está **RESOLVIDA ARQUITETURALMENTE E IMPLEMENTADA** no código-fonte do EA e **VALIDADA LOGICAMENTE (FSM)** via suíte automatizada (cenário W06-07). A **VALIDAÇÃO EMPÍRICA SOB CONDIÇÕES REAIS DE MERCADO** (medindo latência física de rede, comportamento sob alta volatilidade e tempo real de resposta do servidor da corretora em conta Demo conectada) permanece catalogada como **PENDENTE**, programada para a Work Package 07 (W07).
> * **DQ-004 (Tratamento de Mercado Fechado):** A retenção estrita em `LIQUIDATING` e retentativa em timer está **IMPLEMENTADA** e **VALIDADA LOGICAMENTE** no cenário W06-05. A **VALIDAÇÃO EMPÍRICA DE RECUSA REAL POR RETCODE** (`TRADE_RETCODE_MARKET_CLOSED` / 10018) emitido por servidor de corretora remota em conta Demo conectada está catalogada como **PENDENTE**, agendada para W07.
> * **ADR 0005:** Preservado no status formal `Proposed` aguardando as evidências empíricas completas da W07.

### 3.6. Tratamento de Virada de Dia (00:00:00)

A função `CheckMidnightRollover()` inspeciona a passagem do relógio oficial:
* Se em `MONITORING`: fecha a janela anterior, reinicia o ciclo contábil em $J_0$ com baseline $B_0 = 0.0$.
* Se em `PROTECTION_TRIGGERED`, `LIQUIDATING`, `BLOCKED` ou `REOPENING`: **o bloqueio não é zerado**. As 4 horas contínuas continuam correndo normalmente até $t \ge t_{\text{unlock}}$.

### 3.7. Postura Fail-Closed na Inicialização

Caso o EA seja carregado em uma janela intradiária $J_n$ ($n \ge 1$), mas a baseline $B_n$ não possa ser recuperada das Global Variables (por corrupção de dados ou exclusão acidental):
* O sistema **recusa o fallback silencioso para $B=0$** (que geraria falso rebloqueio ou cálculo distorcido).
* O robô **permanece retido em `INIT`** com `safe_to_operate = false`, emitindo alertas críticos no diário e mantendo todas as operações bloqueadas.

---

### 4. Resultados da Bateria de Testes Automatizados (W06-01 a W06-20)

A suíte formal de testes foi implementada em [`tests/test_fsm_w06.mq5`](file:///C:/Projetos/eddytrader/tests/test_fsm_w06.mq5) e executada diretamente no ambiente real do MetaTrader 5 Desktop (build 6193) conectado à conta demo `6272676` da corretora ActivTrades.

### 4.1. Resumo da Execução

```text
==================================================================
 Início da Bateria de Validação Formal W06: Cenários W06-01 a 20  
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
  [PASS] W06-16: Guarda Instância Única: Segunda instância rejeitada quando lock ativo e recente
  [PASS] W06-17: Guarda Instância Única: INIT_FAILED em instância secundária não remove lock de outra instância
  [PASS] W06-18: Guarda Instância Única: Apenas a instância dona tem permissão de liberar o lock no OnDeinit
  [PASS] W06-19: Guarda Instância Única: Assunção (takeover) permitida após lease expirado (>5s)
  [PASS] W06-20: Guarda Instância Única: Instância zumbi pós-takeover entra em FAIL-CLOSED sem ações destrutivas
==================================================================
 Resumo da Bateria W06: Total=20 | Aprovados=20 | Falhas=0
==================================================================
```

### 4.2. Matriz de Cobertura dos Cenários de Teste

| ID do Teste | Cenário Avaliado | Comportamento Esperado | Resultado MT5 | Classificação |
| :--- | :--- | :--- | :--- | :---: |
| **W06-01** | Inicialização limpa em $J_0$ | Transita para `MONITORING`, $J_0$, $B_0=0$, operações autorizadas | APROVADO | **PASS** |
| **W06-02** | Perda acumulada dentro do limite ($W > -L$) | Permanece em `MONITORING` sem disparar gatilho | APROVADO | **PASS** |
| **W06-03** | Violação do limite de perda ($W \le -L$) | Transita `MONITORING` $\to$ `PROTECTION_TRIGGERED` $\to$ `LIQUIDATING`, fixa $t_{\text{unlock}}$ | APROVADO | **PASS** |
| **W06-04** | Liquidação completa (resíduo zero) | Transita `LIQUIDATING` $\to$ `BLOCKED` | APROVADO | **PASS** |
| **W06-05** | Falha parcial de liquidação (resíduo $>0$) | Retido estritamente em `LIQUIDATING` | APROVADO | **PASS** |
| **W06-06** | Permanência em bloqueio ($t < t_{\text{unlock}}$) | Permanece em `BLOCKED` | APROVADO | **PASS** |
| **W06-07** | Intervenção manual durante `BLOCKED` | Neutralização reativa executada mantendo $t_{\text{trigger}}$ e $t_{\text{unlock}}$ inalterados | APROVADO | **PASS** |
| **W06-08** | $t \ge t_{\text{unlock}}$ com `safe_to_reopen == false` | Bloqueio retido em `BLOCKED`, postergando reabertura | APROVADO | **PASS** |
| **W06-09** | Reabertura com sucesso ($t \ge t_{\text{unlock}}$ e seguro) | Transita `BLOCKED` $\to$ `REOPENING` $\to$ `MONITORING`, $B_1 = D(t)$, $W_1 = 0$ | APROVADO | **PASS** |
| **W06-10** | Virada de dia às 00:00:00 em `MONITORING` | Reinicia ciclo em $J_0$ com $B_0=0.0$ | APROVADO | **PASS** |
| **W06-11** | Virada de dia às 00:00:00 durante `BLOCKED` | Mantém bloqueio de 4 horas inalterado através da meia-noite | APROVADO | **PASS** |
| **W06-12** | Restart do terminal em $J_0$ | Reconstitui `MONITORING` com $J_0$ e $B_0=0$ | APROVADO | **PASS** |
| **W06-13** | Restart do terminal em $J_n$ ($n \ge 1$) | Reconstitui `MONITORING` com baseline $B_n$ original persistida | APROVADO | **PASS** |
| **W06-14** | Restart do terminal durante `BLOCKED` | Reconstitui `BLOCKED` com $t_{\text{trigger}}$, $t_{\text{unlock}}$ e `event_id` originais | APROVADO | **PASS** |
| **W06-15** | Restart com baseline ausente em $J_n$ ($n \ge 1$) | Postura fail-closed: retido em `INIT`, recusa autorização de negociação | APROVADO | **PASS** |
| **W06-16** | Concorrência: Segunda instância com lock ativo | Rejeitada imediatamente com `INIT_FAILED` | APROVADO | **PASS** |
| **W06-17** | Concorrência: `INIT_FAILED` em instância secundária | `OnDeinit` secundário não remove lock nem heartbeat do dono | APROVADO | **PASS** |
| **W06-18** | Concorrência: Descarregamento no `OnDeinit` | Apenas o legítimo dono (`g_is_owner == true`) remove o lock | APROVADO | **PASS** |
| **W06-19** | Resiliência: Crash do dono e lease expirado (> 5s) | Nova instância assume a conta (*takeover*) via CAS atômico | APROVADO | **PASS** |
| **W06-20** | Resiliência: Instância zumbi acorda pós-takeover | Detecta perda de posse, transita a `FAIL-CLOSED`, sem ações destrutivas | APROVADO | **PASS** |

---

## 5. Evidência de Execução do EA no MetaTrader 5 Strategy Tester

O arquivo compilado [`src/EddyTrader.ex5`](file:///C:/Projetos/eddytrader/src/EddyTrader.ex5) foi submetido à execução direta no motor do Strategy Tester do MT5 Desktop:

* **Ativo e Tempo Gráfico:** `EURUSD, M1`
* **Período Simulado:** 2026.09.01 a 2026.09.02 (24 horas contínuas de pregão)
* **Volume Processado:** 5.689 ticks gerados sobre 1.437 barras de M1
* **Resultado:** 
  * Carga inicial com sucesso (`[EddyTrader] Modo de conta DEMO / TESTE detectado.`);
  * Posse de instância adquirida (`[EddyTrader] Posse de instância adquirida. ID=...`);
  * Inicialização limpa em $J_0$ (`[EddyTrader] Inicialização limpa na conta 6272676. Iniciando J0 com B0=0.0`);
  * Zero erros de execução, zero falhas de memória ou vazamento de handles;
  * Descarga limpa e estruturada ao final do período (`[EddyTrader] OnDeinit: Liberando guarda de instância única...`).

---

## 6. Rastreabilidade com os Requisitos do Sistema

| Requisito / Regra | Título / Descrição | Implementação em `src/EddyTrader.mq5` | Status de Evidência |
| :--- | :--- | :--- | :--- |
| **RF-001** | Monitoramento Contínuo do Flutuante e Realizado | Funções `CalculateRealizedResultToday()`, `CalculateFloatingResult()`, `CalculateConsolidatedResult()`. | Implementado e testado (W06-01 a W06-03). |
| **RF-002** | Encerramento Compulsório Global de Posições | Função `ExecuteGlobalLiquidation()`. | Implementado e testado (W06-04). |
| **RF-003** | Cancelamento Global de Ordens Pendentes | Função `CancelPendingOrders()`. | Implementado e testado (W06-04). |
| **RF-004** | Bloqueio Temporal Ininterrupto de 4 Horas | Cálculo $t_{\text{unlock}} = t_{\text{trigger}} + 14.400$ s e permanência em `EDDY_STATE_BLOCKED`. | Implementado e testado (W06-06, W06-08, W06-11). |
| **RF-005** | Reabertura Controlada e Nova Baseline | Transição `EDDY_STATE_REOPENING` com $B_{n+1} = D(t_{\text{reopen}})$ e $W_{n+1} = 0$. | Implementado e testado (W06-09). |
| **RF-006** | Neutralização Reativa de Intervenção Manual | Hook `OnTradeTransaction` interceptando `DEAL_ADD` e `ORDER_ADD` durante bloqueio. | Implementado; testado logicamente (W06-07); validação empírica em conta Demo pendente (W07). |
| **RF-007** | Reconstituição de Estado Determinística pós-Restart | Funções `LoadState()` e `PersistState()` com chaves `EDDY_<LOGIN>_*` em Global Variables. | Implementado e testado (W06-12 a W06-15). |
| **RNF-001** | Execução 100% MQL5 Nativo Puro | Desenvolvido sem DLLs ou ferramentas externas; compilado no MetaEditor 64 (0 erros, 0 warnings). | Aprovado na compilação. |
| **RNF-002** | Frequência de Avaliação Sub-Segundo | `EventSetMillisecondTimer(InpTimerIntervalMs)` operando a 500 ms. | Implementado e testado. |
| **RNF-003** | Postura Fail-Closed na Indeterminação | Retenção mandatória em `EDDY_STATE_INIT` perante inconsistência em $J_n$ ($n \ge 1$). | Implementado e testado (W06-15). |
| **GAP-005** | Persistência e Reconstrução pós-Restart | Resolvido e validado com sucesso via Terminal Global Variables e `GlobalVariablesFlush()`. | Validado formalmente (20/20 PASS). |
| **DQ-001** | Mecanismo de Bloqueio Operacional MT5 | Neutralização reativa via `OnTradeTransaction` emitindo `PositionClose` / `OrderDelete`. | Implementado; validado logicamente; validação empírica de latência de rede pendente (W07). |
| **DQ-002** | Tratamento de Contas Netting vs. Hedging | Liquidação universal baseada estritamente em `POSITION_TICKET`. | Implementado e aderente à documentação oficial MT5. |
| **DQ-003** | Slippage e Desvio Máximo em Liquidação | Parametrização via `InpDeviationPoints` (default 10 pontos). | Implementado. |
| **DQ-004** | Tratamento de Ativos com Mercado Fechado | Retenção estrita em `LIQUIDATING` e retentativa em timer até liquidação total. | Implementado; validado logicamente (W06-05); validação empírica de retcode de mercado fechado pendente (W07). |
| **DQ-005** | Prevenção de Múltiplas Instâncias do EA | Protocolo `OWNER + HEARTBEAT` com CAS atômico, takeover limpo e isolamento no `OnDeinit`. | Implementado e validado formalmente (W06-16 a W06-20). |
| **ADR 0005** | Garantias Técnicas MT5 e Estratégia de Recuperação | Persistência em Global Variables e neutralização reativa. | Status formal `Proposed`, aguardando validação empírica com corretora (W07). |

---

## 7. Política de Gestão de Artefatos Compilados (`.ex5` e `.log`)

Durante as atividades de compilação com o MetaEditor e execução via linha de comando no MetaTrader 5, arquivos binários compilados (`.ex5`) e arquivos de log de execução (`.log`) são gerados localmente nas pastas `src/` e `tests/`.

### 7.1. Diretriz de Versionamento (Git)

* **Artefatos Efêmeros:** Arquivos com extensão `.ex5` e `.log` representam resultados temporários de compilação e teste, sendo dependentes da versão específica do compilador e do ambiente operacional da máquina hospedeira.
* **Recomendação Normativa:** Recomenda-se formalmente que tais extensões sejam adicionadas ao arquivo `.gitignore` do repositório, garantindo que apenas o código-fonte puramente reprodutível (`.mq5`, `.mqh`), a documentação normativa (`.md`) e os scripts de automação (`.ps1`) permaneçam sob controle de versão.
* **Reprodutibilidade Garantida:** Qualquer desenvolvedor ou ambiente CI/CD pode regerar os binários e logs a qualquer momento através dos scripts normativos [`scripts/compile_eddy.ps1`](file:///C:/Projetos/eddytrader/scripts/compile_eddy.ps1) e [`scripts/run_test_fsm.ps1`](file:///C:/Projetos/eddytrader/scripts/run_test_fsm.ps1).
