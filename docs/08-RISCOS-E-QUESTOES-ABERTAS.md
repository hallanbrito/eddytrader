# 08 — Riscos Técnicos, Lacunas e Questões Abertas

Este documento cataloga de forma explícita e rastreável todas as ambiguidades conceituais, riscos técnicos e decisões de projeto do **EddyTrader**.

> **Diretriz C.H.:** As decisões de produto formalizadas na W02 estão registradas com status `RESOLVIDA` e referenciam seus respectivos ADRs. Questões técnicas que dependem de evidência prática na plataforma MT5 ou especificação detalhada permanecem explicitamente marcadas com o estágio correspondente.

---

## 1. Matriz de Lacunas de Especificação (GAPs)

| ID | Título | Status | Decisão / Encaminhamento | Referência |
| :--- | :--- | :--- | :--- | :--- |
| **GAP-001** | Fuso Horário e Marco Inicial do "Dia" | **RESOLVIDA** | Referência temporal oficial é exclusivamente o **horário do servidor de negociação da conta**. O dia operacional inicia às `00:00:00` e encerra às `23:59:59` do servidor. | [ADR 0001](file:///C:/Projetos/eddytrader/docs/adr/0001-regras-temporais-e-janelas-de-protecao.md) / Decisão D01 e D02 |
| **GAP-002** | Composição Contábil do Resultado Relevante | **RESOLVIDA** | Resultado = Realizado do Dia + Flutuante Atual. Custos de trading (comissões e swaps) são obrigatoriamente incluídos. Movimentações de capital (depósitos, saques e créditos) são estritamente excluídas. | [ADR 0002](file:///C:/Projetos/eddytrader/docs/adr/0002-composicao-da-perda-operacional.md) / Decisão D03, D04 e D05 |
| **GAP-003** | Consistência Temporal do Bloqueio e Virada de Dia | **RESOLVIDA (ATUALIZADA)** | Duração relativa contênua de **4 horas** a partir do disparo ($t_{\text{unlock}} = t_{\text{bloqueio}} + 4\text{h}$). A virada de `00:00:00` não encerra nem afeta a duração. Bloqueio ativo prevalece até completar 4 horas mesmo com início de novo dia. Desbloqueio encerra evento e inicia nova janela operacional via baseline. *(Interpretação anterior de horário absoluto substituída por esclarecimento do PO)*. | [ADR 0001](file:///C:/Projetos/eddytrader/docs/adr/0001-regras-temporais-e-janelas-de-protecao.md) / Decisões D07, D08, D09, D10 e D11 |
| **GAP-004** | Escopo de Atuação na Conta (Símbolos e Magics) | **RESOLVIDA** | Escopo global da conta: todas as posições, todas as ordens pendentes, todos os símbolos, manuais ou de outros robôs. Sem filtros para o MVP. | Decisão D13 / [RN-004](file:///C:/Projetos/eddytrader/docs/05-REGRAS-DE-NEGOCIO.md#rn-004) / [RN-005](file:///C:/Projetos/eddytrader/docs/05-REGRAS-DE-NEGOCIO.md#rn-005) |
| **GAP-005** | Persistência vs. Reconstrução de Estado após Restart | **RESOLVIDA E INTEGRADA (W06)** | Mecanismo de persistência de $\mathbf{D}_{\text{min\_recovery}}$ implementado e validado em MT5 via **Global Variables do Terminal** (`GlobalVariableSet` / `GlobalVariablesFlush`) com chaves `EDDY_<LOGIN>_*` e recuperação determinística no `OnInit()`. Validado contra 20 cenários de teste automatizados com 100% de aprovação (incluindo guarda OWNER+HEARTBEAT e postura Fail-Closed). | [13-IMPLEMENTACAO-MVP-W06.md](file:///C:/Projetos/eddytrader/docs/13-IMPLEMENTACAO-MVP-W06.md) / [ADR 0005](file:///C:/Projetos/eddytrader/docs/adr/0005-garantias-tecnicas-mt5-e-estrategia-de-recuperacao.md) |
| **GAP-006** | Especificação Matemática da Baseline de Reabertura | **RESOLVIDA (W03)** | Modelo algébrico formalizado: $B_0 = 0$ para a primeira janela do dia; $B_n = D(t_{\text{reopen}, n})$ para janelas subsequentes pós-desbloqueio. O resultado da janela é $W_n(t) = D(t) - B_n$, prevenindo deterministicamente o falso rebloqueio imediato. | [10-ESPECIFICACAO-MATEMATICA.md](file:///C:/Projetos/eddytrader/docs/10-ESPECIFICACAO-MATEMATICA.md) / [ADR 0003](file:///C:/Projetos/eddytrader/docs/adr/0003-modelo-matematico-de-janelas-e-baseline.md) |

---

## 2. Detalhamento dos GAPs

### GAP-001 — Fuso Horário e Marco Inicial do "Dia"
* **Status:** **RESOLVIDA (W02)**
* **Decisão:** O EddyTrader utiliza o horário do servidor de negociação (`00:00:00` às `23:59:59`).
* **Racional:** Independência do relógio local do usuário e alinhamento com os registros contábeis da corretora.
* **Documento Vinculado:** [ADR 0001](file:///C:/Projetos/eddytrader/docs/adr/0001-regras-temporais-e-janelas-de-protecao.md).

### GAP-002 — Composição Contábil do Resultado Relevante
* **Status:** **RESOLVIDA (W02)**
* **Decisão:** $\text{Resultado Relevante} = \text{Realizado do Dia} + \text{Flutuante Atual}$. Custos de comissão e swap são incluídos. Saques e depósitos são desconsiderados. Posições antigas mantidas abertas contribuem com seu flutuante no novo dia.
* **Racional:** Refletir a variação econômica real líquida exclusiva das operações de trading.
* **Documento Vinculado:** [ADR 0002](file:///C:/Projetos/eddytrader/docs/adr/0002-composicao-da-perda-operacional.md).

### GAP-003 — Consistência Temporal da Duração do Bloqueio e Virada de Dia
* **Status:** **RESOLVIDA (W02 — Atualizada por esclarecimento do PO)**
* **Histórico e Rastreabilidade:** A especificação preliminar continha o exemplo `16:00`, que fora interpretado como um horário fixo diário de liberação. O Product Owner formalizou que a intenção real de produto é um **bloqueio contínuo de 4 horas a contar do momento em que a perda atinge o limite**. A interpretação anterior de horário absoluto diário (D07 anterior, D08/D10 anteriores) foi formalmente revogada e substituída (*superseded*).
* **Decisão Vigente:**
  1. **Duração Relativa:** O bloqueio dura exatamente 4 horas contadas a partir do instante do disparo no horário do servidor ($t_{\text{unlock}} = t_{\text{bloqueio}} + 4\text{h}$).
  2. **Virada de Dia:** A virada de `00:00:00` não interfere na duração. Se o bloqueio for acionado às 23:30, a liberação ocorre às 03:30 do dia seguinte.
  3. **Novo Dia Durante Bloqueio:** O início do novo dia operacional não desativa o bloqueio ativo; ele permanece ativo até completar as 4 horas.
  4. **Liberação:** Ao completar a janela de 4 horas ($t \ge t_{\text{bloqueio}} + 4\text{h}$), o bloqueio é finalizado e o sistema torna-se elegível à liberação.
  5. **Baseline Pós-Liberação:** O desbloqueio encerra o evento e inicia uma nova janela operacional via `baseline_de_reabertura` (D09 preservada), prevenindo rebloqueio imediato por perdas históricas do dia.
* **Racional:** Garantir proteção uniforme e determinística de 4 horas para qualquer instante de violação, preservando a coerência mesmo na transição de dias.
* **Documento Vinculado:** [ADR 0001](file:///C:/Projetos/eddytrader/docs/adr/0001-regras-temporais-e-janelas-de-protecao.md).

### GAP-004 — Escopo de Atuação na Conta (Símbolos e Magic Numbers)
* **Status:** **RESOLVIDA (W02)**
* **Decisão:** Atuação irrestrita sobre a conta inteira. Não há filtros por símbolo, Magic Number ou autor da ordem.
* **Racional:** A salvaguarda de perda diária visa à sobrevivência da conta como um todo.

### GAP-005 — Persistência e Reconstrução de Estado após Reinicialização
* **Status:** **RESOLVIDA E INTEGRADA (W06)**
* **Resolução Técnica e Validação (W06):** O conjunto conceitual mínimo $\mathbf{D}_{\text{min\_recovery}} = \{ \text{current\_state}, \text{protection\_event\_id}, J_n, B_n, t_{\text{trigger}}, t_{\text{unlock}}, \text{day} \}$ foi implementado no EA `src/EddyTrader.mq5` via **Global Variables do Terminal MT5** (`GlobalVariableSet` / `GlobalVariablesFlush`) com chave prefixada por login (`EDDY_<LOGIN>_*`). A recuperação determinística foi validada através de 20 cenários formais em MT5, com 100% de aprovação, incluindo a guarda robusta OWNER+HEARTBEAT e a postura Fail-Closed para baselines ausentes em $J_n$ ($n \ge 1$).
* **Documentos Vinculados:** [13-IMPLEMENTACAO-MVP-W06.md](file:///C:/Projetos/eddytrader/docs/13-IMPLEMENTACAO-MVP-W06.md), [12-SPIKE-TECNICO-MT5.md](file:///C:/Projetos/eddytrader/docs/12-SPIKE-TECNICO-MT5.md), [ADR 0005](file:///C:/Projetos/eddytrader/docs/adr/0005-garantias-tecnicas-mt5-e-estrategia-de-recuperacao.md), [11-MAQUINA-DE-ESTADOS.md](file:///C:/Projetos/eddytrader/docs/11-MAQUINA-DE-ESTADOS.md).

### GAP-006 — Especificação Matemática da Baseline de Reabertura
* **Status:** **RESOLVIDA (W03)**
* **Decisão:** A métrica operacional é segmentada em janelas sequenciais $J_n$. A baseline é definida como $B_0 = 0$ para a primeira janela do dia e $B_n = D(t_{\text{reopen}, n})$ para as janelas abertas após o encerramento do bloqueio de 4 horas. O resultado da janela é $W_n(t) = D(t) - B_n$ e a proteção dispara compulsoriamente em $W_n(t) \le -L$.
* **Racional:** Elimina matematicamente a possibilidade de falso rebloqueio no mesmo tick da liberação ($W_n(t_{\text{reopen}}) = 0 > -L$), ao mesmo tempo em que preserva integralmente o histórico contábil da corretora.
* **Documentos Vinculados:** [10-ESPECIFICACAO-MATEMATICA.md](file:///C:/Projetos/eddytrader/docs/10-ESPECIFICACAO-MATEMATICA.md), [ADR 0003](file:///C:/Projetos/eddytrader/docs/adr/0003-modelo-matematico-de-janelas-e-baseline.md).

---

## 3. Decisões de Projeto e Plataforma (DQs)

| ID | Título | Status | Escopo / Encaminhamento |
| :--- | :--- | :--- | :--- |
| **DQ-001** | Mecanismo Técnico de Bloqueio Operacional no MT5 | **RESOLVIDA ARQUITETURALMENTE E IMPLEMENTADA (W06) / VALIDAÇÃO EMPÍRICA DE MERCADO PENDENTE (W07)** | Comprovado documentalmente que o MT5 não possui interceptação prévia de ordens manuais. A garantia técnica normativa é a **neutralização reativa** via `OnTradeTransaction` emitindo `PositionClose` / `OrderDelete`. Arquitetura implementada e validada logicamente (W06-07). Validação empírica sob tráfego real de rede e latência de corretora agendada para W07. |
| **DQ-002** | Tratamento de Contas Netting vs. Hedging | **RESOLVIDA DOCUMENTALMENTE (W05) / IMPLEMENTADA (W06)** | Definida e implementada a liquidação universal estritamente por **`POSITION_TICKET`**, eliminando ambiguidade e garantindo operação 100% idêntica e compatível tanto em Netting quanto em Hedging. |
| **DQ-003** | Política de Slippage e Deviation em Fechamento de Emergência | **RESOLVIDA (W06)** | Parametrização implementada via input normativo `InpDeviationPoints` (default 10 pontos) passado a todas as chamadas de fechamento compulsório em `CTrade::PositionClose(ticket, InpDeviationPoints)`. |
| **DQ-004** | Tratamento de Ativos com Mercado Fechado | **RESOLVIDA ARQUITETURALMENTE E IMPLEMENTADA (W06) / VALIDAÇÃO EMPÍRICA DE MERCADO PENDENTE (W07)** | Tratamento implementado: retenção estrita em `LIQUIDATING` enquanto `PositionsTotal() > 0 || OrdersTotal() > 0`, com retentativas contínuas a cada pulso de timer (500 ms) via `OnTimer()`. Validado logicamente no cenário W06-05. Validação empírica de retcode de mercado fechado (ex: 10018) de corretora conectada agendada para W07. |
| **DQ-005** | Detecção e Prevenção de Múltiplas Instâncias do EA | **RESOLVIDA E IMPLEMENTADA (W06 — CORREÇÃO CIRÚRGICA)** | Guarda de instância única por conta com propriedade explícita (`EDDY_<LOGIN>_OWNER` + `EDDY_<LOGIN>_HEARTBEAT`). Posse atômica via CAS (`GlobalVariableSetOnCondition`), renovação exclusiva pelo dono, liberação no `OnDeinit` apenas pelo proprietário verificado (`if(!g_is_owner) return;`), assunção limpa (takeover) após lease expirado (> 5s) e postura Fail-Closed imediata para instâncias zumbis. Validada pelos testes W06-16 a W06-20. |

---

## 4. Riscos Técnicos e Operacionais (RISKs)

| ID | Risco Identificado | Severidade | Probabilidade | Mitigação Proposta |
| :--- | :--- | :--- | :--- | :--- |
| **RISK-001** | **Derrapagem de Execução (Slippage):** A perda final consolidada ultrapassar o limite configurado devido à latência da corretora e slippage em ordens a mercado em momento de alta volatilidade. | Alta | Alta | Deixar formalizado que o limite é um gatilho de disparo de emergência, sujeito à liquidez e preços reais da contraparte da corretora. |
| **RISK-002** | **Falsa Sensação de Bloqueio Preventivo Físico:** O operador assumir que o EA desabilita o clique manual do MT5 antes do envio (impossível sem DLL). | Alta | Média | Esclarecer na documentação normativa que o bloqueio nativo atua por neutralização reativa após recebimento do evento transacional, estando a latência real sujeita às condições de rede e do servidor. |
| **RISK-003** | **Divergência de Fuso Horário:** Operador interpretar o horário previsto de desbloqueio como horário local em vez do horário do servidor. | Média | Média | Mitigado pela formalização em D01/ADR 0001 (referência oficial é o horário do servidor). O EA deve exibir visualmente o horário atual do servidor e o instante exato de liberação no relógio do servidor ($t_{\text{bloqueio}} + 4\text{h}$). |
| **RISK-004** | **Degradação de Performance do MT5:** Loop de monitoramento excessivamente agressivo consumir alta CPU. | Média | Baixa | Utilizar arquitetura dirigida por eventos (`OnTick` e timer controlado de 500ms a 1s), evitando laços de espera ocupada. |
| **RISK-005** | **Perda de Estado em Falha Elétrica / Reinicialização:** Terminal reiniciado durante o período de 4 horas esquecer restrições se não reconstruir estado. | Média | Média | Mitigado pelo protocolo normativo de recuperação da FSM (`Restart -> INIT`) e identificação de $\mathbf{D}_{\text{min\_recovery}}$ em W04. |
| **RISK-006** | **Múltiplas Instâncias Concorrentes:** Operador anexar o EddyTrader a mais de um gráfico da mesma conta, gerando concorrência e ordens duplicadas de fechamento. | Alta | Média | Requisito formal de instância única por conta (D14, RN-011, FSM-INV-001); validar mecanismo técnico de bloqueio de concorrência na W05. |
| **RISK-007** | **Desconexão do Terminal / Falha de Rede com o Servidor:** Terminal perder conexão durante processo de fechamento de emergência. | Alta | Baixa | Registrar status de tentativa pendente e reexecutar a liquidação no primeiro instante de reconexão detectado. |

---

## 5. Rastreabilidade Documental

* Origem dos Requisitos: [03 — Requisitos](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md)
* Regras Normativas: [05 — Regras de Negócio](file:///C:/Projetos/eddytrader/docs/05-REGRAS-DE-NEGOCIO.md)
* Especificação Matemática: [10 — Especificação Matemática](file:///C:/Projetos/eddytrader/docs/10-ESPECIFICACAO-MATEMATICA.md)
* Máquina de Estados Finita: [11 — Máquina de Estados](file:///C:/Projetos/eddytrader/docs/11-MAQUINA-DE-ESTADOS.md)
* Decisões Arquiteturais: [ADR 0001](file:///C:/Projetos/eddytrader/docs/adr/0001-regras-temporais-e-janelas-de-protecao.md), [ADR 0002](file:///C:/Projetos/eddytrader/docs/adr/0002-composicao-da-perda-operacional.md), [ADR 0003](file:///C:/Projetos/eddytrader/docs/adr/0003-modelo-matematico-de-janelas-e-baseline.md) e [ADR 0004](file:///C:/Projetos/eddytrader/docs/adr/0004-maquina-de-estados-e-recuperacao.md)
* Alinhamento no Cronograma: [09 — Roadmap](file:///C:/Projetos/eddytrader/docs/09-ROADMAP.md)
