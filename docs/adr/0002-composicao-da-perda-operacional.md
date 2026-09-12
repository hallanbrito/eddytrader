# ADR 0002 — Composição da Perda Operacional

* **Status:** Accepted
* **Data:** 2026-09-12
* **Contexto:** W02 — Resolução de Decisões Críticas e GAPs do EddyTrader
* **Decisões Relacionadas:** D03, D04, D05, D06
* **GAPs Afetados:** GAP-002 (Resolvido)

---

## 1. Contexto e Problema

O requisito central aprovado do EddyTrader determina que o EA deve monitorar a perda diária da conta e intervir quando ela atingir ou ultrapassar o limite monetário estipulado pelo operador.

Entretanto, o conceito de "resultado financeiro" em uma conta de negociação no MetaTrader 5 envolve múltiplos componentes:
* Negócios fechados no dia (*Deal Profit* bruto).
* Custos de corretagem e taxas de bolsa (*Commissions*).
* Custos de financiamento noturno / rolagem (*Swaps*).
* Resultado flutuante de posições ainda abertas (*Unrealized / Floating PnL*).
* Transferências financeiras externas (depósitos, retiradas/saques, bônus e créditos administrativos).
* Posições abertas carregadas de dias anteriores (*carry trade* intradiário).

Sem uma definição clara de produto, métricas baseadas na variação do Saldo (*Balance*) ou Patrimônio Líquido (*Equity*) podem sofrer distorções severas (por exemplo, um saque de capital ser interpretado como perda por negociação, ou um depósito mascarar um prejuízo real catastrófico).

---

## 2. Decisões Tomadas

### 2.1. Regra Conceitual de Cálculo da Perda (D03)
O cálculo da métrica de risco do produto é formalizado conceitualmente pela relação:

$$\text{RESULTADO\_RELEVANTE} = \text{RESULTADO\_REALIZADO\_DO\_DIA} + \text{RESULTADO\_FLUTUANTE\_ATUAL}$$

O gatilho de proteção por perda máxima é disparado compulsoriamente no exato momento em que:

$$\text{RESULTADO\_RELEVANTE} \le - \text{LIMITE\_CONFIGURADO}$$

ou, de forma equivalente:

$$\text{PERDA\_DIÁRIA} \ge \text{LIMITE\_CONFIGURADO}, \quad \text{onde } \text{PERDA\_DIÁRIA} = -(\text{RESULTADO\_RELEVANTE})$$

*Exemplo:*
* Limite configurado: $500.00$
* Realizado do dia: $-300.00$
* Flutuante atual: $-205.00$
* Resultado relevante: $-505.00$ (Perda diária de $505.00$).
* **Ação:** Proteção acionada imediatamente.

### 2.2. Inclusão Obrigatória de Custos Operacionais (D04)
A métrica de risco do EddyTrader deve refletir a **variação econômica real líquida causada pela atividade de trading**.

Portanto, integram obrigatoriamente o resultado financeiro:
* Lucro e prejuízo das negociações fechadas.
* Comissões de corretagem e emolumentos.
* Taxas de custódia e financiamento de posições (*swaps*).
* Quaisquer outros custos diretamente atribuíveis às operações fornecidos nativamente pela plataforma.

*Nota da W02:* Esta regra define a intenção normativa de produto. Quais propriedades ou estruturas MQL5 serão consultadas será objeto da especificação da W03.

### 2.3. Exclusão Estrita de Movimentações de Capital (D05)
Movimentações financeiras que não decorram da atividade de negociação **não integram** a perda operacional relevante:
* Depósitos realizados pelo operador.
* Saques / retiradas de capital.
* Créditos ou ajustes administrativos da corretora.

*Exemplo:*
* Resultado de operações no dia: $-300.00$
* Saque efetuado pelo operador: $-1000.00$
* **Perda operacional relevante considerada pelo EddyTrader:** $-300.00$

Um saque nunca transformará a perda em $-1300.00$, nem um depósito mascarará um prejuízo operacional de $-300.00$.

### 2.4. Tratamento do Resultado Flutuante na Virada do Dia (D06)
Em relação a posições mantidas abertas durante a virada do dia operacional (`00:00:00` do servidor):
1. **Perdas e lucros realizados em dias anteriores não são carregados** para o cômputo realizado do novo dia.
2. O resultado realizado do novo dia considera apenas operações encerradas dentro do novo dia operacional.
3. Uma posição antiga que permaneça aberta **continua contribuindo com seu resultado flutuante atual** para a métrica do novo dia.

*Consequência Documentada:* Se na virada do dia uma posição antiga apresentar flutuante negativo mais severo que o limite diário (ex: flutuante atual de $-600.00$ para um limite de $500.00$), a proteção do novo dia **poderá ser acionada imediatamente no primeiro tick do novo dia**.

Esse comportamento é intencional e decorre da premissa de que a exposição aberta representa risco presente real sobre o patrimônio da conta.

---

## 3. Alternativas Consideradas

* **Uso da variação simples de Patrimônio Líquido ($\Delta Equity$):** Descartado porque a variação de saldo/equidade confunde transferências de capital (saques/depósitos) com perdas operacionais de mercado.
* **Ignorar custos operacionais (usar apenas lucro bruto):** Descartado porque em operações de alta frequência ou posições carregadas com alto swap, a comissão e o swap podem consumir grande parte da margem e provocar quebra de conta sem que o EA perceba.
* **Zerar o flutuante na virada de dia ou ignorar posições antigas:** Descartado porque deixaria posições perdedoras acumuladas soltas no novo dia sem proteção de risco, violando o propósito de preservação do capital.

---

## 4. Consequências

### Positivas
* Métrica de risco justa, imune a manipulações por depósitos/saques intradiários.
* Aderência estrita à realidade financeira do operador (contabiliza comissões e swaps reais).
* Rastreamento fidedigno do risco presente em posições carregadas de sessões anteriores.

### Negativas / Pontos de Atenção
* A extração isolada de negócios de trading e custos operacionais a partir do histórico do MT5 exige filtros cuidadosos na implementação para segregar negócios do tipo depósito/retirada (`DEAL_TYPE_BALANCE`).

---

## 5. Questões Ainda Não Resolvidas (Adiada para W03)

1. A especificação matemática detalhada, as fórmulas algébricas e os invariantes contábeis formais para o cálculo das componentes da perda (W03).
2. O mapeamento preciso dos identificadores e tipos de dados do MT5 para cada componente financeira (W03).
