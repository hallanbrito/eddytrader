# 03 — Requisitos do Sistema

Este documento formaliza todos os requisitos do **EddyTrader**, estabelecendo identificadores rastreáveis, origens contratuais, prioridades e critérios verificáveis de aceite, atualizados com as deliberações da **W02** (incluindo o esclarecimento de requisito do Product Owner sobre a duração de 4 horas do bloqueio).

---

## 1. Requisitos Funcionais (RF)

| ID | Descrição | Origem | Prioridade | Condição Verificável |
| :--- | :--- | :--- | :--- | :--- |
| **RF-001** | O sistema deve permitir ao operador configurar o limite máximo de perda diária em valor monetário na moeda da conta. | Requisito Aprovado (Seção 2) | Essencial | O EA disponibiliza parâmetro de entrada numérico positivo (ex: `500.00`). Parâmetro é validado na inicialização ($L > 0$). |
| **RF-002** | O sistema deve aplicar o tempo de bloqueio operacional aprovado de 4 horas contínuas a partir do instante do disparo da proteção. | Requisito Aprovado / W02 (D01, D07 — Atualizada por esclarecimento do PO) | Essencial | A duração do bloqueio é de 4 horas a contar do instante em que o limite for atingido no relógio do servidor ($t_{\text{unlock}} = t_{\text{bloqueio}} + 4\text{h}$). *(Corrigido: substitui a interpretação preliminar de horário fixo absoluto diário)*. |
| **RF-003** | O sistema deve acompanhar continuamente o resultado realizado do dia operacional (`00:00:00` a `23:59:59` do servidor), incluindo custos e excluindo movimentações de capital. | Requisito Aprovado (Seção 2) / W02 (D02, D04, D05) | Essencial | O EA totaliza lucros, prejuízos, comissões e swaps de negócios fechados no dia, desconsiderando depósitos e saques. |
| **RF-004** | O sistema deve acompanhar continuamente o resultado financeiro flutuante (*unrealized PnL*) de todas as posições abertas na conta, incluindo as mantidas após a virada do dia. | Requisito Aprovado (Seção 2) / W02 (D06) | Essencial | O EA lê em tempo real o flutuante líquido consolidado de todas as posições abertas na conta. |
| **RF-005** | O sistema deve detectar quando o resultado financeiro relevante consolidado for menor ou igual ao negativo do limite monetário diário (ou da janela ativa). | Requisito Aprovado (Seção 2) / W02 (D03) / W03 | Essencial | O gatilho de proteção dispara no milissegundo em que $W_n(t) \le -L$, onde $W_n(t) = D(t) - B_n$, conforme [10-ESPECIFICACAO-MATEMATICA.md](file:///C:/Projetos/eddytrader/docs/10-ESPECIFICACAO-MATEMATICA.md). |
| **RF-006** | O sistema deve fechar compulsoriamente todas as posições abertas na conta no momento do disparo da proteção, em escopo global da conta. | Requisito Aprovado (Seção 2) / W02 (D13) | Essencial | Emissão imediata de requisições de fechamento a mercado para 100% das posições abertas na conta, sem filtro de símbolo ou Magic Number. |
| **RF-007** | O sistema deve cancelar compulsoriamente todas as ordens pendentes da conta no momento do disparo da proteção, em escopo global da conta. | Requisito Aprovado (Seção 2) / W02 (D17) | Essencial | Emissão imediata de requisições de cancelamento para 100% das ordens pendentes existentes na conta. |
| **RF-008** | O sistema deve impedir que o operador continue com operações ativas durante o período de bloqueio após o acionamento da proteção. | Requisito Aprovado (Seção 2) / W02 (D18) | Essencial | Durante o estado de bloqueio, novas operações detectadas na conta não permanecem abertas. |
| **RF-009** | O sistema deve informar visualmente no gráfico que o limite diário foi atingido, detalhando o fechamento e o horário do servidor previsto para liberação. | Requisito Aprovado (Seção 2) / W02 (D19) | Alta | Exibição visual contínua no gráfico indicando limite atingido, posições encerradas e liberação no horário calculado ($t_{\text{bloqueio}} + 4\text{h}$) no relógio do servidor. |
| **RF-010** | O sistema deve manter o bloqueio operacional por 4 horas contínuas, liberando automaticamente ao término da janela mesmo se houver virada de dia. | Requisito Aprovado / W02 (D08, D10, D11 — Atualizadas) | Essencial | O bloqueio vigora ininterruptamente pelo intervalo $[t_{\text{bloqueio}}, t_{\text{bloqueio}} + 4\text{h})$. A passagem de `00:00:00` não cancela o bloqueio, que se estende ao dia seguinte até completar integralmente as 4 horas. |
| **RF-011** | O sistema deve informar visualmente no gráfico que o bloqueio foi removido e as operações foram liberadas. | Requisito Aprovado (Seção 2) | Alta | Exibição visual no gráfico informando: *"Bloqueio removido. Operações liberadas."*. |
| **RF-012** | O sistema deve reiniciar o monitoramento criando uma nova janela de proteção a partir de uma baseline de reabertura após o desbloqueio. | Requisito Aprovado (Seção 2) / W02 (D09) / W03 (GAP-006) | Essencial | A liberação não apaga o histórico contábil do dia e estabelece nova baseline $B_n = D(t_{\text{reopen}, n})$ para evitar rebloqueio imediato no mesmo tick ($W_n(t_{\text{reopen}}) = 0$), conforme [ADR 0003](file:///C:/Projetos/eddytrader/docs/adr/0003-modelo-matematico-de-janelas-e-baseline.md). |
| **RF-013** | O sistema deve registrar em log falhas de fechamento sem interromper o EA, mantendo o estado de proteção ativo enquanto houver posições não encerradas. | Tratamento de Erros Aprovado (Seção 4) / W02 (D16) | Essencial | Falha individual gera log detalhado; o EA continua liquidando as demais posições e não retorna ao estado nominal de monitoramento se houver pendência ativa. |
| **RF-014** | O sistema deve operar conceitualmente como uma instância única por conta de negociação. | W02 (D14) | Alta | O EA não deve disputar o controle da conta com outras instâncias ativas do Disciplinador Trader. |
| **RF-015** | O Disciplinador Trader deve monitorar e proteger toda a conta independentemente do símbolo/timeframe do gráfico onde estiver anexado e independentemente da origem das operações. | Requisito Formal W10 | Essencial | Monitoramento contínuo, liquidação compulsória e neutralização durante bloqueio abrangem 100% das ordens e posições da conta, agnósticas ao símbolo do gráfico hospedeiro, permitindo convivência com Chart Trade ou outros EAs com Magic Numbers arbitrários em gráficos separados. |

---

## 2. Requisitos Não-Funcionais (RNF)

| ID | Descrição | Origem | Prioridade | Condição Verificável |
| :--- | :--- | :--- | :--- | :--- |
| **RNF-001** | O produto deve ser desenvolvido exclusivamente em MQL5 nativo para a plataforma MetaTrader 5. | Contexto do Produto / AGENTS.md | Crítica | O código-fonte final deve consistir apenas de arquivos compatíveis com o compilador MetaEditor / MQL5 (`.mq5` / `.mqh`). |
| **RNF-002** | O sistema deve priorizar simplicidade arquitetural, código limpo e estrita aderência ao princípio YAGNI. | Requisitos Não-Funcionais / AGENTS.md | Alta | Ausência de abstrações desnecessárias, interfaces visuais complexas ou recursos não requisitados. |
| **RNF-003** | O sistema deve operar com baixo consumo de CPU e memória, não degradando o terminal MT5. | Requisitos Não-Funcionais | Alta | Processamento dirigido por eventos (`OnTick`) e temporizador com taxa controlada (`OnTimer`), sem loops ocupados. |
| **RNF-004** | O comportamento do sistema deve ser seguro, previsível e priorizar a reconstrução determinística de estado via histórico nativo após reinicializações. | RNF / W02 (D12) / W03 (GAP-005) | Alta | Máquina de estados formal com identificação clara dos dados de estado conceituais necessários para integridade pós-restart. |
| **RNF-005** | Todas as ações críticas, erros comerciais e mudanças de estado devem ser auditáveis via log local (`Print`). | Requisitos Não-Funcionais | Alta | Emissão de mensagens estruturadas no Diário do terminal com timestamps oficiais do servidor de negociação. |
| **RNF-006** | O monitoramento deve ocorrer em tempo real compatível com a exigência de contenção de risco intradiário. | Requisitos Não-Funcionais | Essencial | Verificação a cada tick e em ciclos de timer rápidos suficientes para contenção imediata. |
| **RNF-007** | O sistema deve ser homologado com 100% de sucesso em Conta Demo antes de qualquer recomendação para Conta Real. | RNF / W02 (D20) | Crítica | A validação do MVP exige cumprimento integral dos critérios de teste em simulação antes da transição para produção. |
| **RNF-008** | O sistema deve funcionar independentemente do ativo/símbolo financeiro negociado. | Requisitos Não-Funcionais | Essencial | As rotinas de monitoramento e encerramento atuam sobre todos os símbolos ativos na conta. |
| **RNF-009** | O sistema deve funcionar de forma independente da estratégia ou método adotado pelo operador. | Requisitos Não-Funcionais | Essencial | O EA não assume nenhum conhecimento prévio sobre a lógica de entrada das operações. |
| **RNF-010** | O sistema não deve utilizar nenhuma dependência externa, DLL, API remota, banco de dados ou programa auxiliar. | Contexto do Produto / AGENTS.md | Crítica | O artefato final roda em ambiente isolado padrão do MT5 com zero dependências externas. |

---

## 3. Rastreabilidade Documental

* Casos de Uso: [04 — Casos de Uso](file:///C:/Projetos/eddytrader/docs/04-CASOS-DE-USO.md)
* Regras Normativas: [05 — Regras de Negócio](file:///C:/Projetos/eddytrader/docs/05-REGRAS-DE-NEGOCIO.md)
* Especificação Matemática: [10 — Especificação Matemática](file:///C:/Projetos/eddytrader/docs/10-ESPECIFICACAO-MATEMATICA.md)
* Máquina de Estados Finita: [11 — Máquina de Estados](file:///C:/Projetos/eddytrader/docs/11-MAQUINA-DE-ESTADOS.md)
* Decisões Arquiteturais: [ADR 0001](file:///C:/Projetos/eddytrader/docs/adr/0001-regras-temporais-e-janelas-de-protecao.md), [ADR 0002](file:///C:/Projetos/eddytrader/docs/adr/0002-composicao-da-perda-operacional.md), [ADR 0003](file:///C:/Projetos/eddytrader/docs/adr/0003-modelo-matematico-de-janelas-e-baseline.md) e [ADR 0004](file:///C:/Projetos/eddytrader/docs/adr/0004-maquina-de-estados-e-recuperacao.md)
* Riscos e Lacunas: [08 — Riscos e Questões Abertas](file:///C:/Projetos/eddytrader/docs/08-RISCOS-E-QUESTOES-ABERTAS.md)
