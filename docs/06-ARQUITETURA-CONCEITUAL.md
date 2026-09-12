# 06 — Arquitetura Conceitual do EddyTrader

Este documento define a arquitetura conceitual e os blocos de responsabilidade do **EddyTrader**, atualizados com as deliberações de produto da **W02**. Este documento é puramente conceitual e normativo: **não define nem antecipa implementações de código MQL5 executável**.

---

## 1. Princípios Arquiteturais

A arquitetura conceitual do EddyTrader orienta-se por quatro diretrizes:

1. **Responsabilidade Única e Mínima:** Cada módulo conceitual possui uma atribuição estrita e delimitada.
2. **Determinismo e Isolamento:** Todas as transições operacionais ocorrem através de uma Máquina de Estados Finita (FSM) explícita.
3. **Tempo Soberano do Servidor:** Todos os cálculos e janelas temporais operam com base exclusiva no relógio do servidor de negociação da corretora.
4. **Reconstrução Determinística sobre Persistência:** O sistema prioriza a inferência e reconstrução do estado operacional a partir do histórico nativo da conta, evitando arquivos duplicados e estados inconsistentes.

---

## 2. Decomposição Conceitual de Responsabilidades

O sistema estrutura-se conceitualmente em sete módulos funcionais:

```mermaid
graph TD
    subgraph "Camada de Percepção Temporal e Contábil"
        A["Leitor de Tempo e Estado da Conta (Server Time & Account State Reader)"]
        B["Avaliador de Perda Operacional e Janelas (Risk & Window Evaluator)"]
    end

    subgraph "Camada de Controle e Decisão"
        C["Máquina de Estados Finita (FSM)"]
        D["Controlador de Bloqueio e Janelas (Block & Schedule Controller)"]
    end

    subgraph "Camada de Execução Operacional (Escopo Global)"
        E["Motor de Liquidação Compulsória (Account Liquidation Engine)"]
        F["Motor de Cancelamento de Ordens (Order Cancellation Engine)"]
    end

    subgraph "Camada de Comunicação e Auditoria"
        G["Apresentador Visual no Gráfico (Visual HUD)"]
        H["Registrador de Auditoria em Log (Journal Logger)"]
    end

    A --> B
    B --> C
    C --> D
    C --> E
    C --> F
    C --> G
    C --> H
    D --> E
    D --> F
```

### 2.1. Leitor de Tempo e Estado da Conta (*Server Time & Account Reader*)
* **Responsabilidade:** Consultar o relógio do servidor de negociação, varrer o histórico diário (`00:00:00` às `23:59:59` do servidor), filtrar negócios de trading (ignorando depósitos/saques) e ler o flutuante líquido atual.

### 2.2. Avaliador de Perda Operacional e Janelas (*Risk & Window Evaluator*)
* **Responsabilidade:** Calcular o resultado diário consolidado $D(t) = R_{\text{day}}(t) + F(t)$ somando realizado líquido (com comissões e swaps) e flutuante atual, e calcular o resultado da janela ativa $W_n(t) = D(t) - B_n$ (com $B_0 = 0$ e $B_n = D(t_{\text{reopen}, n})$ para $n \ge 1$), confrontando com o limite $L$ segundo [10-ESPECIFICACAO-MATEMATICA.md](file:///C:/Projetos/eddytrader/docs/10-ESPECIFICACAO-MATEMATICA.md).

### 2.3. Máquina de Estados Finita (*FSM - Finite State Machine*)
* **Responsabilidade:** Controlar o ciclo de vida da proteção, governando as transições entre vigilância, contenção, bloqueio programado e liberação.

### 2.4. Motor de Liquidação Compulsória (*Account Liquidation Engine*)
* **Responsabilidade:** Emitir ordens de fechamento a mercado para 100% das posições abertas na conta (todos os símbolos e robôs), isolando falhas individuais sem interromper o processamento das demais.

### 2.5. Motor de Cancelamento de Ordens (*Order Cancellation Engine*)
* **Responsabilidade:** Emitir requisições de remoção para 100% das ordens pendentes existentes na conta.

### 2.6. Controlador de Bloqueio e Janelas (*Block & Schedule Controller*)
* **Responsabilidade:** Gerenciar a janela temporal de bloqueio de 4 horas a partir do acionamento ($t_{\text{unlock}} = t_{\text{trigger}} + 4\text{h}$), retendo o bloqueio após a meia-noite caso a janela atravesse a virada de dia e administrando o gatilho de reabertura de nova janela em $t_{\text{reopen}} \ge t_{\text{unlock}}$.

### 2.7. Apresentador Visual e Logger (*Visual HUD & Journal Logger*)
* **Responsabilidade:** Exibir no gráfico informações claras de status (relógio do servidor, limite, perdas, instante do bloqueio e previsão de liberação após 4h) e auditar eventos com carimbo de tempo do servidor no Diário do MT5.

---

## 3. Máquina de Estados Conceitual

O comportamento operacional do EddyTrader é governado por seis estados conceituais normativos formalizados integralmente em [11 — Máquina de Estados](file:///C:/Projetos/eddytrader/docs/11-MAQUINA-DE-ESTADOS.md):

```mermaid
stateDiagram-v2
    [*] --> INIT : Inicialização / Restart
    
    INIT --> MONITORING : Estado reconstruído limpo (J0/B0 ou Jn/Bn restaurados)
    INIT --> BLOCKED : Bloqueio ativo (t < t_unlock OU safe_to_reopen == false)
    INIT --> REOPENING : Proteção vencida (t >= t_unlock, resíduo 0 e safe_to_reopen)
    INIT --> LIQUIDATING : Exposição residual a neutralizar (precedência)

    MONITORING --> PROTECTION_TRIGGERED : Perda da janela W_n(t) <= -L
    
    PROTECTION_TRIGGERED --> LIQUIDATING : Registrar t_trigger e t_unlock
    
    LIQUIDATING --> LIQUIDATING : Retentativa / Exposição residual
    LIQUIDATING --> BLOCKED : Exposição 100% neutralizada (resíduo zero)
    
    BLOCKED --> BLOCKED : t < t_unlock OU safe_to_reopen == false
    BLOCKED --> REOPENING : t >= t_unlock AND safe_to_reopen == true

    REOPENING --> MONITORING : Registrar baseline B_n e zerar janela
```

### 3.1. Transições Críticas Detalhadas

1. **`INIT` $\to$ `MONITORING` / `BLOCKED` / `REOPENING` / `LIQUIDATING`:** Ponto de entrada obrigatório. O sistema inspeciona registros e histórico sob ordem hierárquica estrita:
   * Se dados insuficientes ou baseline intradiária irrecuperável $\implies$ retém em `INIT` (`safe_to_operate = false`, postura *fail-closed* sem fallback para zero);
   * Se houver exposição residual que deveria ter sido eliminada $\implies$ transita para `LIQUIDATING` (precedência absoluta de contenção);
   * Se houver proteção ativa com $t < t_{\text{unlock}}$ e resíduo zero $\implies$ transita para `BLOCKED` preservando $t_{\text{trigger}}$ e $t_{\text{unlock}}$;
   * Se houver proteção pendente com $t \ge t_{\text{unlock}}$ e resíduo zero $\implies$ transita para `BLOCKED` se `safe_to_reopen == false`, ou diretamente para `REOPENING` se `safe_to_reopen == true` (sendo terminantemente proibido pular para `MONITORING`);
   * Se estado for nominal sem proteção pendente $\implies$ transita para `MONITORING` (estabelecendo $B_0 \gets 0$ se primeira janela ou restaurando $B_n$ intradiário).
2. **`MONITORING` $\to$ `PROTECTION_TRIGGERED` $\to$ `LIQUIDATING`:** Disparada imediatamente quando $W_n(t) \le -L$. Congela o contexto, registra $t_{\text{trigger}}$, calcula $t_{\text{unlock}} = t_{\text{trigger}} + 14.400\text{s}$ e comanda a liquidação compulsória integral.
3. **`LIQUIDATING` $\to$ `LIQUIDATING` / `BLOCKED`:** Enquanto existir qualquer posição aberta ou ordem pendente a ser neutralizada, o sistema **permanece estritamente em `LIQUIDATING`**, persistindo nas tentativas de encerramento. A transição para `BLOCKED` ocorre única e exclusivamente após a neutralização de 100% da exposição (resíduo zero). O relógio de 4 horas ($t_{\text{unlock}}$) corre continuamente durante `LIQUIDATING`.
4. **`BLOCKED` $\to$ `REOPENING`:** Ocorre estritamente quando duas condições são simultaneamente satisfeitas: decurso das 4 horas contínuas ($t \ge t_{\text{unlock}}$) e segurança operacional atestada (`safe_to_reopen == true`). A virada de `00:00:00` não cancela o bloqueio.
5. **`REOPENING` $\to$ `MONITORING`:** Encerra formalmente o evento de bloqueio em $t_{\text{reopen}} \ge t_{\text{unlock}}$, estabelece a baseline $B_{n+1} = D(t_{\text{reopen}})$ garantindo $W_{n+1}(t_{\text{reopen}}) = 0$, e reabre o monitoramento contra novas perdas na nova janela.

---

## 4. Reconstrução Determinística vs. Persistência em Disco

A decisão arquitetural de produto para o MVP ([D12](file:///C:/Projetos/eddytrader/docs/adr/0001-regras-temporais-e-janelas-de-protecao.md)) estabelece:

* **Prioridade Absoluta:** O EA deve reconstruir seu estado a partir dos registros contábeis nativos da conta e do histórico do terminal MT5 sempre que possível.
* **Racional (KISS / YAGNI):** Evitar arquivos proprietários duplicados no disco reduz pontos de falha, corrupção de dados e complexidade operacional.
* **Delimitação da W04:** A especificação normativa da FSM formalizou com exatidão o conjunto mínimo de dados conceituais necessários para a recuperação determinística: $\mathbf{D}_{\text{min\_recovery}} = \{ \text{current\_state}, \text{protection\_event\_id}, J_n, B_n, t_{\text{trigger}}, t_{\text{unlock}} \}$. A validação prática sobre a suficiência dos dados nativos do MT5 vs. necessidade de persistência leve auxiliar permanece encaminhada para o Spike Técnico da W05 ([GAP-005](file:///C:/Projetos/eddytrader/docs/08-RISCOS-E-QUESTOES-ABERTAS.md#gap-005--persistência-e-reconstrução-de-estado-após-reinicialização) e [ADR 0004](file:///C:/Projetos/eddytrader/docs/adr/0004-maquina-de-estados-e-recuperacao.md)).

---

## 5. Escopo da Conta e Restrição de Instância Única

* **Escopo Global da Conta (D13):** O EddyTrader não atua isolado no ativo do gráfico; sua governança se estende a todas as posições e ordens da conta de negociação.
* **Instância Única por Conta (D14):** O sistema opera sob o pressuposto de uma única instância por conta. Mecanismos de detecção ou restrição de instâncias concorrentes serão especificados em W04/W05.

---

## 6. A Questão do Bloqueio no MT5 (Encaminhamento para Spike Técnico)

Conforme mantido no catálogo de questões abertas ([DQ-001](file:///C:/Projetos/eddytrader/docs/08-RISCOS-E-QUESTOES-ABERTAS.md#dq-001--mecanismo-de-bloqueio-operacional-no-mt5)):
* O requisito de produto determina que novas operações não permaneçam ativas durante o bloqueio.
* Em MQL5 nativo puro, ordens manuais disparadas diretamente no terminal são tratadas por **neutralização reativa imediata**.
* A comprovação da latência, dos eventos de negociação (`OnTradeTransaction`) e do comportamento prático será executada no Spike Técnico laboratorial da **W05**.

---

## 7. Rastreabilidade Documental

* Requisitos Associados: [03 — Requisitos](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md)
* Casos de Uso: [04 — Casos de Uso](file:///C:/Projetos/eddytrader/docs/04-CASOS-DE-USO.md)
* Regras Normativas: [05 — Regras de Negócio](file:///C:/Projetos/eddytrader/docs/05-REGRAS-DE-NEGOCIO.md)
* Especificação Matemática: [10 — Especificação Matemática](file:///C:/Projetos/eddytrader/docs/10-ESPECIFICACAO-MATEMATICA.md)
* Máquina de Estados Finita: [11 — Máquina de Estados](file:///C:/Projetos/eddytrader/docs/11-MAQUINA-DE-ESTADOS.md)
* Decisões Arquiteturais: [ADR 0001](file:///C:/Projetos/eddytrader/docs/adr/0001-regras-temporais-e-janelas-de-protecao.md), [ADR 0002](file:///C:/Projetos/eddytrader/docs/adr/0002-composicao-da-perda-operacional.md), [ADR 0003](file:///C:/Projetos/eddytrader/docs/adr/0003-modelo-matematico-de-janelas-e-baseline.md) e [ADR 0004](file:///C:/Projetos/eddytrader/docs/adr/0004-maquina-de-estados-e-recuperacao.md)
* Planejamento Incremental: [09 — Roadmap](file:///C:/Projetos/eddytrader/docs/09-ROADMAP.md)
