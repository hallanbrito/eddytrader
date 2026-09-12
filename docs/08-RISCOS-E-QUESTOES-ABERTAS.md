# 08 — Riscos Técnicos, Lacunas e Questões Abertas

Este documento cataloga de forma explícita e rastreável todas as ambiguidades conceituais, riscos técnicos e decisões de projeto do **EddyTrader**.

> **Diretriz C.H.:** As decisões de produto formalizadas na W02 estão registradas com status `RESOLVIDA` e referenciam seus respectivos ADRs. Questões técnicas que dependem de evidência prática na plataforma MT5 ou especificação detalhada permanecem explicitamente marcadas com o estágio correspondente.

---

## 1. Matriz de Lacunas de Especificação (GAPs)

| ID | Título | Status | Decisão / Encaminhamento | Referência |
| :--- | :--- | :--- | :--- | :--- |
| **GAP-001** | Fuso Horário e Marco Inicial do "Dia" | **RESOLVIDA** | Referência temporal oficial é exclusivamente o **horário do servidor de negociação da conta**. O dia operacional inicia às `00:00:00` e encerra às `23:59:59` do servidor. | [ADR 0001](file:///C:/Projetos/eddytrader/docs/adr/0001-regras-temporais-e-janelas-de-protecao.md) / Decisão D01 e D02 |
| **GAP-002** | Composição Contábil do Resultado Relevante | **RESOLVIDA** | Resultado = Realizado do Dia + Flutuante Atual. Custos de trading (comissões e swaps) são obrigatoriamente incluídos. Movimentações de capital (depósitos, saques e créditos) são estritamente excluídas. | [ADR 0002](file:///C:/Projetos/eddytrader/docs/adr/0002-composicao-da-perda-operacional.md) / Decisão D03, D04 e D05 |
| **GAP-003** | Consistência Temporal do Bloqueio e Virada de Dia | **RESOLVIDA (ATUALIZADA)** | Duração relativa contínua de **4 horas** a partir do disparo ($t_{\text{unlock}} = t_{\text{bloqueio}} + 4\text{h}$). A virada de `00:00:00` não encerra nem afeta a duração. Bloqueio ativo prevalece até completar 4 horas mesmo com início de novo dia. Desbloqueio encerra evento e inicia nova janela operacional via baseline. *(Interpretação anterior de horário absoluto substituída por esclarecimento do PO)*. | [ADR 0001](file:///C:/Projetos/eddytrader/docs/adr/0001-regras-temporais-e-janelas-de-protecao.md) / Decisões D07, D08, D09, D10 e D11 |
| **GAP-004** | Escopo de Atuação na Conta (Símbolos e Magics) | **RESOLVIDA** | Escopo global da conta: todas as posições, todas as ordens pendentes, todos os símbolos, manuais ou de outros robôs. Sem filtros para o MVP. | Decisão D13 / [RN-004](file:///C:/Projetos/eddytrader/docs/05-REGRAS-DE-NEGOCIO.md#rn-004) / [RN-005](file:///C:/Projetos/eddytrader/docs/05-REGRAS-DE-NEGOCIO.md#rn-005) |
| **GAP-005** | Persistência vs. Reconstrução de Estado após Restart | **RESOLVIDA PARCIALMENTE / ADIADA PARA W03/W04** | Princípio de produto para MVP: priorizar reconstrução determinística baseada no histórico nativo do MT5 sobre persistência em arquivos (YAGNI). Avaliar em W03/W04 se baseline intradiária requer arquivo local mínimo. | Decisão D12 |
| **GAP-006** | Especificação Matemática da Baseline de Reabertura | **ADIADA PARA W03** | Conceito de nova janela aprovado na W02. A formulação matemática exata, equações de referência e invariantes numéricos serão especificados na W03. | [ADR 0001](file:///C:/Projetos/eddytrader/docs/adr/0001-regras-temporais-e-janelas-de-protecao.md) / W03 Roadmap |

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
* **Status:** **RESOLVIDA PARCIALMENTE / ADIADA PARA W03/W04**
* **Decisão:** Para o MVP, adotar a reconstrução determinística a partir do histórico nativo como primeira escolha técnica, reduzindo arquivos e complexidade. A necessidade de arquivo auxiliar mínimo para a baseline intradiária e tempo de bloqueio será delimitada na W03/W04.

---

## 3. Decisões de Projeto e Plataforma (DQs)

| ID | Título | Status | Escopo / Encaminhamento |
| :--- | :--- | :--- | :--- |
| **DQ-001** | Mecanismo Técnico de Bloqueio Operacional no MT5 | **ADIADA PARA W05** | Spike técnico prático para comprovar a viabilidade e latência da neutralização reativa via eventos de negociação (`OnTradeTransaction`) e polling vs. ordens manuais. |
| **DQ-002** | Tratamento de Contas Netting vs. Hedging | **ADIADA PARA W05** | Requisito de produto estabelece suporte a ambas as modalidades. A mecânica específica de fechamento e cancelamento será validada em laboratório no MT5. |
| **DQ-003** | Política de Slippage e Deviation em Fechamento de Emergência | **ADIADA PARA W05** | Definição da tolerância de desvio em pontos (`deviation`) para garantir execução sem requote durante alta volatilidade. |
| **DQ-004** | Tratamento de Ativos com Mercado Fechado | **ADIADA PARA W05** | Validação laboratorial de códigos de retorno (`TRADE_RETCODE_MARKET_CLOSED`) para assegurar não travamento e continuidade de processamento. |
| **DQ-005** | Detecção e Prevenção de Múltiplas Instâncias do EA | **ADIADA PARA W04** | Definição da regra para impedir que mais de uma instância do EddyTrader opere concorrentemente na mesma conta. |

---

## 4. Riscos Técnicos e Operacionais (RISKs)

| ID | Risco Identificado | Severidade | Probabilidade | Mitigação Proposta |
| :--- | :--- | :--- | :--- | :--- |
| **RISK-001** | **Derrapagem de Execução (Slippage):** A perda final consolidada ultrapassar o limite configurado devido à latência da corretora e slippage em ordens a mercado em momento de alta volatilidade. | Alta | Alta | Deixar formalizado que o limite é um gatilho de disparo de emergência, sujeito à liquidez e preços reais da contraparte da corretora. |
| **RISK-002** | **Falsa Sensação de Bloqueio Preventivo Físico:** O operador assumir que o EA desabilita o clique manual do MT5 antes do envio (impossível sem DLL). | Alta | Média | Esclarecer na documentação normativa que o bloqueio nativo atua por neutralização/liquidação reativa imediata no milissegundo em que a ordem for gerada. |
| **RISK-003** | **Divergência de Fuso Horário:** Operador interpretar o horário previsto de desbloqueio como horário local em vez do horário do servidor. | Média | Média | Mitigado pela formalização em D01/ADR 0001 (referência oficial é o horário do servidor). O EA deve exibir visualmente o horário atual do servidor e o instante exato de liberação no relógio do servidor ($t_{\text{bloqueio}} + 4\text{h}$). |
| **RISK-004** | **Degradação de Performance do MT5:** Loop de monitoramento excessivamente agressivo consumir alta CPU. | Média | Baixa | Utilizar arquitetura dirigida por eventos (`OnTick` e timer controlado de 500ms a 1s), evitando laços de espera ocupada. |
| **RISK-005** | **Perda de Estado em Falha Elétrica / Reinicialização:** Terminal reiniciado durante o período de 4 horas esquecer restrições se não reconstruir estado. | Média | Média | Mitigado pela diretriz de reconstrução determinística a partir do histórico diário de negócios e posições da conta. |
| **RISK-006** | **Múltiplas Instâncias Concorrentes:** Operador anexar o EddyTrader a mais de um gráfico da mesma conta, gerando concorrência e ordens duplicadas de fechamento. | Alta | Média | Requisito formal de instância única por conta (D14); especificar mecanismo de detecção/guarda em W04. |
| **RISK-007** | **Desconexão do Terminal / Falha de Rede com o Servidor:** Terminal perder conexão durante processo de fechamento de emergência. | Alta | Baixa | Registrar status de tentativa pendente e reexecutar a liquidação no primeiro instante de reconexão detectado. |

---

## 5. Rastreabilidade Documental

* Origem dos Requisitos: [03 — Requisitos](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md)
* Regras Normativas: [05 — Regras de Negócio](file:///C:/Projetos/eddytrader/docs/05-REGRAS-DE-NEGOCIO.md)
* Decisões Arquiteturais: [ADR 0001](file:///C:/Projetos/eddytrader/docs/adr/0001-regras-temporais-e-janelas-de-protecao.md) e [ADR 0002](file:///C:/Projetos/eddytrader/docs/adr/0002-composicao-da-perda-operacional.md)
* Alinhamento no Cronograma: [09 — Roadmap](file:///C:/Projetos/eddytrader/docs/09-ROADMAP.md)
