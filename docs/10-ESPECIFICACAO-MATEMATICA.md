# 10 — Especificação Matemática da Perda e das Janelas de Proteção

* **Status:** Normativo
* **Etapa:** W03 — Especificação Matemática da Perda e Janelas de Proteção
* **Origem:** Resoluções da W02 ([ADR 0001](file:///C:/Projetos/eddytrader/docs/adr/0001-regras-temporais-e-janelas-de-protecao.md), [ADR 0002](file:///C:/Projetos/eddytrader/docs/adr/0002-composicao-da-perda-operacional.md))
* **Aplicação:** Obrigatória para toda modelagem de estados, spikes técnicos e implementações futuras em MQL5.

---

## 1. Objetivo e Princípio Central

Este documento formaliza o modelo matemático determinístico, contínuo e testável do **EddyTrader**. Seu propósito é fornecer a resposta matemática inequívoca para as duas questões fundamentais do produto:

1. **Qual é exatamente a perda que o EddyTrader considera em qualquer instante $t$?**
2. **Qual é exatamente a perda considerada após o encerramento de um bloqueio de 4 horas e a liberação de uma nova janela operacional?**

O modelo aqui definido é puramente conceitual e independente de plataforma, garantindo que, dados os mesmos eventos financeiros e temporais, qualquer implementação chegue deterministicamente ao mesmo resultado.

---

## 2. Notação Matemática e Domínio das Variáveis

A tabela abaixo define os símbolos, descrições conceituais e domínios de valores utilizados no modelo:

| Símbolo | Significado Conceitual | Domínio / Unidade |
| :--- | :--- | :--- |
| $t$ | Instante de tempo corrente no relógio oficial do servidor de negociação. | Tempo contínuo em segundos ($\mathbb{R}_{\ge 0}$ ou timestamp UNIX). |
| $t_{\text{day}}$ | Instante correspondente a `00:00:00.000` do dia operacional corrente. | Ponto temporal fixo no dia corrente. |
| $L$ | Limite monetário máximo de perda configurado pelo operador. | $\mathbb{R}_{> 0}$ (magnitude monetária positiva). |
| $\Delta_{\text{lock}}$ | Duração normativa contínua do período de bloqueio operacional. | Constante fixa: $4\text{ horas} = 14.400\text{ segundos}$. |
| $t_{\text{trigger}}$ | Instante exato em que a violação do limite foi confirmada. | Ponto temporal no relógio do servidor. |
| $t_{\text{unlock}}$ | Instante mínimo em que a restrição temporal de 4 horas deixa de impedir uma eventual reabertura ($t_{\text{unlock}} = t_{\text{trigger}} + \Delta_{\text{lock}}$). | Ponto temporal no relógio do servidor. |
| $t_{\text{reopen}}$ | Instante efetivo em que o sistema ingressa em uma nova janela operacional e retorna ao monitoramento normal ($t_{\text{reopen}} \ge t_{\text{unlock}}$). | Ponto temporal no relógio do servidor. |
| $J_n$ | Janela operacional de negociação de índice $n \in \mathbb{N}_0$ ($J_0, J_1, J_2, \dots$). | Intervalo temporal semiaberto ou fechado. |
| $R_{\text{day}}(t)$ | Resultado econômico líquido realizado, relacionado à atividade de trading, ocorrido no dia operacional atual até o instante $t$. | $\mathbb{R}$ (na moeda da conta). |
| $F(t)$ | Resultado econômico flutuante (*unrealized PnL*) líquido de todas as posições abertas na conta no instante $t$. | $\mathbb{R}$ (na moeda da conta). |
| $D(t)$ | Métrica de resultado relevante diário acumulado no instante $t$. | $\mathbb{R}$ ($D(t) = R_{\text{day}}(t) + F(t)$). |
| $B_n$ | Baseline financeira da janela operacional $J_n$. | $\mathbb{R}$ ($B_0 = 0$; $B_n = D(t_{\text{reopen}, n})$ para $n \ge 1$). |
| $W_n(t)$ | Resultado econômico da janela operacional ativa $J_n$ no instante $t$. | $\mathbb{R}$ ($W_n(t) = D(t) - B_n$). |
| $P_n(t)$ | Perda econômica atribuída à janela operacional ativa $J_n$ no instante $t$. | $\mathbb{R}$ ($P_n(t) = -W_n(t)$). |

---

## 3. Intervalos Temporais e Referência do Servidor

### 3.1. Soberania Temporal do Servidor de Negociação
Toda avaliação temporal do modelo apoia-se exclusivamente no relógio oficial do servidor de negociação disponibilizado pela corretora no MetaTrader 5:
$$t = \text{TimeCurrent}_{\text{server}}$$
É vedado o uso de relógios locais da máquina do cliente, UTC desvinculado da corretora ou fusos horários arbitrários.

### 3.2. Definição Algébrica do Dia Operacional
Um dia operacional ordinário $\mathcal{D}$ inicia em $t_{\text{day}}$ e estende-se até o final do dia:
$$\mathcal{D} = [t_{\text{day}}, \, t_{\text{day}} + 86.400\text{s})$$
correspondendo exatamente ao intervalo das `00:00:00.000` até `23:59:59.999` do servidor.

---

## 4. Componentes Financeiros Fundamentais

### 4.1. Resultado Realizado Relevante $R_{\text{day}}(t)$
O resultado realizado diário $R_{\text{day}}(t)$ é formalizado conceitualmente como o **resultado econômico líquido realizado, relacionado à atividade de trading, ocorrido no dia operacional atual até o instante $t$**.

$$R_{\text{day}}(t) = \text{Resultado líquido realizado de trading no intervalo } [t_{\text{day}}, t]$$

#### Componentes Econômicos Abrangidos (quando aplicáveis):
1. **Lucros e Prejuízos Realizados:** Variações financeiras geradas por operações executadas no período diário.
2. **Comissões de Trading:** Custos de corretagem e emolumentos diretamente associados à atividade de negociação.
3. **Taxas de Financiamento Noturno (*Swaps*):** Ajustes de rolagem e custódia decorrentes da manutenção de posições.
4. **Outras Taxas Operacionais:** Quaisquer outros custos ou emolumentos diretamente atribuíveis ao trading registrados no histórico diário.

#### Componentes Estritamente Excluídos:
1. **Movimentações de Capital Externo:** Depósitos efetuados pelo operador, saques/retiradas de capital, créditos e bônus administrativos concedidos ou debitados pela corretora.
2. **Ajustes Não-Operacionais:** Correções de saldo ou transferências financeiras entre contas que não decorram da atividade de mercado.
   $$\Delta \text{CapitalExterno} \notin R_{\text{day}}(t)$$

#### Independência de Representação na Plataforma (Sem Amarra a Fechamento de Posição):
A formulação de $R_{\text{day}}(t)$ é puramente conceitual e deliberadamente agnóstica quanto ao momento exato ou à mecânica técnica em que a plataforma MetaTrader 5 contabiliza tais eventos (se a comissão é debitada na abertura, no fechamento, em lançamento separado ou consolidada na operação). Não se definem nesta etapa enums, deal types ou propriedades concretas de API MQL5.

#### Ausência de Dupla Contagem (Invariante Crítico):
Nenhum componente econômico pode ser computado mais de uma vez. Caso um valor financeiro disponibilizado pela plataforma já reflita o resultado líquido consolidado (incorporando comissões ou swaps), essas parcelas não deverão ser somadas novamente no cômputo de $R_{\text{day}}(t)$ (INV-009).

### 4.2. Resultado Flutuante Relevante $F(t)$
Seja $\mathcal{O}(t)$ o conjunto de todas as posições de mercado abertas na conta de negociação no instante $t$. O resultado flutuante consolidado é definido como:
$$F(t) = \sum_{p \in \mathcal{O}(t)} \Big( \text{LucroFlutuanteBruto}(p, t) + \text{CustosFlutuantes}(p, t) \Big)$$
onde $\text{CustosFlutuantes}(p, t)$ inclui comissões pendentes de liquidação e taxas de swap acumuladas pela posição aberta até o instante $t$.

#### Propriedades de $F(t)$:
1. **Escopo Global Irrestrito:** A soma abrange $100\%$ das posições da conta: todos os ativos, todos os robôs, ordens manuais, sem filtros por Magic Number, comentário ou símbolo.
2. **Dinâmica Contínua:** $F(t)$ varia a cada oscilação de cotação das posições ativas, podendo melhorar ou deteriorar o resultado da conta de forma contínua.
3. **Posições Carregadas de Dias Anteriores:** Se uma posição foi aberta em dia anterior e permaneceu aberta após a virada de dia, ela integra $\mathcal{O}(t)$ normalmente. Seu resultado flutuante total no instante $t$ compõe $F(t)$ integralmente.

### 4.3. Diferença Fundamental entre Variação de Saldo / Equidade e a Métrica Operacional
O EddyTrader rejeita expressamente as formulações ingênuas:
$$D_{\text{invalido}}(t) \ne \text{Saldo}(t) - \text{Saldo}(t_{\text{day}})$$
$$D_{\text{invalido}}(t) \ne \text{Equidade}(t) - \text{Equidade}(t_{\text{day}})$$

**Justificativa Técnica:**
* Um saque de $\$1.000$ efetuado pelo operador reduz o Saldo e a Equidade em $\$1.000$, mas representa retirada patrimonial e não prejuízo operacional de trading.
* Um depósito de $\$5.000$ eleva o Saldo e a Equidade, mas mascararia uma perda operacional real violadora do limite.
* O modelo do EddyTrader mede exclusivamente a **destruição ou geração de valor decorrente da atividade de negociação**.

---

## 5. Métrica de Resultado Diário Acumulado $D(t)$

A qualquer instante $t$, o resultado econômico diário relevante da conta é definido por:
$$D(t) = R_{\text{day}}(t) + F(t)$$

A perda operacional acumulada no dia é o inverso aditivo desse valor:
$$\text{Perda}_{\text{day}}(t) = -D(t)$$

---

## 6. Ciclo de Janelas Operacionais e Modelo de Baseline

### 6.1. Primeira Janela do Dia: Janela $J_0$
A primeira janela operacional do dia tem início formal às `00:00:00.000` do servidor:
$$t_{\text{inicio}, 0} = t_{\text{day}}$$

Para a primeira janela $J_0$, a baseline de referência é nula:
$$B_0 = 0$$

O resultado financeiro da janela $J_0$ é dado por:
$$W_0(t) = D(t) - B_0 = D(t)$$

A proteção dispara quando o resultado da janela atingir ou ultrapassar a perda tolerada:
$$W_0(t) \le -L \iff D(t) \le -L \iff \text{Perda}_{\text{day}}(t) \ge L$$

---

### 6.2. O Problema do Rebloqueio Imediato
Suponha que na janela $J_0$, com limite $L = 500$, a conta atinja $D(t_{\text{trigger}}) = -520$. O sistema encerra as posições e impõe o bloqueio de 4 horas.

Ao término das 4 horas ($t_{\text{unlock}}$), se o sistema avaliasse simplesmente a perda do dia $D(t)$, constataria que o resultado realizado do dia continua sendo $-520$ (ou pior, após custos de liquidação). Sem um modelo de nova janela, a condição $D(t) \le -500$ continuaria verdadeira no primeiro milissegundo pós-desbloqueio, provocando um **rebloqueio falso instantâneo**, violando a premissa de liberação aprovada na W02.

---

### 6.3. Solução Normativa: Modelo de Baseline de Reabertura
Para permitir que o operador utilize a conta após o período punitivo de 4 horas sem apagar os dados contábeis do dia, o sistema segmenta a sessão em **janelas operacionais sequenciais** $J_0, J_1, J_2, \dots, J_n$:

1. Seja $t_{\text{reopen}, n}$ o instante exato em que o bloqueio anterior é removido e a nova janela operacional $J_n$ ($n \ge 1$) é iniciada:
   $$t_{\text{reopen}, n} \ge t_{\text{unlock}, n-1}$$
2. No momento da reabertura, o sistema fotografa o estado contábil diário da conta e fixa a baseline da janela $n$:
   $$B_n = D(t_{\text{reopen}, n})$$
3. A baseline $B_n$ permanece **estritamente constante** durante toda a vigência da janela $J_n$:
   $$\forall t \in J_n, \quad \frac{d B_n}{dt} = 0$$
4. O resultado econômico da janela ativa $J_n$ para qualquer $t \ge t_{\text{reopen}, n}$ é a variação líquida a partir da baseline:
   $$W_n(t) = D(t) - B_n$$
5. A nova proteção de emergência dispara se e somente se:
   $$W_n(t) \le -L \iff D(t) - B_n \le -L \iff D(t) \le B_n - L$$

---

### 6.4. Análise de Ganhos e Perdas em Janelas Pós-Reabertura

#### Caso A: Deterioração Direta após Reabertura
* $L = 500$
* Reabertura com $D(t_{\text{reopen}}) = -520 \implies B_1 = -520$.
* No instante exato da reabertura:
  $$W_1(t_{\text{reopen}}) = -520 - (-520) = 0$$
  Como $0 > -500$, **não há rebloqueio imediato**.
* Nova perda operacional de $200$ leva o acumulado a $D(t) = -720$:
  $$W_1(t) = -720 - (-520) = -200$$
  Como $-200 > -500$, a proteção permanece em vigilância nominal (`MONITORING`).
* Nova deterioração leva o acumulado a $D(t) = -1025$:
  $$W_1(t) = -1025 - (-520) = -505$$
  Como $-505 \le -500$, a proteção é disparada compulsoriamente.

#### Caso B: Lucro após Reabertura seguido de Queda
* $L = 500$, baseline ativa $B_1 = -520$.
* O operador obtém lucro nas operações da nova janela, reduzindo o prejuízo acumulado do dia para $D(t) = -300$:
  $$W_1(t) = -300 - (-520) = +220$$
  O resultado da janela é positivo ($+\$220$). Esse ganho melhora a margem da janela corrente.
* Posteriormente, o mercado oscila negativamente e o acumulado do dia piora para $D(t') = -700$:
  $$W_1(t') = -700 - (-520) = -180$$
  Como $-180 > -500$, a proteção **não** dispara.
* **Propriedade Formal:** A nova janela mede a **deterioração líquida marginal acumulada na janela** a partir de $B_n$. Ganhos obtidos na janela aumentam o fôlego financeiro antes de atingir o limite $L$.

---

## 7. Regras e Condição de Acionamento da Proteção

### 7.1. Condição Formal de Gatilho
Na janela operacional ativa $J_n$, a condição necessária e suficiente para disparo da proteção é:
$$W_n(t) \le -L$$

### 7.2. Carimbo Temporal do Acionamento e Instante Mínimo de Desbloqueio
No instante exato em que a condição de gatilho for satisfeita:
1. Registra-se o instante do acionamento da proteção:
   $$t_{\text{trigger}} = t$$
2. Calcula-se o instante oficial mínimo em que a restrição temporal de 4 horas expira:
   $$t_{\text{unlock}} = t_{\text{trigger}} + \Delta_{\text{lock}} = t_{\text{trigger}} + 14.400\text{s}$$

### 7.3. Janela Temporal Mínima vs. Estado Operacional de Proteção e Reabertura
É imperativo distinguir formalmente a **condição temporal estrita** do **estado operacional de proteção**:

1. **Janela Temporal Obrigatória de Bloqueio:** O sistema permanece incondicionalmente sob bloqueio temporal no intervalo semiaberto:
   $$t \in [t_{\text{trigger}}, \, t_{\text{unlock}})$$
   Durante essa janela de 4 horas, nenhuma reabertura é admitida sob qualquer hipótese.
2. **Condição Necessária vs. Condição Suficiente:** O decurso integral das 4 horas ($t \ge t_{\text{unlock}}$) é uma **condição necessária** para a liberação da conta, mas **pode não ser uma condição suficiente** se ainda existir uma condição de proteção ativa não resolvida (por exemplo, exposições remanescentes que não puderam ser liquidadas por mercado fechado ou recusa de ordem).
3. **Instante Efetivo de Reabertura ($t_{\text{reopen}}$):**
   Define-se $t_{\text{reopen}}$ como o instante efetivo em que o sistema encerra a proteção, estabelece a nova baseline, abre a nova janela operacional e retorna ao monitoramento normal (`MONITORING`). O modelo impõe a relação normativa:
   $$t_{\text{reopen}} \ge t_{\text{unlock}}$$
   * **Caso Nominal (sem pendências de proteção):**
     $$t_{\text{reopen}} = t_{\text{unlock}}$$
   * **Caso com Condição de Segurança Pendente:**
     $$t_{\text{reopen}} > t_{\text{unlock}}$$
     O sistema permanece retido em estado de proteção/contenção além de $t_{\text{unlock}}$, tornando-se apto a reabrir somente no instante $t_{\text{reopen}}$ em que todas as condições de segurança forem satisfeitas.

### 7.4. Efeito da Liquidação Compulsória na Composição Contábil
O acionamento da proteção em $t_{\text{trigger}}$ toma como base a fotografia econômica naquele instante:
$$W_n(t_{\text{trigger}}) = R_{\text{day}}(t_{\text{trigger}}) + F(t_{\text{trigger}}) - B_n \le -L$$

O processo de liquidação fecha as posições abertas $\mathcal{O}(t)$, transformando o flutuante $F(t)$ em realizado $R(t)$ e reduzindo $F(t) \to 0$.
Essa mutação contábil interna **não altera nem cancela o evento de proteção já disparado**. O estado de bloqueio permanece soberano pelo menos até $t_{\text{unlock}}$.

### 7.5. Derrapagem de Preço (Slippage) e Perda Efetiva Final
O limite $L$ atua como **gatilho de contenção**, e não como garantia de teto patrimonial absoluto.
Devido à volatilidade de mercado, latência e liquidez no momento do envio das ordens a mercado, o resultado final consolidado pós-liquidação satisfaz:
$$W_{\text{final}} \le W_n(t_{\text{trigger}}) \le -L$$
A ocorrência de $W_{\text{final}} < -L$ é uma propriedade intrínseca da execução a mercado e não invalida a consistência matemática do modelo.

---

## 8. Transições Temporais e Virada do Dia Operacional

### 8.1. Virada de Dia sem Bloqueio Ativo (`00:00:00`)
Se no instante de transição de dia $t_{\text{meia-noite}}$ o sistema estiver em estado nominal de monitoramento:
1. A janela anterior $J_n$ é encerrada.
2. Inicia-se a janela $J_0$ do novo dia operacional.
3. A baseline é reiniciada para zero:
   $$B_0 = 0$$
4. O resultado realizado diário é reiniciado:
   $$R_{\text{day\_novo}}(t_{\text{meia-noite}}) = 0$$
5. O resultado flutuante $F(t_{\text{meia-noite}})$ continua sendo computado integralmente para todas as posições abertas mantidas na virada.
6. A nova métrica do início do dia é:
   $$D_{\text{novo}}(t_{\text{meia-noite}}) = 0 + F(t_{\text{meia-noite}}) = F(t_{\text{meia-noite}})$$
   $$W_0(t_{\text{meia-noite}}) = F(t_{\text{meia-noite}})$$

*Consequência:* Se uma posição antiga carregar um flutuante negativo tal que $F(t) \le -L$, a proteção da nova janela $J_0$ disparará imediatamente no primeiro evento do novo dia.

---

### 8.2. Virada de Dia com Bloqueio Ativo (Cruzamento da Meia-Noite)
Se a proteção for acionada nas horas finais do dia (ex: $t_{\text{trigger}} = \text{23:30}$), o instante mínimo de liberação ocorrerá na madrugada do dia subsequente ($t_{\text{unlock}} = \text{03:30}$).

**Regras Normativas de Cruzamento:**
1. **Invariância da Duração:** A transição por `00:00:00` **não encerra, não abrevia e não altera** $t_{\text{unlock}}$. O bloqueio vigora ininterruptamente pelo intervalo mínimo $[t_{\text{trigger}}, t_{\text{unlock}})$.
2. **Virada Contábil:** Às `00:00:00`, a contabilidade diária do servidor inicia um novo dia. O histórico realizado do dia anterior deixa de compor $R_{\text{day\_novo}}$.
3. **Determinação da Baseline no Instante da Reabertura Efetiva ($t_{\text{reopen}}$):**
   Ao atingir as condições de liberação em $t_{\text{reopen}}$ (com $t_{\text{reopen}} \ge t_{\text{unlock}}$), o sistema encerra a proteção e inicia a nova janela operacional. A baseline da nova janela é calculada estritamente sobre a contabilidade do **novo dia operacional vigente no instante real da reabertura**:
   $$B_{\text{new}} = D_{\text{novo\_dia}}(t_{\text{reopen}}) = R_{\text{day\_novo}}(t_{\text{reopen}}) + F(t_{\text{reopen}})$$
   No caso nominal em que não há pendências de segurança e $t_{\text{reopen}} = t_{\text{unlock}} = \text{03:30}$:
   $$B_{\text{new}} = D_{\text{novo\_dia}}(\text{03:30}) = R_{\text{day\_novo}}(\text{03:30}) + F(\text{03:30})$$

#### Demonstração Numérica do Cruzamento (Exemplo Base)
* Limite $L = 500$.
* Dia A, às 23:30: $R_{\text{day}} = -300$, $F = -220 \implies D = -520 \le -500 \implies$ Disparo.
* Liquidação ocorre: posições encerradas com ligeiro slippage, $F \to 0$, $R_{\text{day}} = -530$.
* $t_{\text{trigger}} = \text{23:30}$, $t_{\text{unlock}} = \text{03:30}$ do Dia B.
* Dia B, às 00:00: Novo dia operacional inicia. $R_{\text{day\_novo}} = 0$, $F = 0$. O bloqueio permanece rigorosamente ativo.
* Dia B, às 03:30: Relógio alcança $t_{\text{unlock}}$. Não há pendências $\implies t_{\text{reopen}} = \text{03:30}$.
  $$D_{\text{novo\_dia}}(\text{03:30}) = R_{\text{day\_novo}}(\text{03:30}) + F(\text{03:30}) = 0 + 0 = 0$$
  $$B_{\text{new}} = 0$$
* A nova janela inicia com baseline zero e resultado nulo ($W_{\text{new}} = 0 - 0 = 0$), pronta para monitorar a sessão do Dia B com a tolerância integral de $\$500$.

#### Demonstração com Posição Remanescente por Falha de Fechamento (Variante)
* Suponha que, no fechamento às 23:30, uma posição em ativo ilíquido não pôde ser fechada e permaneceu aberta na virada com $F = -150$.
* Dia B, às 00:00: $R_{\text{day\_novo}} = 0$, $F = -150$. Bloqueio continua.
* Dia B, após resolução ou na reabertura efetiva em $t_{\text{reopen}} \ge \text{03:30}$, a posição remanescente flutua em $F(t_{\text{reopen}}) = -160$.
  $$D_{\text{novo\_dia}}(t_{\text{reopen}}) = 0 + (-160) = -160$$
  $$B_{\text{new}} = -160$$
* Resultado da nova janela no momento da reabertura:
  $$W_{\text{new}}(t_{\text{reopen}}) = D_{\text{novo\_dia}}(t_{\text{reopen}}) - B_{\text{new}} = -160 - (-160) = 0$$
  O sistema **não rebloqueia no mesmo tick**.
* Se essa posição continuar piorando e atingir $F(t) = -665$:
  $$W_{\text{new}}(t) = -665 - (-160) = -505$$
  Como $-505 \le -500$, o sistema aciona uma nova proteção defensiva de 4 horas.

---

## 9. Invariantes Matemáticos Normativos

O modelo matemático do EddyTrader é regido por dez invariantes absolutos:

* **INV-001 (Limite Positivo):** O limite de perda é estritamente positivo:
  $$L > 0, \quad L \in \mathbb{R}$$
* **INV-002 (Baseline Inicial Nula):** A primeira janela operacional de qualquer dia inicia com baseline zero:
  $$B_0 = 0$$
* **INV-003 (Baseline Pós-Reabertura):** Para qualquer janela $J_n$ subsequente a um desbloqueio ($n \ge 1$), a baseline é igual ao resultado diário consolidado no instante exato e efetivo da reabertura:
  $$B_n = D(t_{\text{reopen}, n})$$
* **INV-004 (Resultado da Janela):** O resultado financeiro considerado em qualquer janela $J_n$ no instante $t$ é a diferença líquida entre o resultado diário e a baseline da janela:
  $$W_n(t) = D(t) - B_n$$
* **INV-005 (Condição de Gatilho):** A proteção dispara no instante em que o resultado da janela ativa atinge ou ultrapassa a magnitude do limite:
  $$W_n(t) \le -L$$
* **INV-006 (Duração Mínima do Bloqueio e Reabertura Condicionada):** O instante mínimo de liberação temporal é exatamente quatro horas posterior ao acionamento, e a reabertura efetiva nunca antecede esse marco:
  $$t_{\text{unlock}} = t_{\text{trigger}} + 14.400\text{s} \quad \text{e} \quad t_{\text{reopen}, n} \ge t_{\text{unlock}, n-1}$$
* **INV-007 (Independência da Meia-Noite):** A passagem por `00:00:00` do servidor preserva inalterado o valor de $t_{\text{unlock}}$ e a vigência do bloqueio ativo temporal ($t \in [t_{\text{trigger}}, t_{\text{unlock}}) \implies \text{Bloqueio Temporal Ativo}$).
* **INV-008 (Capital Externo Excluído):** Movimentações financeiras de capital não afetam a métrica de resultado:
  $$\forall \Delta \text{Depósito}, \Delta \text{Saque}, \quad \frac{\partial D(t)}{\partial (\Delta \text{CapitalExterno})} = 0$$
* **INV-009 (Ausência de Dupla Contagem):** Nenhum componente econômico (lucro, prejuízo, comissão, swap, taxa) pode ser contabilizado mais de uma vez na composição de $D(t)$.
* **INV-010 (Escopo Global da Conta):** O cômputo de $F(t)$ abrange a totalidade das posições de mercado ativas na conta:
  $$\mathcal{O}(t) = \text{União de 100\% das posições abertas na conta}$$

---

## 10. Análise de Continuidade e Reinicialização do Sistema (Restart)

### 10.1. Restart durante Janela Operacional Normal
1. **Janela $J_0$:** Se o terminal for reiniciado durante a primeira janela do dia sem bloqueios anteriores, $B_0 = 0$. $R_{\text{day}}(t)$ e $F(t)$ podem ser recuperados a partir dos dados do servidor de negociação.
2. **Janela $J_n$ ($n \ge 1$):** Se o terminal for reiniciado após uma ou mais reaberturas intradiárias, o valor de $B_n$ precisa estar disponível para calcular $W_n(t) = D(t) - B_n$.

### 10.2. Restart durante Bloqueio Operacional Vigente
Considere o cenário:
$$t_{\text{trigger}} = \text{14:25}, \quad t_{\text{unlock}} = \text{18:25}$$
Se o terminal sofrer reinicialização às `16:10`, o sistema deve reconhecer que a janela temporal mínima satisfaz $16:10 < 18:25$, restando $2\text{h}15\text{min}$ ($135\text{ min}$) para $t_{\text{unlock}}$.
*Nota sobre Reabertura:* Durante a vigência do bloqueio, o sistema conhece $t_{\text{unlock}}$, mas não conhece necessariamente $t_{\text{reopen}}$ com antecedência caso condições de segurança dependam de fatores dinâmicos no momento da liberação.

### 10.3. Conjunto Mínimo de Informação de Estado Conceitual
A análise matemática demonstrou que a reconstrução determinística de determinadas situações (como reinicialização durante bloqueio ativo ou em janelas subsequentes com $n \ge 1$) exige que informações conceituais sejam recuperáveis ou deterministicamente deriváveis:
1. **Estado operacional vigente** (monitoramento nominal, liquidação, bloqueio ativo ou retenção de proteção);
2. **Baseline da janela ativa** ($B_n$);
3. **Instante de acionamento da proteção** ($t_{\text{trigger}}$);
4. **Instante mínimo de liberação temporal** ($t_{\text{unlock}}$);
5. **Identidade / índice lógico da janela** ($J_n$).

**Diretriz Metodológica Normativa:**
A W03 identifica essas necessidades sob a ótica puramente matemática e conceitual. **Ainda não foi demonstrado se os dados nativos disponibilizados pelo MT5/MQL5 são suficientes para derivar integralmente o estado necessário ou se haverá necessidade de mecanismo de persistência auxiliar.** Essa suficiência técnica não foi avaliada por spike técnico e permanece pendente para deliberação na FSM da W04 e no Spike Técnico da W05.

---

## 11. Casos de Teste Verificáveis (Suíte Documental MATH)

A tabela a seguir estabelece os cenários canônicos para verificação matemática determinística:

| ID | Parâmetros e Variáveis de Entrada | Cálculo Intermediário | Resultado Esperado | Validação |
| :--- | :--- | :--- | :--- | :--- |
| **MATH-01** | $L = 500$, $R_{\text{day}} = -300$, $F = -210$, $B_0 = 0$ | $D = -300 + (-210) = -510$<br>$W_0 = -510 - 0 = -510$ | $W_0 \le -500 \implies$ **PROTEÇÃO ACIONADA (SIM)** | Pass |
| **MATH-02** | $L = 500$, $R_{\text{day}} = -200$, $F = -250$, $B_0 = 0$ | $D = -200 + (-250) = -450$<br>$W_0 = -450 - 0 = -450$ | $W_0 > -500 \implies$ **PROTEÇÃO NÃO DISPARA (NÃO)** | Pass |
| **MATH-03** | Reabertura com $D(t_{\text{reopen}}) = -520 \implies B_1 = -520$.<br>Posteriormente: $D(t) = -700$, $L = 500$ | $W_1 = -700 - (-520) = -180$ | $W_1 > -500 \implies$ **PROTEÇÃO NÃO DISPARA (NÃO)** | Pass |
| **MATH-04** | Janela $J_1$ com $B_1 = -520$.<br>Posteriormente: $D(t) = -1025$, $L = 500$ | $W_1 = -1025 - (-520) = -505$ | $W_1 \le -500 \implies$ **PROTEÇÃO ACIONADA (SIM)** | Pass |
| **MATH-05** | Janela $J_1$ com $B_1 = -520$.<br>Operações lucrativas levam a $D(t) = -300$. | $W_1 = -300 - (-520) = +220$ | $W_1 = +220$ (margem adicional de ganho na janela) | Pass |
| **MATH-06** | Acionamento às $t_{\text{trigger}} = \text{23:30:00}$ do Dia A.<br>Duração normativa: $\Delta_{\text{lock}} = 4\text{h}$. | $t_{\text{unlock}} = \text{23:30:00} + 4\text{h}$ | $t_{\text{unlock}} = \text{03:30:00}$ do Dia B (madrugada subsequente) | Pass |
| **MATH-07** | Virada de dia sem bloqueio ativo.<br>Novo dia: $R_{\text{day}} = 0$, $F = -600$, $L = 500$, $B_0 = 0$. | $D = 0 + (-600) = -600$<br>$W_0 = -600 - 0 = -600$ | $W_0 \le -500 \implies$ **PROTEÇÃO ACIONADA IMEDIATAMENTE (SIM)** | Pass |
| **MATH-08** | $R_{\text{operacional}} = -200$.<br>Saque realizado na conta pelo operador: $-\$1.000$. | Saque é capital externo $\implies$ excluído de $R_{\text{day}}$. | $R_{\text{day}} = -200$ (não se altera para $-1.200$) | Pass |
| **MATH-09** | $\text{PnL}_{\text{bruto}} = -450$, $\text{Comissão} = -20$, $\text{Swap} = -10$.<br>(Componentes não consolidados previamente). | $R_{\text{day}} = -450 + (-20) + (-10) = -480$ | $R_{\text{day}} = -480$ (custos operacionais somados sem dupla contagem) | Pass |
| **MATH-10** | Bloqueio em $t_{\text{trigger}} = \text{14:25}$, $t_{\text{unlock}} = \text{18:25}$.<br>Terminal reinicia às $t = \text{16:10}$. | Comparação temporal: $\text{16:10} < \text{18:25}$. | **BLOQUEIO VIGENTE**. Faltam exatamente $2\text{h}15\text{min}$ para $t_{\text{unlock}}$. | Pass |
| **MATH-11** | $t_{\text{trigger}} = \text{14:00}$, $t_{\text{unlock}} = \text{18:00}$.<br>Às $t = \text{18:00}$: condição de proteção ainda não encerrada (exposição remanescente). | Comparação temporal e de segurança:<br>$t = \text{18:00} \ge t_{\text{unlock}}$, mas condição de proteção ativa. | $t_{\text{reopen}} > \text{18:00}$. As 4 horas foram cumpridas, mas a nova janela operacional não é aberta até que a condição de segurança seja satisfeita. | Pass |

---

## 12. Propriedades Matemáticas do Modelo

1. **Não-Monotonicidade de $D(t)$:** A função $D(t)$ não é monotonicamente decrescente nem crescente. Oscilações favoráveis de mercado ou fechamento de operações no lucro aumentam $D(t)$; operações perdedoras diminuem $D(t)$.
2. **Constância da Baseline na Janela:** Para qualquer janela operacional $J_n$, $B_n$ é um escalar estático fixado no instante $t_{\text{reopen}, n}$.
3. **Condições Exclusivas de Redefinição de Baseline:** A baseline $B$ somente é redefinida em dois eventos normativos:
   * **Início de novo dia operacional sem bloqueio herdado:** $B_0 \gets 0$.
   * **Abertura de nova janela após encerramento de bloqueio de 4 horas:** $B_n \gets D(t_{\text{reopen}, n})$.
4. **Preservação Integral do Histórico:** A redefinição de baseline é uma operação puramente relacional sobre a métrica da janela ($W_n = D - B_n$) e **nunca altera, zera ou expurga** os registros contábeis originais da conta.

---

## 13. Requisitos Futuros de Precisão Numérica

Para subsidiar o spike técnico (W05) e a implementação (W06):
1. **Aritmética Monetária Determinística:** Comparações financeiras entre $W_n(t)$ e $-L$ devem ser estritamente determinísticas, respeitando o número de casas decimais da moeda base da conta (geralmente 2 casas decimais).
2. **Prevenção de Erros de Ponto Flutuante:** Em implementações binárias de ponto flutuante (`double`), comparações de desigualdade estrita ou de margem devem evitar tolerâncias arbitrárias que mascarem violações de limite. A especificação concreta de normalização monetária será validada na W05.
