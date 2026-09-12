# 08 — Riscos Técnicos, Lacunas e Questões Abertas

Este documento cataloga de forma explícita e rastreável todas as ambiguidades conceituais, riscos técnicos e decisões de projeto pendentes do **EddyTrader**.

> **Diretriz C.H.:** Nenhuma ambiguidade ou detalhe técnico omisso na especificação original foi inventado ou assumido tacitamente. As questões estão registradas como pendentes até sua deliberação ou validação via Spike Técnico.

---

## 1. Lacunas de Especificação (GAPs)

### GAP-001 — Definição do Fuso Horário e Marco Inicial do "Dia"
* **Descrição:** A especificação determina o monitoramento da "perda diária", mas não define qual relógio rege o início e término do dia.
* **Por que importa:** Se o dia for considerado pelo fuso horário do servidor da corretora (comum no Forex/CFDs, ex: GMT+2/GMT+3), o reset ocorre em horário diferente do horário civil local do operador (ex: GMT-3 no Brasil). Uma perda corrida às 19h locais pode cair no "dia seguinte" da corretora.
* **Opções Possíveis:**
  1. *Opção A:* Utilizar estritamente o horário do servidor da corretora (`TimeCurrent()`).
  2. *Opção B:* Utilizar o horário local da máquina do usuário (`TimeLocal()`).
  3. *Opção C:* Tornar o fuso horário ou o horário de início do dia configurável pelo operador.
* **Status:** **PENDENTE DE VALIDAÇÃO (Prioridade: Alta)**.

---

### GAP-002 — Composição Financeira do Resultado Relevante
* **Descrição:** O requisito aprovado estabelece: *"resultado financeiro realizado durante o período considerado somado ao resultado financeiro das posições ainda abertas"*. Não foi formalizado como tratar depósitos, saques, comissões de corretagem e custos de rolagem (*swap*).
* **Por que importa:** Se o operador depositar ou retirar recursos durante o pregão, uma apuração baseada puramente na variação de Saldo (*Balance*) ou Patrimônio (*Equity*) distorcerá a métrica de perda operacional. Além disso, se comissões e swaps não forem somados ao lucro bruto das posições, a perda real da conta será subestimada.
* **Opções Possíveis:**
  1. *Opção A:* Soma do lucro líquido dos negócios fechados no dia (`Deal Profit + Deal Commission + Deal Swap`) + lucro flutuante líquido das posições abertas (`Position Profit + Position Swap`). Ignora movimentações de depósito/saque.
  2. *Opção B:* Variação líquida do patrimônio líquido (*Equity Delta*) descontando transferências de capital identificadas.
* **Status:** **PENDENTE DE VALIDAÇÃO (Prioridade: Alta)**.

---

### GAP-003 — Consistência Temporal do Horário de Desbloqueio
* **Descrição:** O operador configura o horário de desbloqueio como string/hora (ex: `16:00`). O que deve acontecer se o bloqueio for disparado às `16:30` (horário posterior ao desbloqueio) ou se o bloqueio for acionado às `23:00` com liberação prevista para as `09:00` do dia seguinte?
* **Por que importa:** Sem regra clara de comparação temporal, uma checagem ingênua do tipo `HoraAtual >= HoraDesbloqueio` faria com que uma conta bloqueada às 16:30 fosse desbloqueada no milissegundo seguinte caso a hora de desbloqueio fosse 16:00.
* **Opções Possíveis:**
  1. *Opção A:* Se `Horário de Bloqueio >= Horário de Desbloqueio`, a liberação só ocorre no dia civil seguinte ao atingir o horário.
  2. *Opção B:* Exigir que o horário de desbloqueio seja sempre estritamente no mesmo dia operacional, desarmando o bloqueio somente às 00:00 se a hora configurada já tiver passado.
  3. *Opção C:* Adicionar parâmetro de "duração do bloqueio em minutos" além do horário fixo.
* **Status:** **PENDENTE DE VALIDAÇÃO (Prioridade: Alta)**.

---

### GAP-004 — Escopo de Atuação na Conta (Símbolos e Magic Numbers)
* **Descrição:** O requisito estabelece fechar todas as posições da conta. Caso o operador execute outros robôs com Magic Numbers específicos ou opere múltiplos ativos simultaneamente, o EddyTrader deve atuar sobre a conta inteira ou admitir filtros?
* **Por que importa:** Em contas compartilhadas com múltiplos robôs, liquidar a conta inteira interrompe estratégias alheias. Para gestão de risco global, no entanto, a conta inteira é a abordagem mais segura.
* **Opções Possíveis:**
  1. *Opção A:* Escopo global de conta (fecha absolutamente tudo na conta, sem filtro de símbolo ou Magic Number — alinhado à especificação original).
  2. *Opção B:* Suporte futuro a filtro opcional por Magic Number ou símbolo atual.
* **Status:** **PRESERVADO ESCOPO GLOBAL DA CONTA (Evolução opcional catalogada para Pós-MVP)**.

---

### GAP-005 — Persistência e Reconstrução de Estado após Reinicialização
* **Descrição:** O que acontece se o terminal MT5 for reiniciado, a máquina sofrer queda de energia ou o operador remover e reinserir o EA durante o estado `BLOCKED`?
* **Por que importa:** Se o estado do EA residir puramente na memória volátil RAM, ao reiniciar o terminal o EA iniciará em `MONITORING`. Se o cálculo de perda do dia ainda apontar perda >= limite, ele reentraria em bloqueio imediatamente, mas se o resultado tiver sido zerado pelo fechamento das posições ou pela interpretação do dia, o bloqueio pode ser perdido prematuramente.
* **Opções Possíveis:**
  1. *Opção A (Reconstrução Dinâmica Pura):* O EA não salva arquivos em disco. Na inicialização (`OnInit`), ele recalcula o histórico do dia; se a perda realizada já excedeu o limite e o horário atual for anterior ao horário de desbloqueio, entra automaticamente em `BLOCKED`.
  2. *Opção B (Persistência em Disco Local):* O EA grava um arquivo texto/binário na pasta `MQL5/Files` registrando o timestamp do bloqueio e só o remove na liberação.
* **Status:** **PENDENTE DE DECISÃO TÉCNICA (Prioridade: Média)**.

---

## 2. Decisões de Projeto e Plataforma (DQs)

### DQ-001 — Mecanismo de Bloqueio Operacional no MT5
* **Descrição:** Qual é a garantia técnica real que o MetaTrader 5 em MQL5 puro permite oferecer para cumprir o requisito de "bloquear novas operações"?
* **Análise Técnica:**
  * **Abordagem Preventiva (Pré-Ordem):** Um EA comum em MQL5 não pode interceptar a interface gráfica do usuário para desativar o botão de negociação manual do MT5 ou interceptar ordens emitidas diretamente pelo diálogo `F9` sem injeção de DLL (proibida).
  * **Abordagem Reativa Imediata (Pós-Ordem):** O EA monitora o evento `OnTradeTransaction()`. No milissegundo em que uma ordem for convertida em posição ou ordem pendente durante o estado `BLOCKED`, o EA emite uma ordem a mercado imediata de fechamento/cancelamento.
  * **Abordagem de Terminal (`TerminalInfoSetInteger`):** Investigar se a plataforma permite desabilitar o *AlgoTrading* do terminal programaticamente para impedir outros robôs.
* **Ação Necessária:** Realizar um Spike Técnico prático no MT5 antes de iniciar a codificação do EA (ver [W03 no Roadmap](file:///C:/Projetos/eddytrader/docs/09-ROADMAP.md#w03--spike-tecnico-das-capacidades-do-mt5mql5)).
* **Status:** **PENDENTE DE SPIKE TÉCNICO (Prioridade: Crítica)**.

---

### DQ-002 — Tratamento de Contas Netting vs. Hedging
* **Descrição:** Contas Netting (comuns em bolsas de valores como B3) mantêm apenas uma posição consolidada por ativo. Contas Hedging (comuns no mercado Forex internacional) permitem posições simultâneas de compra e venda no mesmo ativo.
* **Por que importa:** A rotina de fechamento de ordens difere no tratamento de posições parciais ou fechamento por ordem oposta (*CloseBy*).
* **Diretriz:** A rotina de liquidação deve ser escrita utilizando a classe padrão de negociação `CTrade` ou rotinas nativas de envio de ordens que identifiquem dinamicamente o modo de conta (`ACCOUNT_MARGIN_MODE`).
* **Status:** **PLANEJADO PARA ESPECIFICAÇÃO TÉCNICA (Prioridade: Alta)**.

---

### DQ-003 — Tolerância a Slippage / Desvio na Execução de Emergência
* **Descrição:** Em momentos de alta volatilidade, o envio de ordens de fechamento a mercado sem desvio máximo configurado (`deviation`) pode gerar rejeição por preço fora de mercado (*requote*). Se configurado com desvio infinito, pode sofrer forte slippage.
* **Decisão Necessária:** Definir a política de desvio aceitável para o fechamento compulsório de emergência. A prioridade de encerramento em emergência costuma exigir execução garantida a qualquer preço de mercado.
* **Status:** **PENDENTE DE VALIDAÇÃO (Prioridade: Média)**.

---

### DQ-004 — Tratamento de Mercado Fechado / Ativos Iíquidos
* **Descrição:** Se uma posição estiver aberta em um símbolo cujo pregão já encerrou (ex: ações no fechamento do dia) e o limite for atingido por perdas em outro ativo ativo (ex: mini-índice), o envio de ordem de fechamento para o ativo fechado retornará erro (`TRADE_RETCODE_MARKET_CLOSED`).
* **Diretriz Prevista:** O tratamento aprovado em [RF-013](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-013) determina que a falha deve ser registrada em log e as demais posições devem continuar sendo processadas. O sistema não deve travar em loop infinito tentando fechar um mercado indisponível.
* **Status:** **REQUISITO FORMALIZADO, PENDENTE DE VERIFICAÇÃO EM TESTE (Prioridade: Média)**.

---

## 3. Riscos Técnicos e Operacionais (RISKs)

| ID | Risco Identificado | Severidade | Probabilidade | Mitigação Proposta |
| :--- | :--- | :--- | :--- | :--- |
| **RISK-001** | **Derrapagem de Execução (Slippage):** A perda final consolidada ultrapassar o limite configurado (ex: limite 500, perda real 540) devido à latência da corretora e slippage em ordens a mercado. | Alta | Alta | Deixar claro na documentação que o limite atua como gatilho de disparo de encerramento, e que a execução final está sujeita aos preços reais fornecidos pela contraparte da corretora. |
| **RISK-002** | **Falsa Sensação de Segurança quanto a Ordens Manuais:** O operador acreditar que o EA desabilitará fisicamente os botões da interface do MetaTrader 5 sem DLLs. | Alta | Média | Formalizar explicitamente que no MT5 puro o bloqueio atua por liquidação e cancelamento reativo imediato de quaisquer operações detectadas na conta durante o período de bloqueio. |
| **RISK-003** | **Divergência de Fusos Horários:** Conflito entre a hora do servidor da corretora e a hora local do computador resultar em desbloqueio em horário indesejado. | Média | Média | Definir de forma inequívoca o relógio de referência utilizado na configuração do horário de liberação. |
| **RISK-004** | **Degradação de Performance por Polling Excessivo:** Loop de monitoramento mal dimensionado consumir 100% da CPU do terminal. | Média | Baixa | Utilizar eventos orientados a tick (`OnTick`) e temporizador controlado (`OnTimer` de no mínimo 500ms a 1s), evitando laços vazios de espera. |
| **RISK-005** | **Perda do Estado de Bloqueio por Reinicialização do Terminal:** Queda de energia ou fechamento do MT5 fazer o EA esquecer que estava bloqueado. | Média | Média | Implementar reconstrução dinâmica com base no histórico contábil do dia ou persistência em arquivo de configuração local. |

---

## 4. Rastreabilidade Documental

* Origem dos Requisitos Afetados: [03 — Requisitos](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md)
* Regras Impactadas: [05 — Regras de Negócio](file:///C:/Projetos/eddytrader/docs/05-REGRAS-DE-NEGOCIO.md)
* Alinhamento no Cronograma: [09 — Roadmap](file:///C:/Projetos/eddytrader/docs/09-ROADMAP.md)
