# AGENTS.md — Diretrizes Normativas para Agentes de IA

Este documento estabelece as regras de conduta, restrições arquiteturais e protocolos operacionais para **qualquer agente de Inteligência Artificial** que atue no repositório **EddyTrader**.

A observância deste documento é obrigatória e incondicional.

---

## 1. Princípios de Atuação do Agente

Todo agente que interagir com este repositório deve operar sob os preceitos do **Método C.H.**:

1. **Clareza antes de código:** Não escreva código se houver dúvida sobre o requisito ou a regra de negócio.
2. **Escopo mínimo:** Execute estritamente o que foi autorizado na Work Package (W) corrente.
3. **Evidência antes de expansão:** Não adicione recursos imaginando utilidade futura.
4. **Documentação como contrato:** O código deve espelhar a documentação, e a documentação deve refletir o estado real acordado.
5. **Rastreabilidade total:** Mantenha a ligação entre requisitos (RF/RNF), regras (RN), casos de uso (UC) e testes.
6. **Decisões explícitas:** Nunca assuma tacitamente uma resposta para um ponto em aberto.

---

## 2. As 12 Regras Inegociáveis

Qualquer agente atuando neste repositório deve:

1. **Ler o `AGENTS.md`:** Compreender e respeitar todas as instruções deste guia antes de qualquer ação.
2. **Consultar a documentação normativa:** Ler os documentos da pasta `docs/` pertinentes à sua tarefa antes de modificar arquivos.
3. **Respeitar rigorosamente o escopo:** Obedecer às fronteiras estabelecidas em [02-ESCOPO-E-LIMITES.md](file:///C:/Projetos/eddytrader/docs/02-ESCOPO-E-LIMITES.md).
4. **Não implementar funcionalidades não autorizadas:** Aderir estritamente ao princípio YAGNI. Não adicione telas, alertas externos, relatórios ou recursos sem pedido explícito.
5. **Não transformar questões abertas em decisões:** Se deparar com uma ambiguidade catalogada em [08-RISCOS-E-QUESTOES-ABERTAS.md](file:///C:/Projetos/eddytrader/docs/08-RISCOS-E-QUESTOES-ABERTAS.md), preserve o requisito original e solicite a deliberação do usuário.
6. **Preferir mudanças pequenas e atômicas:** Realizar alterações cirúrgicas, focadas no objetivo da W atual.
7. **Manter rastreabilidade:** Identificar os IDs dos requisitos (RF-xxx), regras (RN-xxx) ou decisões (GAP-xxx / DQ-xxx) afetados por suas alterações.
8. **Atualizar a documentação quando uma decisão mudar:** Toda definição validada deve ser formalmente registrada nos documentos de `docs/`.
9. **Não adicionar dependências externas:** É proibido usar DLLs, bancos de dados, conexões WebRequest, microsserviços, scripts externos em Python, Docker ou pacotes de terceiros.
10. **Utilizar exclusivamente MQL5 para o produto:** O Expert Advisor e seus módulos de biblioteca devem ser escritos 100% em **MQL5 nativo** compatível com o compilador MetaEditor do MetaTrader 5.
11. **Não implementar estratégia de trading:** O EddyTrader é um gerenciador de perda diária; é terminantemente proibido programar sinais de entrada, indicadores, trailing stop ou gestão de metas de ganho.
12. **Não ultrapassar os limites da W autorizada:** Não avance para tarefas de Work Packages futuras sem que a W atual tenha sido formalmente concluída e aceita pelo usuário.

---

## 3. Ordem Recomendada de Leitura da Documentação

Ao iniciar uma nova sessão de trabalho ou receber uma nova missão, o agente deve ler os documentos na seguinte ordem:

1. [AGENTS.md](file:///C:/Projetos/eddytrader/AGENTS.md) — Regras de engajamento do agente.
2. [README.md](file:///C:/Projetos/eddytrader/README.md) — Visão executiva e status do projeto.
3. [docs/00-MANIFESTO.md](file:///C:/Projetos/eddytrader/docs/00-MANIFESTO.md) — Filosofia e propósito inegociável.
4. [docs/02-ESCOPO-E-LIMITES.md](file:///C:/Projetos/eddytrader/docs/02-ESCOPO-E-LIMITES.md) — Fronteiras do que é permitido e expressamente proibido.
5. [docs/01-VISAO-GERAL.md](file:///C:/Projetos/eddytrader/docs/01-VISAO-GERAL.md) — Funcionamento do produto e relação com o MT5.
6. [docs/03-REQUISITOS.md](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md) — Requisitos funcionais e não-funcionais rastreáveis.
7. [docs/05-REGRAS-DE-NEGOCIO.md](file:///C:/Projetos/eddytrader/docs/05-REGRAS-DE-NEGOCIO.md) — Regras normativas de cálculo e ação.
8. [docs/06-ARQUITETURA-CONCEITUAL.md](file:///C:/Projetos/eddytrader/docs/06-ARQUITETURA-CONCEITUAL.md) — Decomposição conceitual e máquina de estados.
9. [docs/08-RISCOS-E-QUESTOES-ABERTAS.md](file:///C:/Projetos/eddytrader/docs/08-RISCOS-E-QUESTOES-ABERTAS.md) — GAPs, decisões técnicas e riscos ativos.
10. [docs/adr/](file:///C:/Projetos/eddytrader/docs/adr/) — Registros formais de decisões arquiteturais (ADR 0001 e 0002).
11. [docs/09-ROADMAP.md](file:///C:/Projetos/eddytrader/docs/09-ROADMAP.md) — Etapas planejadas e critérios da W corrente.
12. [docs/04-CASOS-DE-USO.md](file:///C:/Projetos/eddytrader/docs/04-CASOS-DE-USO.md) — Casos de uso do operador e do sistema.
13. [docs/07-MVP.md](file:///C:/Projetos/eddytrader/docs/07-MVP.md) — Critérios de aceite do produto mínimo viável.

---

## 4. Política de Tratamento de Ambiguidade

Caso o agente encontre um ponto do código ou da especificação que admita mais de uma interpretação:

* **O que NÃO fazer:** Escolher silenciosamente a alternativa mais conveniente, inventar uma convenção própria ou implementar sem avisar.
* **O que FAZER:**
  1. Registrar a ambiguidade em `docs/08-RISCOS-E-QUESTOES-ABERTAS.md` sob a taxonomia `GAP-xxx` ou `DQ-xxx`.
  2. Apresentar o problema ao usuário, explicando o impacto técnico e as opções disponíveis.
  3. Aguardar a validação explícita antes de codificar.
