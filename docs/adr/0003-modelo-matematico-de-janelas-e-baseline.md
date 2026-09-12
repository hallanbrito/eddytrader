# ADR 0003 — Modelo Matemático de Janelas Operacionais e Baseline de Reabertura

* **Status:** Accepted
* **Data:** 2026-09-12
* **Contexto:** W03 — Especificação Matemática da Perda e das Janelas de Proteção do EddyTrader
* **Decisões Relacionadas:** D03, D07, D08, D09, D10, D11, D12
* **GAPs Afetados:** GAP-006 (Resolvido), GAP-005 (Reavaliado)

---

## 1. Contexto e Problema

As decisões normativas aprovadas na W02 estabeleceram que:
1. O horário oficial é o do servidor de negociação da corretora.
2. O dia operacional estende-se de `00:00:00` a `23:59:59` do servidor.
3. A proteção fecha todas as posições, cancela ordens e impõe bloqueio contínuo com término temporal mínimo em **4 horas** ($t_{\text{unlock}} = t_{\text{trigger}} + 4\text{h}$), ocorrendo a reabertura efetiva em $t_{\text{reopen}} \ge t_{\text{unlock}}$.
4. A passagem da meia-noite (`00:00:00`) não cancela o bloqueio ativo.
5. A métrica financeira integra resultado realizado econômico de trading do dia e resultado flutuante atual, incluindo custos (comissões/swaps/taxas) e excluindo movimentações de capital externo (depósitos/saques).
6. Ao término das 4 horas e satisfeitas as condições de segurança, o sistema libera a conta em $t_{\text{reopen}} \ge t_{\text{unlock}}$ e inicia uma nova janela operacional de monitoramento.

Entretanto, surgiu o **problema crítico do rebloqueio imediato**:
* Se o operador sofreu um prejuízo de $\$520$ com limite $L = 500$, ao ser liberado após 4 horas o histórico realizado daquele dia continuará registrando o prejuízo de $\$520$.
* Se o sistema utilizasse a métrica bruta diária para decidir novo bloqueio, detectaria imediatamente $-520 \le -500$, provocando o rebloqueio instantâneo no mesmo tick da liberação.

Portanto, era necessário definir matematicamente:
* Como segmentar a sessão em janelas operacionais determinísticas;
* Como formalizar a `baseline_de_reabertura` de modo que o sistema proteja o capital contra novas perdas na nova janela sem ser iludido pelo prejuízo que motivou o bloqueio anterior;
* Como manter a integridade do modelo quando o bloqueio de 4 horas atravessar a meia-noite;
* Quais invariantes matemáticos devem governar a apuração financeira.

---

## 2. Decisão

Adotar o **Modelo Algébrico de Janelas Operacionais e Baseline de Reabertura**, formalizado integralmente em [10 — Especificação Matemática](file:///C:/Projetos/eddytrader/docs/10-ESPECIFICACAO-MATEMATICA.md).

### 2.1. Formulação da Baseline e Resultado de Janela
A sessão do operador é formalmente dividida em janelas operacionais sequenciais $J_n$ ($n = 0, 1, 2, \dots$):

1. **Primeira Janela do Dia ($J_0$):**
   Iniciada às `00:00:00` do dia operacional. Possui baseline inicial nula:
   $$B_0 = 0$$
   $$W_0(t) = D(t) - B_0 = D(t)$$
   onde $D(t) = R_{\text{day}}(t) + F(t)$, sendo $R_{\text{day}}(t)$ o resultado econômico realizado líquido de trading do dia e $F(t)$ o flutuante global da conta.
   A proteção dispara quando $W_0(t) \le -L$.

2. **Janelas Subsequentes pós-Desbloqueio ($J_n$, para $n \ge 1$):**
   Transcorrido o período contínuo mínimo de 4 horas de bloqueio ($t \ge t_{\text{unlock}}$) e satisfeitas todas as condições operacionais de segurança (ausência de ordens/posições residuais de liquidação falha e mercado acessível), ocorre a reabertura efetiva em $t_{\text{reopen}, n}$ ($t_{\text{reopen}, n} \ge t_{\text{unlock}, n-1}$), iniciando-se a janela $J_n$.
   A baseline é fotografada estaticamente no instante da efetiva reabertura:
   $$B_n = D(t_{\text{reopen}, n})$$
   Durante toda a vigência da janela $J_n$, a baseline permanece constante.
   O resultado da janela ativa no instante $t$ é:
   $$W_n(t) = D(t) - B_n$$
   A proteção é acionada se e somente se:
   $$W_n(t) \le -L$$

### 2.2. Eliminação Matemática do Rebloqueio Imediato
No instante da reabertura ($t = t_{\text{reopen}, n}$):
$$W_n(t_{\text{reopen}, n}) = D(t_{\text{reopen}, n}) - B_n = D(t_{\text{reopen}, n}) - D(t_{\text{reopen}, n}) = 0$$
Como $0 > -L$ (pois $L > 0$), o resultado econômico da nova janela é zero no instante da liberação. O sistema entra em monitoramento nominal (`MONITORING`) com a tolerância integral de perda $L$ renovada para novas deteriorações a partir daquele instante.

### 2.3. Comportamento diante de Ganhos e Perdas
* **Deterioração líquida:** Novas perdas a partir da baseline reduzem $W_n(t)$. Se a deterioração acumulada na janela atingir $-L$, nova proteção de 4 horas é ativada.
* **Ganhos na janela:** Operações lucrativas aumentam $W_n(t)$ acima de zero, melhorando a margem operacional da janela antes de qualquer novo bloqueio.

### 2.4. Cruzamento da Meia-Noite durante Bloqueio Ativo
Se o bloqueio for acionado às `23:30` (com liberação prevista para `03:30` do dia seguinte):
1. A passagem por `00:00:00` preserva o bloqueio ativo e inalterado ($t_{\text{unlock}} = \text{03:30}$).
2. Às `00:00:00`, a contabilidade diária é reiniciada para o novo dia ($R_{\text{day\_novo}} = 0$).
3. Ao atingir `03:30` ($t_{\text{unlock}}$) e ocorrendo a reabertura efetiva em $t_{\text{reopen}} \ge t_{\text{unlock}}$, a baseline de reabertura é calculada sobre a contabilidade do **novo dia operacional vigente no momento da reabertura**:
   $$B_{\text{new}} = D_{\text{novo\_dia}}(t_{\text{reopen}}) = R_{\text{day\_novo}}(t_{\text{reopen}}) + F(t_{\text{reopen}})$$
   Se não houver posições remanescentes, $B_{\text{new}} = 0 + 0 = 0$.

### 2.5. Invariantes Normativos (INV-001 a INV-010)
Ficam formalmente estabelecidos os invariantes matemáticos:
* **INV-001:** $L > 0$
* **INV-002:** $B_0 = 0$
* **INV-003:** $B_n = D(t_{\text{reopen}, n})$
* **INV-004:** $W_n(t) = D(t) - B_n$
* **INV-005:** Gatilho $W_n(t) \le -L$
* **INV-006:** $t_{\text{unlock}} = t_{\text{trigger}} + 14.400\text{s}$ e $t_{\text{reopen}} \ge t_{\text{unlock}}$ (com igualdade nominal $t_{\text{reopen}} = t_{\text{unlock}}$ sob condições normais de mercado e execução concluída)
* **INV-007:** Independência da Meia-Noite (preservação de $t_{\text{unlock}}$, do estado de bloqueio e reabertura em $t_{\text{reopen}} \ge t_{\text{unlock}}$)
* **INV-008:** Exclusão estrita de capital externo ($\Delta \text{Depósito}, \Delta \text{Saque} \notin D(t)$)
* **INV-009:** Ausência absoluta de dupla contagem de custos/lucros
* **INV-010:** Escopo global irrestrito da conta para $F(t)$

---

## 3. Alternativas Rejeitadas

1. **Apagar o histórico de transações da conta após a reabertura:**
   * *Rejeitada:* O EA não tem e não deve ter autoridade para expurgar registros contábeis do terminal. Isso corromperia extratos, relatórios fiscais e violaria a integridade contábil do MT5.
2. **Avaliar a perda acumulada bruta diária continuamente sem baseline:**
   * *Rejeitada:* Tornaria o desbloqueio inútil, pois qualquer tentativa de reabertura resultaria em bloqueio no mesmo tick pelo prejuízo já acumulado na sessão.
3. **Resetar o bloqueio às 00:00:00 (cancelar bloqueio na virada de dia):**
   * *Rejeitada:* Criaria uma brecha crítica de controle comportamental, permitindo que violações ocorridas às 23:55 liberassem a conta 5 minutos depois.
4. **Utilizar variação simples de Patrimônio Líquido ($\Delta \text{Equity}$):**
   * *Rejeitada:* A variação patrimonial bruta é poluída por saques e depósitos. Um saque de capital seria interpretado erroneamente como perda operacional, enquanto um aporte mascararia perdas catastróficas.
5. **Baseline dinâmica com trailing de perdas:**
   * *Rejeitada (YAGNI):* Introduziria complexidade algorítmica e comportamento não intuitivo para o operador no MVP.

---

## 4. Consequências

### Positivas
* **Previsibilidade Absoluta:** O comportamento financeiro do sistema é determinístico e rigorosamente testável em qualquer instante temporal.
* **Retomada Saudável:** A reabertura intradiária opera de forma limpa, garantindo a proteção da conta contra novas perdas sem rebloqueios falsos.
* **Integridade Contábil:** O histórico de negociações do usuário permanece intacto.
* **Resolução Formal do GAP-006:** A especificação da baseline de reabertura está plenamente resolvida e catalogada.

### Impactos Arquiteturais e Subsequentes (W04 e W05)
* **Reavaliação do GAP-005 (Continuidade e Restart):**
  A formalização matemática demonstrou que, se o terminal MT5 for reiniciado durante um bloqueio ativo ou durante uma janela subsequente ($n \ge 1$), o sistema necessita minimamente do par temporal $(t_{\text{trigger}}, t_{\text{unlock}})$, de $B_n$ e do estado operacional. A viabilidade técnica de reconstituir unívoca e deterministicamente todas essas variáveis a partir exclusivamente dos dados nativos do MT5 sem persistência auxiliar ainda não foi validada empiricamente, permanecendo como questão aberta pendente de spike técnico (GAP-005) na W04/W05.
* **Subsídio Direto para a FSM (W04):** A máquina de estados da W04 consumirá diretamente as equações $W_n(t)$, $t_{\text{trigger}}$, $t_{\text{unlock}}$ e $t_{\text{reopen}}$ para orquestrar as transições de estado.
* **Precisão Numérica (W05):** A implementação em MQL5 exigirá cuidados na comparação de ponto flutuante com o limite monetário configurado.

---

## 5. Rastreabilidade

* Documento Normativo Principal: [10 — Especificação Matemática](file:///C:/Projetos/eddytrader/docs/10-ESPECIFICACAO-MATEMATICA.md)
* Decisões Fundacionais Anteriores: [ADR 0001](file:///C:/Projetos/eddytrader/docs/adr/0001-regras-temporais-e-janelas-de-protecao.md) e [ADR 0002](file:///C:/Projetos/eddytrader/docs/adr/0002-composicao-da-perda-operacional.md)
* Próxima Etapa: W04 — Especificação Normativa da Máquina de Estados
