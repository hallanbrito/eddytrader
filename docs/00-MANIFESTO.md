# 00 — Manifesto do Disciplinador Trader

> **"Disciplinador Trader é uma ferramenta de controle de risco operacional e salvaguarda da disciplina do operador, não uma estratégia de trading."**
> *(Nome de projeto interno e repositório: **EddyTrader**)*

---

## 1. O Problema

Nos mercados financeiros alavancados, a maior causa de destruição de capital não reside na imperfeição dos modelos estatísticos ou na análise gráfica equivocada. Reside na **falência do controle comportamental e operacional do operador**.

Fenômenos psicológicos severos — como o *tilt*, o *overtrading*, a vingança contra o mercado (*revenge trading*) e a paralisia decisória diante de perdas crescentes — levam operadores a violar suas próprias regras financeiras. Pequenas perdas aceitáveis transformam-se, em minutos, em perdas catastróficas capazes de dizimar contas inteiras.

Operadores necessitam de um guardião automatizado, frio e inflexível: um mecanismo capaz de agir no momento exato em que a dor emocional impede o ser humano de interromper a hemorragia financeira.

---

## 2. O Propósito

O propósito do **Disciplinador Trader** é **garantir a sobrevivência do operador**.

O Disciplinador Trader existe para impor, de maneira técnica, automática e implacável, o limite monetário diário de perda definido pelo usuário. Sua missão se resume a:

1. Monitorar o resultado financeiro relevante em nível global de conta.
2. Identificar a violação do limite monetário de perda.
3. Liquidar compulsoriamente todas as posições abertas.
4. Cancelar todas as ordens pendentes.
5. Impedir novas negociações durante a janela de bloqueio.
6. Liberar as operações apenas quando o tempo programado (4 horas) for atingido.

---

## 3. Filosofia Fundamental

O desenvolvimento e a evolução do Disciplinador Trader apoiam-se em cinco princípios intransigíveis:

### 3.1. Proteção do Operador Acima de Tudo
A preservação do capital presente é a única condição que permite a existência de lucros futuros. Nenhum ganho hipotético justifica a ausência de uma trava absoluta de destruição de capital.

### 3.2. Simplicidade Radical (KISS e YAGNI)
Fazer uma única coisa com precisão impecável. Qualquer sofisticação desnecessária introduz pontos de falha que podem comprometer a execução da ordem de emergência quando o capital estiver em risco iminente.

### 3.3. Previsibilidade e Determinismo
O comportamento do sistema deve ser 100% determinístico. Diante das mesmas condições de saldo, resultado e tempo, o Disciplinador Trader sempre executará as mesmas ações, sem variações ocultas ou decisões probabilísticas.

### 3.4. Soberania do Risco, Neutralidade da Estratégia
O Disciplinador Trader é agnóstico à forma como o operador negocia. Ele não julga compras, vendas, tempos gráficos ou indicadores. Sua autoridade se manifesta exclusivamente quando a barreira de risco é rompida.

### 3.5. Soberania e Nativismo em MQL5
O sistema deve rodar diretamente no motor nativo do **MetaTrader 5**. Não haverá dependência de intermediários, DLLs, servidores externos, bancos de dados ou conexões de rede que possam falhar no milissegundo em que a conta precisa ser protegida.

---

## 4. Limites Fundamentais (O Que o Disciplinador Trader NUNCA Será)

Para preservar sua integridade conceitual e técnica, o Disciplinador Trader estabelece proibições permanentes:

* **Não é um gerador de sinais:** jamais analisará tendências, suportes, resistências ou osciladores.
* **Não é uma estratégia de trading:** jamais abrirá posições de compra ou venda por iniciativa própria.
* **Não é um gestor de metas de ganho:** não calcula alvos de lucro diário, parciais ou trailing stop.
* **Não utiliza Inteligência Artificial:** recusa expressamente modelos preditivos, redes neurais ou heurísticas complexas.
* **Não utiliza infraestrutura externa:** recusa bancos de dados, APIs web, serviços em nuvem ou bibliotecas de terceiros.

---

## 5. Relação Documental

Este manifesto é a âncora filosófica de todos os documentos normativos do projeto:

* [01 — Visão Geral](file:///C:/Projetos/eddytrader/docs/01-VISAO-GERAL.md)
* [02 — Escopo e Limites](file:///C:/Projetos/eddytrader/docs/02-ESCOPO-E-LIMITES.md)
* [03 — Requisitos](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md)
* [04 — Casos de Uso](file:///C:/Projetos/eddytrader/docs/04-CASOS-DE-USO.md)
* [05 — Regras de Negócio](file:///C:/Projetos/eddytrader/docs/05-REGRAS-DE-NEGOCIO.md)
* [06 — Arquitetura Conceitual](file:///C:/Projetos/eddytrader/docs/06-ARQUITETURA-CONCEITUAL.md)
* [07 — MVP](file:///C:/Projetos/eddytrader/docs/07-MVP.md)
* [08 — Riscos e Questões Abertas](file:///C:/Projetos/eddytrader/docs/08-RISCOS-E-QUESTOES-ABERTAS.md)
* [09 — Roadmap](file:///C:/Projetos/eddytrader/docs/09-ROADMAP.md)
