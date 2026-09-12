# 03 — Requisitos do Sistema

Este documento formaliza todos os requisitos do **EddyTrader**, estabelecendo identificadores rastreáveis, origens contratuais, prioridades e critérios verificáveis de aceite.

---

## 1. Requisitos Funcionais (RF)

| ID | Descrição | Origem | Prioridade | Condição Verificável |
| :--- | :--- | :--- | :--- | :--- |
| **RF-001** | O sistema deve permitir ao operador configurar o limite máximo de perda diária em valor monetário na moeda da conta. | Requisito Aprovado (Seção 2) | Essencial | O EA disponibiliza parâmetro de entrada numérico positivo (ex: `500.00`). Parâmetro é carregado na inicialização. |
| **RF-002** | O sistema deve permitir ao operador configurar o horário no qual as operações poderão ser liberadas novamente após o bloqueio. | Requisito Aprovado (Seção 2) | Essencial | O EA disponibiliza parâmetro de entrada textual ou horário (ex: `16:00`). Parâmetro é validado na inicialização. |
| **RF-003** | O sistema deve acompanhar continuamente o resultado financeiro realizado da conta durante o período considerado. | Requisito Aprovado (Seção 2) | Essencial | O EA consulta o histórico diário da conta e totaliza lucros e perdas de operações já encerradas no período. |
| **RF-004** | O sistema deve acompanhar continuamente o resultado financeiro flutuante (*unrealized profit/loss*) de todas as posições abertas. | Requisito Aprovado (Seção 2) | Essencial | O EA lê o lucro/prejuízo em tempo real de cada posição aberta e atualiza o montante flutuante da conta. |
| **RF-005** | O sistema deve detectar quando o prejuízo acumulado relevante atingir ou ultrapassar o limite monetário diário configurado. | Requisito Aprovado (Seção 2) | Essencial | Se a perda acumulada (realizada + flutuante relevante) for igual ou superior ao limite (ex: perda de 503 com limite de 500), dispara gatilho de proteção. |
| **RF-006** | O sistema deve fechar compulsoriamente todas as posições abertas na conta no momento em que o limite for atingido ou ultrapassado. | Requisito Aprovado (Seção 2) | Essencial | Ao ser disparada a proteção, requisições de fechamento a mercado são emitidas para 100% das posições abertas na conta. |
| **RF-007** | O sistema deve cancelar compulsoriamente todas as ordens pendentes da conta no momento em que o limite for atingido ou ultrapassado. | Requisito Aprovado (Seção 2) | Essencial | Ao ser disparada a proteção, requisições de cancelamento são emitidas para 100% das ordens pendentes na conta. |
| **RF-008** | O sistema deve impedir que o operador continue negociando durante o período de bloqueio após o acionamento do limite. | Requisito Aprovado (Seção 2) | Essencial | Durante o estado de bloqueio, novas operações detectadas ou submetidas são barradas ou imediatamente neutralizadas. |
| **RF-009** | O sistema deve informar visualmente no gráfico que o limite diário foi atingido, detalhando o fechamento e o horário de liberação. | Requisito Aprovado (Seção 2) | Alta | Exibição de mensagem visível no gráfico do tipo: *"Limite diário atingido. Todas as operações foram encerradas. Novas operações bloqueadas. Liberação às [horário]"*. |
| **RF-010** | O sistema deve remover automaticamente o bloqueio operacional quando o horário configurado for atingido. | Requisito Aprovado (Seção 2) | Essencial | Ao atingir o horário definido em RF-002, o estado muda de bloqueado para desbloqueado/liberado. |
| **RF-011** | O sistema deve informar visualmente no gráfico que o bloqueio foi removido e as operações foram liberadas. | Requisito Aprovado (Seção 2) | Alta | Exibição de mensagem visível no gráfico do tipo: *"Bloqueio removido. Operações liberadas."*. |
| **RF-012** | O sistema deve continuar o monitoramento normalmente após a liberação das operações. | Requisito Aprovado (Seção 2) | Essencial | Após o desbloqueio, o sistema retorna ao estado de vigilância ativa de perdas e operações. |
| **RF-013** | O sistema deve registrar em log falhas de fechamento ou cancelamento sem interromper a execução do EA e continuar processando os demais itens. | Tratamento de Erros Aprovado (Seção 4) | Essencial | Se o fechamento de uma posição falhar (ex: rejeição da corretora), o erro é registrado no log e as posições subsequentes são processadas normalmente. |

---

## 2. Requisitos Não-Funcionais (RNF)

| ID | Descrição | Origem | Prioridade | Condição Verificável |
| :--- | :--- | :--- | :--- | :--- |
| **RNF-001** | O produto deve ser desenvolvido exclusivamente em MQL5 nativo para a plataforma MetaTrader 5. | Contexto do Produto (Seção 1) | Crítica | O código-fonte final deve consistir apenas de arquivos compatíveis com o compilador MetaEditor / MQL5 (`.mq5` / `.mqh`). |
| **RNF-002** | O sistema deve priorizar simplicidade arquitetural, código limpo e estrita aderência ao princípio YAGNI. | Requisitos Não-Funcionais (Seção 5 e 6) | Alta | Inexistência de abstrações desnecessárias, heranças complexas ou código não justificado por requisito funcional direto. |
| **RNF-003** | O sistema deve operar com baixo consumo de CPU e memória, não degradando o desempenho do terminal MT5. | Requisitos Não-Funcionais (Seção 5) | Alta | O loop de monitoramento deve evitar chamadas excessivas redundantes que saturem a thread de interface ou negociação. |
| **RNF-004** | O comportamento do sistema deve ser seguro, previsível e determinístico em todas as transições de estado. | Tratamento de Erros / RNF (Seção 4 e 5) | Alta | Estados e transições são mutuamente exclusivos e definidos por máquina de estados finita formal. |
| **RNF-005** | Todas as ações operacionais críticas, erros de execução e mudanças de estado devem ser rastreáveis via log local. | Requisitos Não-Funcionais (Seção 5) | Alta | Emissão de mensagens estruturadas com timestamp e código de retorno através da função nativa `Print()` no diário do MT5. |
| **RNF-006** | O monitoramento deve ocorrer em tempo real compatível com a exigência de gestão de risco intradiário. | Requisitos Não-Funcionais (Seção 5) | Essencial | A verificação de risco deve responder a cada tick de mercado (`OnTick`) e/ou em intervalos temporais curtos de alta frequência (`OnTimer`). |
| **RNF-007** | O sistema deve funcionar de forma idêntica e sem restrições em contas de simulação (**Demo**) e contas com saldo real (**Real**). | Requisitos Não-Funcionais (Seção 5) | Essencial | Ausência de validações ou diferenciações de comportamento baseadas no tipo de conta retornado pelo terminal. |
| **RNF-008** | O sistema deve funcionar independentemente do ativo/símbolo financeiro negociado. | Requisitos Não-Funcionais (Seção 5) | Essencial | As rotinas de consulta de posições e fechamento devem iterar por todos os símbolos ativos na conta do operador. |
| **RNF-009** | O sistema deve funcionar de forma independente da estratégia ou método adotado pelo operador. | Requisitos Não-Funcionais (Seção 5) | Essencial | O EA não assume nenhum conhecimento prévio sobre como ou por que as ordens foram abertas. |
| **RNF-010** | O sistema não deve utilizar nenhuma dependência externa, DLL, API remota, banco de dados ou programa auxiliar. | Contexto do Produto (Seção 1 e 6) | Crítica | O artefato final roda em ambiente isolado padrão do MT5 sem necessidade de habilitar "Permitir DLL" ou requisições WebRequest. |

---

## 3. Rastreabilidade Documental

* Mapeamento de Casos de Uso: [04 — Casos de Uso](file:///C:/Projetos/eddytrader/docs/04-CASOS-DE-USO.md)
* Regras de Negócio Associadas: [05 — Regras de Negócio](file:///C:/Projetos/eddytrader/docs/05-REGRAS-DE-NEGOCIO.md)
* Lacunas e Incertezas a Resolver: [08 — Riscos e Questões Abertas](file:///C:/Projetos/eddytrader/docs/08-RISCOS-E-QUESTOES-ABERTAS.md)
